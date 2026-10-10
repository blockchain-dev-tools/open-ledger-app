# Manual device validation checklist

This checklist is a test specification, not a record of passed tests. Run on a dedicated test device and use disposable recovery inputs. Some automated fresh-session tests clear App data. Document the measured source revision, APK and host environment in a sanitized report.

## Wallet lifecycle

- [ ] Create/import/Enigma paths reach the intended PIN setup and Vault screens.
- [ ] Generated-word verification checks positions 3, 7 and 11.
- [ ] Cold start with existing wallet shows Unlock before public accounts.
- [ ] Correct PIN opens only its layer; incorrect PIN increments the persisted global counter.
- [ ] Five failures lock input across restart; explicit reset clears all layers and history.
- [ ] Change PIN preserves addresses and saved passphrase recovery for the affected layer.
- [ ] Vault switches isolate APDU signing context and history.
- [ ] Stand-in hide/wipe and explicit device reset use the documented deletion scopes.

## BLE/APDU and signing

- [ ] Live advertising contains the expected service UUID; discovery does not depend on a hardcoded personal MAC.
- [ ] Open-app identity and dashboard response match the selected chain state.
- [ ] Connection/disconnection, error recovery and fragment validation behave correctly.
- [ ] Each supported host/chain operation has a reproducible result in the verification matrix.
- [ ] Device shows locally parsed request data before signing.
- [ ] Approve emits one valid signature, independently verified against its public identity.
- [ ] Reject returns `6985`; 60-second timeout returns `6400`; no signature appears in either path.
- [ ] Locked signing fails and request cache state does not leak between sessions.
- [ ] History records outcome and isolates vaults; storage failure does not block the signing response.

## Backup, presentation and release

- [ ] Current QR export re-verifies session PIN, shows importable chain encoding, warns about BIP-39 passphrase and hides after 60 seconds.
- [ ] Recovery verification matches the expected addresses using disposable inputs.
- [ ] Both themes and supported locales display without clipping; privacy shielding covers sensitive App previews.
- [ ] APK includes the Rust native library and an intended signing certificate.
- [ ] No private mnemonic/PIN/passphrase/key appears in published logs or BLE responses.

## Known gaps that require dedicated fixes

Background lock/pause-resume is not connected to App lifecycle; foreground idle lock is absent. The legacy `/backup-seed` route supports clipboard copy. BLE-name edits do not affect advertising. Storage is SharedPreferences and release signing uses debug credentials. Do not mark these guarantees passed without a dedicated fix and a new test result. See [SECURITY.md](../../SECURITY.md).
