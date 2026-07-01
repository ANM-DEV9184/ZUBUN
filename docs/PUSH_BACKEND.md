# ZUBUN — Push backend: token registration + sending (APNs)

Two pieces the backend team adds so the app's push works end-to-end:
1. **`POST /api/push/register`** — stores a device's APNs token (the iOS app already calls this).
2. **A send helper** — uses your **APNs Auth Key (.p8)** to deliver notifications.

The iOS client (`PushManager` / `PushService`) already sends:
```
POST /api/push/register
Authorization: Bearer <role token>        // staff JWT, or customer/owner Supabase token
{ "token": "<hex apns token>", "platform": "ios", "role": "customer" | "staff" | "owner" }
```
It fires on each role's home screen after sign-in, for every active session.

---

## 1. Migration — `device_tokens`

```sql
create table if not exists device_tokens (
  id          uuid primary key default gen_random_uuid(),
  token       text not null,                 -- APNs hex device token
  platform    text not null default 'ios',
  role        text not null check (role in ('customer','staff','owner')),
  -- one of these is set depending on role:
  customer_id uuid references customers(id) on delete cascade,
  staff_id    uuid references staff_users(id) on delete cascade,
  merchant_id uuid references merchants(id) on delete cascade,
  user_id     uuid,                          -- supabase auth uid for owner/customer
  updated_at  timestamptz not null default now(),
  unique (token, role)
);
create index if not exists device_tokens_customer_idx on device_tokens(customer_id);
create index if not exists device_tokens_staff_idx    on device_tokens(staff_id);
create index if not exists device_tokens_merchant_idx on device_tokens(merchant_id);

alter table device_tokens enable row level security;
-- Service-role only; the route writes with the service client.
```

---

## 2. Route — `src/app/api/push/register/route.ts`

Mirror the existing auth helpers (`getStaffSession`, `resolveCustomer`, cookie/bearer Supabase). Writes with the **service client**.

```ts
import { NextResponse } from "next/server";
import { createServiceClient } from "@/lib/supabase/service";
import { getStaffSession } from "@/lib/auth/staff-auth";
import { resolveCustomer } from "@/lib/auth/customer-auth";

export async function POST(req: Request) {
  const b = await req.json().catch(() => ({}));
  const token = String(b?.token ?? "").trim();
  const role = String(b?.role ?? "");
  const platform = String(b?.platform ?? "ios");
  if (!token || !["customer", "staff", "owner"].includes(role)) {
    return NextResponse.json({ error: "invalid_request" }, { status: 400 });
  }
  const svc = createServiceClient();
  const row: Record<string, unknown> = { token, platform, role, updated_at: new Date().toISOString() };

  if (role === "staff") {
    const s = await getStaffSession(req);
    if (!s) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    row.staff_id = s.staffId;
  } else if (role === "customer") {
    const ctx = await resolveCustomer(req);          // validates the Supabase bearer, resolves customer
    if (!ctx) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    row.customer_id = ctx.customerId;
    row.user_id = ctx.userId;
  } else { // owner
    const auth = req.headers.get("authorization");
    const bearer = auth && /^bearer /i.test(auth) ? auth.slice(7).trim() : null;
    if (!bearer) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    const { data, error } = await svc.auth.getUser(bearer);
    if (error || !data.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    row.user_id = data.user.id;
    row.merchant_id = data.user.app_metadata?.merchant_id ?? null;
  }

  const { error } = await svc.from("device_tokens").upsert(row, { onConflict: "token,role" });
  if (error) return NextResponse.json({ error: "save_failed" }, { status: 400 });
  return NextResponse.json({ ok: true });
}
```

---

## 3. Env (Vercel) — from the APNs key you created

```
APNS_KEY_ID=ABC123XYZ                 # the .p8 Key ID
APNS_TEAM_ID=BV4RVZG72H               # your Team ID
APNS_BUNDLE_ID=Rentolic-Technologies-Est.ZUBUN
APNS_P8=-----BEGIN PRIVATE KEY-----\n...contents of AuthKey_XXX.p8...\n-----END PRIVATE KEY-----
APNS_ENV=sandbox                      # sandbox for dev builds; production for App Store/TestFlight
```

---

## 4. Send helper — `src/lib/push/apns.ts`

Uses HTTP/2 + a signed ES256 JWT (token-based auth, no expiring certs). Needs `jsonwebtoken`.

```ts
import http2 from "node:http2";
import jwt from "jsonwebtoken";

let cachedJwt: { token: string; at: number } | null = null;
function apnsJwt() {
  // APNs tokens are valid ~1h; refresh every ~50 min.
  if (cachedJwt && Date.now() - cachedJwt.at < 50 * 60_000) return cachedJwt.token;
  const token = jwt.sign({}, (process.env.APNS_P8 ?? "").replace(/\\n/g, "\n"), {
    algorithm: "ES256",
    keyid: process.env.APNS_KEY_ID,
    issuer: process.env.APNS_TEAM_ID,
    header: { alg: "ES256", kid: process.env.APNS_KEY_ID! },
  });
  cachedJwt = { token, at: Date.now() };
  return token;
}

export async function sendPush(deviceToken: string, payload: object) {
  const host = process.env.APNS_ENV === "production"
    ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
  const client = http2.connect(host);
  return new Promise<void>((resolve, reject) => {
    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${apnsJwt()}`,
      "apns-topic": process.env.APNS_BUNDLE_ID!,
      "apns-push-type": "alert",
      "content-type": "application/json",
    });
    req.setEncoding("utf8");
    let status = 0;
    req.on("response", (h) => (status = Number(h[":status"])));
    req.on("data", () => {});
    req.on("end", () => { client.close(); status === 200 ? resolve() : reject(new Error(`APNs ${status}`)); });
    req.on("error", (e) => { client.close(); reject(e); });
    req.end(JSON.stringify(payload));
  });
}
```

Usage (e.g. from the outbound worker when a reward is issued):
```ts
const { data: tokens } = await svc.from("device_tokens").select("token").eq("customer_id", customerId);
for (const t of tokens ?? []) {
  await sendPush(t.token, { aps: { alert: { title: "ZUBUN", body: "Your reward is ready 🎁" }, sound: "default" } });
}
```

Handle `410 Unregistered` responses by deleting that `device_tokens` row (the token is stale).

---

**That's the whole loop:** app registers its token → `device_tokens` → your worker/events call `sendPush(...)`. Keep the `.p8` secret; the one key works for all environments and never expires.
