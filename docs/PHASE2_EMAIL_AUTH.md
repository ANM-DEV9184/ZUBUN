# Phase 2 backend — Customer EMAIL-OTP auth (drop Twilio) + capture mobile

**Goal:** customer identity = **email** (free Supabase email OTP); the **mobile
number becomes a reference field** (owner/venue outreach), never used for auth.
The iOS app already sends: email OTP for auth, and `mobile` in the join body.

Apply these changes to `dayem-starter`, then deploy + run the migration.

---

## 1. Supabase Auth config (dashboard + `config.toml`)
- **Enable Email provider**; **disable Phone** provider (was Twilio).
- Email OTP settings already present in `config.toml` (`otp_length = 6`, `enable_confirmations = false`). ✅
- **Add an email-OTP template that renders the code** (default template is a magic *link*). Create `supabase/templates/magic_link.html`:
  ```html
  <h2>Your ZUBUN code</h2>
  <p>Enter this code to sign in:</p>
  <p style="font-size:28px;font-weight:bold;letter-spacing:4px">{{ .Token }}</p>
  <p>It expires in 60 minutes.</p>
  ```
  Wire it in `config.toml`:
  ```toml
  [auth.email.template.magic_link]
  subject = "Your ZUBUN sign-in code"
  content_path = "./supabase/templates/magic_link.html"
  ```
- **Raise the email rate limit** for production: `[auth.rate_limit] email_sent` is `2/hour` — bump appropriately.
- Configure SMTP (you already have SMTP creds for billing/reports — reuse them) so OTP emails send from your domain.

---

## 2. Migration — `supabase/migrations/20260702000080_customer_email_auth.sql`
```sql
-- Email becomes the customer identity; phone becomes a reference field.
alter table customers add column if not exists email  text;
alter table customers add column if not exists mobile text;      -- reference only (owner/venue outreach)
alter table customers alter column phone_e164 drop not null;     -- no longer the identity

create unique index if not exists customers_email_key
  on customers (lower(email)) where email is not null;

-- Email-keyed enrollment. Clone the CURRENT enroll_customer body verbatim, then
-- change ONLY: (a) the identity validation/upsert block below, (b) add p_mobile.
create or replace function enroll_customer_email(
  p_email            text,
  p_venue_id         uuid,
  p_marketing_opt_in boolean,
  p_consent_source   text,
  p_name             text default null,
  p_mobile           text default null,
  p_block_new        boolean default false
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_customer_id uuid;
  -- ...keep the rest of enroll_customer's declares (membership vars, etc.)...
begin
  if p_email is null or p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('result', 'invalid_email');
  end if;

  insert into customers (email, name_optional, mobile)
  values (lower(p_email), p_name, p_mobile)
  on conflict (lower(email)) do update
    set updated_at    = now(),
        name_optional = coalesce(customers.name_optional, excluded.name_optional),
        mobile        = coalesce(excluded.mobile, customers.mobile)
    where customers.erasure_status <> 'erased'
  returning id into v_customer_id;

  if v_customer_id is null then
    return jsonb_build_object('result', 'erased_customer');
  end if;

  -- >>> from here, keep the EXISTING enroll_customer logic verbatim:
  -- venue validation, member-cap (p_block_new -> venue_full), membership upsert
  -- (already_member vs enrolled), consent snapshot, send_welcome_message job, etc.
end;
$$;

revoke execute on function enroll_customer_email(text,uuid,boolean,text,text,text,boolean) from public, anon, authenticated;
grant  execute on function enroll_customer_email(text,uuid,boolean,text,text,text,boolean) to service_role;

-- Email-keyed erasure (mirror request_erasure but resolve by email / customer id).
create or replace function request_erasure_email(p_email text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  select id into v_id from customers where lower(email) = lower(p_email) and erasure_status = 'active';
  if v_id is null then return jsonb_build_object('result','not_found'); end if;
  update customers set erasure_status = 'pending_erasure', erasure_queued_at = now() where id = v_id;
  return jsonb_build_object('result','pending_erasure');
end;
$$;
revoke execute on function request_erasure_email(text) from public, anon, authenticated;
grant  execute on function request_erasure_email(text) to service_role;
```
> The erasure cron already tombstones `phone_e164='erased:<id>'`; also null/ももtombstone `email` there so an erased email can't re-enroll (add `email = 'erased:'||id` in `process_erasures`).

---

## 3. `src/lib/auth/customer-auth.ts` — resolve by email
```ts
export interface CustomerCtx {
  email: string;
  customerId: string | null;
}

export async function resolveCustomer(req: NextRequest): Promise<CustomerCtx | null> {
  const token = bearer(req);
  if (!token) return null;
  const svc = createServiceClient();
  const { data, error } = await svc.auth.getUser(token);
  if (error || !data?.user?.email) return null;
  const email = data.user.email.toLowerCase();

  const { data: c } = await (svc as any)
    .from("customers")
    .select("id, erasure_status")
    .eq("email", email)         // matches the lower(email) unique index
    .maybeSingle();

  if (c?.erasure_status === "erased") return { email, customerId: null };
  return { email, customerId: c?.id ?? null };
}
```
Then in the two routes that used `ctx.phoneE164`:
- **`join/route.ts`**: read `mobile` from the body; call
  `svc.rpc("enroll_customer_email", { p_email: ctx.email, p_venue_id, p_marketing_opt_in, p_consent_source: "ios_app", p_name, p_mobile: mobile ?? null, p_block_new })`.
- **`account/route.ts`**: call `svc.rpc("request_erasure_email", { p_email: ctx.email })`.
The other 5 customer routes only use `ctx.customerId` — no change.

---

## 4. Verify
- Customer signs in with email → 6-digit code arrives → app gets a session.
- Join a venue → `customers` row created/updated by email; `mobile` stored; card appears.
- Owner Member detail shows the mobile (already displays the phone field — point it at `mobile`).

**Net:** no Twilio, free email OTP, email = identity, mobile = reference. iOS is already done and matches this contract.
