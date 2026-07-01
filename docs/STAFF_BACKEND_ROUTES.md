# ZUBUN — Backend routes needed for the native Staff app

The iOS **Staff** app authenticates with the custom staff **bearer JWT** against
`/api/staff/*` Next.js routes — it is **not** a Supabase session, so staff cannot
read via PostgREST/RLS. The following staff *reads* have working Postgres RPCs but
**no JSON endpoint**, so they're currently unbuildable on native. Adding these five
thin `GET` routes (mirroring the existing `/api/staff/shift-stats` pattern) unblocks
them immediately.

**Shared conventions**
- Auth: `getStaffSession(req)` (bearer or cookie). Return `401 { error: "unauthorized" }` if absent.
- Derive `staff_id` + `venue_id` from the session — never trust client-supplied ids.
- Call the RPC via the **service client** (same as existing staff routes).
- Respond with the RPC's JSON verbatim (shapes below are already what the web reads).

---

## 1. `GET /api/staff/attendance`  — attendance history
- **Query:** `from` (YYYY-MM-DD, optional, default = today−30d), `to` (optional, default = today). Dubai dates.
- **RPC:** `staff_my_attendance(p_staff_id, p_venue_id, p_from, p_to)`
- **Response:**
```json
{ "ot_pay_policy": "approval",
  "entries": [
    { "kind": "entry", "entry_id": "…", "work_date": "2026-06-30",
      "clock_in_at": "…Z", "clock_out_at": "…Z",
      "worked_minutes": 480, "paid_worked_minutes": 450, "break_minutes": 30,
      "overtime_minutes": 0, "overtime_status": "none",
      "early_leave_minutes": 0, "late_minutes": 5,
      "status": "closed", "source": "clock", "shift_start": "…", "shift_end": "…" }
  ] }
```
- iOS then renders the list and enables **flag-an-issue** (POST `/api/staff/flag-attendance` `{ entry_id, note? }`, which already exists) per entry.

## 2. `GET /api/staff/achievements`
- **RPC:** `staff_my_achievements(p_staff_id, p_venue_id)`
- **Response:** `{ "lifetime": 0, "month": 0, "rank": 0, "best_day": 0, "streak": 0, "next_milestone": 0 }`

## 3. `GET /api/staff/payslips`  — payslip list
- **RPC / reads:** the web `/staff/pay` page reads `staff_payslips` (this staffer, newest first) + `staff_payslip_adjustments`. Expose the same:
- **Response:**
```json
{ "payslips": [
    { "id": "…", "period_month": "2026-06-01", "status": "paid",
      "gross_amount": 4500, "adjustment_total": -50, "currency": "AED",
      "regular_minutes": 9600, "overtime_minutes": 120, "expected_pay_date": "2026-07-01",
      "paid_at": "…", "on_time": true } ],
  "adjustments": [ { "id": "…", "payslip_id": "…", "label": "…", "amount": -50, "note": null } ] }
```
- iOS already has confirm/dispute wired (POST `/api/staff/payslip`), so this list completes the screen.

## 4. `GET /api/staff/colleagues`  — for shift-swap picker
- **Reads:** `staff_users` at the caller's venue, active, excluding self.
- **Response:** `{ "colleagues": [ { "id": "…", "display_name": "Omar" } ] }`
- iOS uses this to populate `to_staff` for the existing POST `/api/staff/swap`.

## 5. (covered by #1) flag-attendance entry picker
- No new route — `POST /api/staff/flag-attendance` already exists. It only needs the
  attendance list from **#1** so the staffer can pick which entry to flag.

---

**Note on offline clock:** the app intentionally does **not** queue clock-in/out for
offline replay — the counter code is a 20-minute HMAC window, so a replayed punch would
fail `bad_code`. Only stamps (idempotent, 60s key) are queued offline.
