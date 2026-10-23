# Security policy

## Reporting a vulnerability

Use the repository's [GitHub Security page](https://github.com/blockchain-dev-tools/open-ledger-app/security) and **Report a vulnerability** when private vulnerability reporting is enabled. Do not post exploit details, credentials, seeds or private wallet data in public issues. If that private option is unavailable, open a minimal issue asking the maintainers to establish a private reporting channel, without disclosing the vulnerability or affected secrets. No alternate email or response-time commitment is implied.

Describe the affected revision, platform and steps using disposable test data. Include the expected security boundary and observed result. The project currently has no declared supported release series; reports against the current source are welcome, and fixes do not imply support for old unreleased snapshots.

## Current trust model

The host wallet and BLE peer are untrusted request sources. Device-side approval should be required before a signature is released. Seeds/private keys must remain on the device except for deliberate PIN-gated local backup displays. The six-digit PIN is local access control, not BLE authentication. See the [product contract](docs/product/contract.md) for required behavior and exceptions.

A general-purpose phone, its operating system, input method and storage are part of the trust boundary. Rooted/compromised devices and exported app storage are not made safe by protocol compatibility. This source has not received an independent security audit, and protocol implementation is not evidence of hardware-wallet-equivalent assurance.

## Known limitations in this snapshot

- Wallet storage is backed by the OS keystore (Android Keystore-wrapped encryption, iOS Keychain), so extracted app data is not decryptable off-device. Mnemonic/passphrase fields and history remain individually encrypted as well; indexes, metadata and counters are not separately obscured. An attacker able to execute code on an unlocked device can still ask the keystore for the data. The five-attempt UI lockout does not apply to that case.
- Background-lock and BLE pause/resume handlers exist but are not connected to the App lifecycle in `main.dart`. Do not rely on the intended five-minute background lock. Foreground inactivity also has no automatic timeout.
- The legacy `/backup-seed` route remains registered and supports copying the seed phrase to the clipboard. The current QR export flow does not remove that route's exposure.
- BLE-name edits in Settings do not persist or change the active advertiser name.
- Android release configuration currently signs with the debug key. An official distribution needs separate release signing and verification.
- iOS integration and broad host-wallet compatibility are experimental or unverified. Air-gap codecs exist but have no product screen journey.
- A persisted five-attempt failure budget locks further PIN entry until reset; reset deletes wallet data. Keep recovery material separately. Older single-wallet storage formats are not migrated by the current repository implementation.

These facts remain visible in public documentation. They are not fixed by this source migration. Validate recovery using disposable data before evaluating any real wallet lifecycle, and never send assets to public test-vector addresses.
