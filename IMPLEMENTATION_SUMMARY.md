# Implementation Plan Summary (Mar 16–17, 2026)

This file summarizes the implementation plans executed over the last two days.

## 1) Late Popup Uses Per‑Teacher Schedule (Manila)
- Use `TeacherSchedule` for the teacher’s current Manila day, with fallback to system `working_hours`.
- Handle cross‑midnight shifts by extending end time to the next day when `end <= start`.
- Skip rest days based on `Teacher.restDay` vs Manila weekday.
- Show the popup **15 minutes before** shift start and continue until shift end.
- Reopen every **5 minutes** after closing until time‑in.
- Data flow: `getCompleteDashboardData` → `DashboardClient` → `DashboardControls` → `ExperienceManager`.
- Files: `src/app/actions/dashboard.ts`, `src/components/dashboard/DashboardClient.tsx`, `DashboardControls.tsx`, `ExperienceManager.tsx`, `LateArrivalPopup.tsx`.

## 2) Manila Time Display Alignment
- Standardized header time/date display using Manila time in Teacher, Admin, and Branch Admin layouts.
- Files: `src/components/Clock.tsx`, `src/components/ManilaDate.tsx`,
  `src/app/dashboard/layout.tsx`, `src/app/admin/layout.tsx`, `src/app/branch-admin/layout.tsx`.

## 3) Collage Generation (Freshness Check Photos)
- Collage photos limited to Manila window **07:00–23:59** for the current Manila day.
- Branch Admin collage data is filtered by branch.
- Collage popup supports manual trigger and pagination; download uses Manila date in filename.
- Files: `src/app/api/admin/collage-photos/route.ts`, `src/components/admin/AdminCollagePopup.tsx`.

## 4) Birthday Gifts & Monthly Celebration
- Birthday gift API returns only the teacher’s gifts for Teacher role; Admin/Owner see all.
- Gift popup filters out achievement gifts to avoid cross‑contamination.
- Monthly celebration popup triggers based on Manila date signal.
- Files: `src/app/api/admin/birthday-gift/route.ts`, `src/components/dashboard/BirthdayGiftPopup.tsx`,
  `src/components/dashboard/BirthdayCelebrationPopup.tsx`.

## 5) Load Testing (k6)
- Baseline load test script for login + key endpoints with thresholds.
- RBAC login spike test for Admin/Staff/Teacher roles using CSV users.
- Files: `ops/k6/netspeak-load-test.js`, `ops/k6/login-rbac-300.js`, `ops/k6/rbac-users.example.csv`.
