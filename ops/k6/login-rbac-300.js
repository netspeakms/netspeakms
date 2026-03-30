import http from "k6/http";
import { check } from "k6";
import { Rate } from "k6/metrics";
import { SharedArray } from "k6/data";
import exec from "k6/execution";

const BASE_URL = __ENV.BASE_URL || "https://app.netspeak.com.ph";
const USERS_CSV = __ENV.USERS_CSV || "./rbac-users.csv";

const TOTAL_VUS = Number(__ENV.TOTAL_VUS || 300);
const ADMIN_PCT = Number(__ENV.ADMIN_PCT || 0.1);
const STAFF_PCT = Number(__ENV.STAFF_PCT || 0.2);

function safePct(n, fallback) {
  if (Number.isFinite(n) && n >= 0 && n <= 1) return n;
  return fallback;
}

const ADMIN_RATIO = safePct(ADMIN_PCT, 0.1);
const STAFF_RATIO = safePct(STAFF_PCT, 0.2);
let adminVUs = Math.max(1, Math.round(TOTAL_VUS * ADMIN_RATIO));
let staffVUs = Math.max(1, Math.round(TOTAL_VUS * STAFF_RATIO));
let teacherVUs = TOTAL_VUS - adminVUs - staffVUs;
if (teacherVUs < 1) {
  teacherVUs = 1;
  const overflow = adminVUs + staffVUs + teacherVUs - TOTAL_VUS;
  if (overflow > 0) {
    if (adminVUs >= staffVUs) adminVUs = Math.max(1, adminVUs - overflow);
    else staffVUs = Math.max(1, staffVUs - overflow);
  }
}

export const loginOk = new Rate("login_ok");
export const roleLandingOk = new Rate("role_landing_ok");

function parseCsv(text) {
  const lines = text
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"));

  if (lines.length < 2) return [];

  const headers = lines[0].split(",").map((h) => h.trim().toLowerCase());
  const roleIdx = headers.indexOf("role");
  const userIdx = headers.indexOf("username");
  const passIdx = headers.indexOf("password");

  if (roleIdx === -1 || userIdx === -1 || passIdx === -1) {
    throw new Error("CSV must have headers: role,username,password");
  }

  const items = [];
  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(",").map((c) => c.trim());
    if (!cols[roleIdx] || !cols[userIdx] || !cols[passIdx]) continue;
    items.push({
      role: cols[roleIdx].toLowerCase(),
      username: cols[userIdx],
      password: cols[passIdx],
    });
  }
  return items;
}

const allUsers = new SharedArray("rbac_users", () => parseCsv(open(USERS_CSV)));
const usersByRole = {
  admin: allUsers.filter((u) => u.role === "admin"),
  staff: allUsers.filter((u) => u.role === "staff"),
  teacher: allUsers.filter((u) => u.role === "teacher"),
};

function pickUser(role) {
  const pool = usersByRole[role] || [];
  if (pool.length === 0) return null;
  const idx = (exec.vu.idInTest - 1) % pool.length;
  return pool[idx];
}

function loginFlow(role, landingPath) {
  const user = pickUser(role);
  if (!user) {
    loginOk.add(false, { role });
    roleLandingOk.add(false, { role });
    return;
  }

  const csrfRes = http.get(`${BASE_URL}/api/auth/csrf`, {
    tags: { name: "GET /api/auth/csrf", role },
    responseCallback: http.expectedStatuses(200),
  });
  const csrfOk = check(csrfRes, {
    [`${role} csrf 200`]: (r) => r.status === 200,
  });

  let csrfToken = "";
  try {
    csrfToken = csrfRes.json("csrfToken") || "";
  } catch (_) {
    csrfToken = "";
  }

  const loginRes = http.post(
    `${BASE_URL}/api/auth/callback/credentials`,
    {
      username: user.username,
      password: user.password,
      redirect: "false",
      csrfToken,
      callbackUrl: `${BASE_URL}/login`,
      json: "true",
    },
    {
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      tags: { name: "POST /api/auth/callback/credentials", role },
      responseCallback: http.expectedStatuses(200),
    }
  );
  const loginPostOk = check(loginRes, {
    [`${role} login POST 200`]: (r) => r.status === 200,
  });

  const sessionRes = http.get(`${BASE_URL}/api/auth/session`, {
    tags: { name: "GET /api/auth/session", role },
    responseCallback: http.expectedStatuses(200),
  });

  let hasUser = false;
  try {
    hasUser = !!sessionRes.json("user");
  } catch (_) {
    hasUser = false;
  }
  const sessionOk = check(sessionRes, {
    [`${role} session has user`]: () => hasUser,
  });

  const fullLoginOk = csrfOk && loginPostOk && sessionOk;
  loginOk.add(fullLoginOk, { role });

  const landingRes = http.get(`${BASE_URL}${landingPath}`, {
    tags: { name: `GET ${landingPath}`, role },
    responseCallback: http.expectedStatuses(200, 302, 307),
  });
  const landingOk = check(landingRes, {
    [`${role} landing reachable`]: (r) => [200, 302, 307].includes(r.status),
  });
  roleLandingOk.add(landingOk, { role });
}

export const options = {
  scenarios: {
    admin_login: {
      executor: "per-vu-iterations",
      vus: adminVUs,
      iterations: 1,
      maxDuration: "2m",
      exec: "adminLogin",
    },
    staff_login: {
      executor: "per-vu-iterations",
      vus: staffVUs,
      iterations: 1,
      maxDuration: "2m",
      exec: "staffLogin",
    },
    teacher_login: {
      executor: "per-vu-iterations",
      vus: teacherVUs,
      iterations: 1,
      maxDuration: "2m",
      exec: "teacherLogin",
    },
  },
  thresholds: {
    login_ok: ["rate>=0.95"],
    role_landing_ok: ["rate>=0.95"],
    http_req_failed: ["rate<0.05"],
  },
};

export function setup() {
  if (usersByRole.admin.length < adminVUs) {
    throw new Error(`Need at least ${adminVUs} admin users in ${USERS_CSV}`);
  }
  if (usersByRole.staff.length < staffVUs) {
    throw new Error(`Need at least ${staffVUs} staff users in ${USERS_CSV}`);
  }
  if (usersByRole.teacher.length < teacherVUs) {
    throw new Error(`Need at least ${teacherVUs} teacher users in ${USERS_CSV}`);
  }
}

export function adminLogin() {
  loginFlow("admin", "/admin");
}

export function staffLogin() {
  loginFlow("staff", "/dashboard/services");
}

export function teacherLogin() {
  loginFlow("teacher", "/dashboard");
}
