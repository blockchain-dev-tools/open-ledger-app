# Device state machines

The [product contract](../product/contract.md) defines required behavior and current gaps. These diagrams summarize the current model; background lifecycle transitions remain unconnected in the App entry point.

## Wallet and credential state

```text
No wallet → setup/import → Unlocked layer session
Stored wallet → PIN gate → credential match → Unlocked layer session
Unlocked session → lock → Locked
PIN mismatch → increment persistent count
Five mismatches → Locked-out → explicit reset → No wallet
```

All layers share the failure counter. Each credential matches a depth; only vaults at that depth appear in the session. A successful match resets the counter. A wipe credential validates its session data before destroying the immediately shallower layer. Explicit Reset Wallet is device-wide, including from a stand-in session.

Current reset entry points call `resetAll()` and remove history. Service-level `clearWallet()` is narrower and must not be substituted incidentally. Settings preferences survive wallet reset.

## Signing request

```text
Idle → Pending (60-second timer)
  ├→ approve → sign once → send 9000 → record outcome → Idle
  ├→ reject → send 6985 → record outcome → Idle
  └→ timeout → send 6400 → record outcome → Idle
```

The resolving guard prevents repeat decisions. Await delivery before clearing pending. Rejection, timeout, BLE error/disconnect and lock clear request accumulators/domain caches. Locked state must not have a seed available for signing.

## BLE and active app

BLE states are `idle → broadcasting → connected`, with transitions back to idle/error on stop/disconnect/failure. The active Ledger app is an independent state: dashboard or one chain app. Selecting a chain opens that app and starts advertising; stopping returns to BOLOS/dashboard. App-specific CLA `E0` commands on dashboard return `6D00`.

Background behavior pauses broadcasting and remembers its intent; returning before timeout resumes, and a five-minute background interval locks. `main.dart` observes the App lifecycle (`paused`/`hidden` → background, `resumed` → foreground; `inactive` is ignored) and forwards it to `AppState`.

Foreground idle locking is a sliding window: any pointer down restarts a five-minute timer, so the session locks only after a full window without interaction. The timer runs only while unlocked and in the foreground, and is suspended while a sign or address confirmation is pending (the 60s request timeout bounds that pause). Either lock path leaves BLE advertising and connections untouched; signing is refused by the absent APDU context. Locking drops a pending confirmation, answers it with `6982` on a best-effort basis, clears in-memory history, and navigates to Unlock with `go()`. PrivacyShield still observes lifecycle only to cover sensitive UI; it does not perform wallet lock.

## Startup and navigation

Do not render normal screens before wallet existence resolves. Existing wallet opens Unlock; no wallet opens Welcome. Authentication and reset use router `go()` so old authentication pages are not retained in the back stack. Secret export flows require fresh PIN verification and automatically hide their QR display after 60 seconds. The legacy seed route is an explicit known exception to the clipboard prohibition.

## Implementations

[WalletBiz](../../apps/mobile-flutter/lib/biz/wallet_biz.dart), [PinBiz](../../apps/mobile-flutter/lib/biz/pin_biz.dart), [SignConfirmation](../../apps/mobile-flutter/lib/biz/sign_confirmation.dart), [BleSession](../../apps/mobile-flutter/lib/biz/ble_session.dart), [AppState](../../apps/mobile-flutter/lib/app/app_state.dart), [PrivacyShield](../../apps/mobile-flutter/lib/ui/widgets/security/privacy_shield.dart).
