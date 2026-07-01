# ZUBUN — In-App Purchase (Owner subscriptions) setup

**Who uses it:** the **Owner** role only — the merchant's subscription to the ZUBUN
platform (Starter / Standard / Multi). Staff & Customers never see IAP.

**State:** the iOS app (StoreKit 2) and the backend endpoint
`POST /api/billing/apple-notifications` are **already built**. What's missing is
**config**: the App Store Connect products + a few env vars. Both are below.

---

## ⚠️ Fix this first — Bundle ID mismatch
The backend's optional bundle sanity check reads `APPLE_BUNDLE_ID`, which the
handover assumed would be **`io.zubun.app`**. But the app's **actual bundle ID is
`Rentolic-Technologies-Est.ZUBUN`**. Pick one and be consistent:
- **Easiest:** set the env `APPLE_BUNDLE_ID=Rentolic-Technologies-Est.ZUBUN` (match the app), **or**
- Change the app's Bundle Identifier to `io.zubun.app` in Xcode (then re-create the App ID + provisioning).
If they don't match, every Apple notification is rejected as `wrong_bundle`.

---

## Part A — Local testing (no App Store Connect needed) — DONE
`ZUBUN/ZUBUN.storekit` defines the 3 subscriptions locally. To use it:
1. Xcode ▸ **Product ▸ Scheme ▸ Edit Scheme…** ▸ **Run ▸ Options** tab.
2. **StoreKit Configuration** dropdown → select **ZUBUN.storekit**.
3. Run the app → **Owner ▸ More ▸ Billing** now lists Starter/Standard/Multi and
   you can "purchase" them in the local test environment (no real charge, no ASC).
> Local testing exercises the UI + StoreKit flow only; it does NOT hit the backend
> reconciliation (that needs a real sandbox + server notifications). Turn the
> StoreKit Configuration back to **None** to test against real sandbox/ASC.

---

## Part B — App Store Connect products (you)
1. appstoreconnect.apple.com ▸ your app ▸ **Subscriptions** ▸ create a
   **Subscription Group** (e.g. "ZUBUN Plans").
2. Add **3 auto-renewable subscriptions**, monthly (1 month), with these **exact
   Product IDs** (must match `AppConfig.swift`):
   | Tier | Product ID | Price |
   |---|---|---|
   | Starter | `io.zubun.sub.starter` | AED 299/mo |
   | Standard | `io.zubun.sub.standard` | AED 599/mo |
   | Multi | `io.zubun.sub.multi` | AED 1,299/mo |
   *(If you use different IDs, change the constants in `AppConfig.swift` to match.)*
3. Fill in a display name, description, and a review screenshot for each (Apple requires these).

---

## Part C — Backend env (you / whoever deploys)
The endpoint exists at `src/app/api/billing/apple-notifications/route.ts` and is a
**no-op until `APPLE_IAP_ENABLED=true`**. Set these on Vercel:

| Env var | Value |
|---|---|
| `APPLE_PRODUCT_STARTER` | `io.zubun.sub.starter` |
| `APPLE_PRODUCT_STANDARD` | `io.zubun.sub.standard` |
| `APPLE_PRODUCT_MULTI` | `io.zubun.sub.multi` |
| `APPLE_BUNDLE_ID` | `Rentolic-Technologies-Est.ZUBUN` (match the app — see warning above) |
| `APPLE_ROOT_CA_FINGERPRINT` | SHA-256 fingerprint of **"Apple Root CA - G3"** |
| `APPLE_IAP_ENABLED` | leave unset/`false` until sandbox passes, then `true` |

Get the root CA fingerprint: download **Apple Root CA - G3** from
apple.com/certificateauthority, then:
```
openssl x509 -in AppleRootCA-G3.cer -inform DER -noout -fingerprint -sha256
```

Also confirm the migration `supabase/migrations/20260618000079_iap_billing_source.sql`
(adds `merchants.billing_source` + `apple_original_transaction_id`) is applied.

---

## Part D — Point Apple's notifications at the endpoint (you)
App Store Connect ▸ your app ▸ **App Information** ▸ **App Store Server Notifications**:
- Set the **Production** and **Sandbox** URLs to `https://zubun.io/api/billing/apple-notifications`
- Version **V2**.

---

## How the loop works (already coded)
1. Owner taps a plan in Billing → StoreKit purchase with **`appAccountToken = merchant_id`** (done in `StoreManager`).
2. Apple sends a **Server Notification V2** to `/api/billing/apple-notifications`.
3. The route verifies the JWS (pinned to Apple root), reads `appAccountToken` as the
   `merchant_id`, maps the product → tier, and updates `merchants.plan_tier` /
   `billing_status` / `billing_source='apple'`.
4. The Owner app re-reads the plan → features unlock.

## Turn-on order
Migration applied → ASC products created → env vars set (except `APPLE_IAP_ENABLED`)
→ notifications URL set → **sandbox test a purchase** → only then `APPLE_IAP_ENABLED=true`.
