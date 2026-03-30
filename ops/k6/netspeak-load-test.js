import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "https://app.netspeak.com.ph";
const USERNAME = __ENV.K6_USERNAME || "";
const PASSWORD = __ENV.K6_PASSWORD || "";

export const options = {
  stages: [
    { target: 50, duration: "1m" },
    { target: 100, duration: "1m" },
    { target: 200, duration: "1m" },
    { target: 300, duration: "2m" },
    { target: 300, duration: "3m30s" },
    { target: 0, duration: "1m" },
  ],
  thresholds: {
    http_req_failed: ["rate<0.02"],
    http_req_duration: ["p(95)<2500", "p(99)<5000"],
    checks: ["rate>0.95"],
  },
};

function expectStatus(resp, allowed, label) {
  return check(resp, {
    [`${label} status in [${allowed.join(",")}]`]: (r) => allowed.includes(r.status),
  });
}

function requestParams(allowedStatuses, params = {}) {
  // Keep http_req_failed aligned with endpoint-specific expected outcomes.
  return {
    ...params,
    responseCallback: http.expectedStatuses(...allowedStatuses),
  };
}

function getCsrfToken() {
  const allowed = [200];
  const resp = http.get(
    `${BASE_URL}/api/auth/csrf`,
    requestParams(allowed, {
      headers: { accept: "application/json" },
    })
  );

  expectStatus(resp, allowed, "GET /api/auth/csrf");

  try {
    return resp.json("csrfToken") || "";
  } catch (_) {
    return "";
  }
}

function tryLogin(csrfToken) {
  if (!USERNAME || !PASSWORD || !csrfToken) return false;

  const payload = {
    username: USERNAME,
    password: PASSWORD,
    redirect: "false",
    csrfToken,
    callbackUrl: `${BASE_URL}/login`,
    json: "true",
  };

  const allowed = [200];
  const resp = http.post(
    `${BASE_URL}/api/auth/callback/credentials`,
    payload,
    requestParams(allowed, {
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        accept: "application/json",
      },
    })
  );

  expectStatus(resp, allowed, "POST /api/auth/callback/credentials");
  return resp.status === 200;
}

export default function () {
  // Baseline page load
  const loginAllowed = [200];
  const loginPage = http.get(`${BASE_URL}/login`, requestParams(loginAllowed));
  expectStatus(loginPage, loginAllowed, "GET /login");

  const providersAllowed = [200];
  const providers = http.get(
    `${BASE_URL}/api/auth/providers`,
    requestParams(providersAllowed, {
      headers: { accept: "application/json" },
    })
  );
  expectStatus(providers, providersAllowed, "GET /api/auth/providers");

  const csrfToken = getCsrfToken();
  const loggedIn = tryLogin(csrfToken);

  const sessionAllowed = [200];
  const session = http.get(
    `${BASE_URL}/api/auth/session`,
    requestParams(sessionAllowed, {
      headers: { accept: "application/json" },
    })
  );
  expectStatus(session, sessionAllowed, "GET /api/auth/session");

  // Dashboard can redirect when not logged in
  const dashboardAllowed = loggedIn ? [200] : [200, 302, 307];
  const dashboard = http.get(`${BASE_URL}/dashboard`, requestParams(dashboardAllowed));
  expectStatus(dashboard, dashboardAllowed, "GET /dashboard");

  const adminAllowed = [200, 401, 403];
  const apiResponses = http.batch([
    [
      "GET",
      `${BASE_URL}/api/admin/game-broadcast`,
      null,
      requestParams(adminAllowed, { headers: { accept: "application/json" } }),
    ],
    [
      "GET",
      `${BASE_URL}/api/admin/birthday-gift`,
      null,
      requestParams(adminAllowed, { headers: { accept: "application/json" } }),
    ],
    [
      "GET",
      `${BASE_URL}/api/admin/celebrate-birthdays`,
      null,
      requestParams(adminAllowed, { headers: { accept: "application/json" } }),
    ],
    [
      "GET",
      `${BASE_URL}/api/admin/settings/quick-note`,
      null,
      requestParams(adminAllowed, { headers: { accept: "application/json" } }),
    ],
    [
      "GET",
      `${BASE_URL}/api/admin/notifications/stats`,
      null,
      requestParams(adminAllowed, { headers: { accept: "application/json" } }),
    ],
  ]);

  // Role-protected endpoints: 200/401/403 are all valid outcomes.
  expectStatus(apiResponses[0], adminAllowed, "GET /api/admin/game-broadcast");
  expectStatus(apiResponses[1], adminAllowed, "GET /api/admin/birthday-gift");
  expectStatus(apiResponses[2], adminAllowed, "GET /api/admin/celebrate-birthdays");
  expectStatus(apiResponses[3], adminAllowed, "GET /api/admin/settings/quick-note");
  expectStatus(apiResponses[4], adminAllowed, "GET /api/admin/notifications/stats");

  // Keep a write path in the test to surface write failures.
  const notificationsAllowed = [200, 401, 403];
  const notificationsLocked = http.post(
    `${BASE_URL}/api/notifications/locked`,
    JSON.stringify({
      department: "Overseas",
      teacherName: "k6 test",
      warningType: "First Warning",
      title: "Teacher Account Locked",
      message: "k6 test event",
    }),
    {
      headers: {
        "Content-Type": "application/json",
        accept: "application/json",
      },
      responseCallback: http.expectedStatuses(...notificationsAllowed),
    }
  );
  expectStatus(notificationsLocked, notificationsAllowed, "POST /api/notifications/locked");

  // Sign out if login was attempted.
  if (loggedIn) {
    const signOutAllowed = [200, 302];
    const signOut = http.post(
      `${BASE_URL}/api/auth/signout`,
      { csrfToken, callbackUrl: "/login", json: "true" },
      requestParams(signOutAllowed, {
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          accept: "application/json",
        },
      })
    );
    expectStatus(signOut, signOutAllowed, "POST /api/auth/signout");
  }

  sleep(1);
}
