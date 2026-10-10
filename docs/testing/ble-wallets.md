# Host-wallet verification matrix

This source snapshot does not claim a freshly measured host-wallet compatibility matrix. Crypto/protocol code coverage is separate from an end-to-end host-wallet result. Record only reproducible measurements against a named source commit and built APK.

| Chain | Address query | Message/transaction signing | Host/version | Status |
|---|---|---|---|---|
| Ethereum | Implementation present | Implementation present | Record measured host | Unverified for this public snapshot |
| Solana | Implementation present | Implementation present | Record measured host | Unverified for this public snapshot |
| Bitcoin | Implementation present | Verify each signing protocol/PSBT operation | Record measured host | Unverified for this public snapshot |
| Tron | Implementation present | Implementation present | Record measured host | Unverified for this public snapshot |
| Sui | Implementation present | Implementation present | Record measured host | Unverified for this public snapshot |

For each measurement, record: source commit/tag, APK checksum and signing-certificate fingerprint, Android/host OS versions, host-wallet version, chain/network, exact operation, result, status word and sanitized reproduction steps. Keep personal device serials/MACs and private wallet data out of published reports.

Use disposable wallets and public test vectors. Signature checks should independently recover/verify the expected public key or address. Verify approve, reject, timeout, disconnect and locked-state paths. A host discovering the service or accepting an address does not establish signing compatibility.

See the [harness instructions](../../apps/mobile-flutter/tool/e2e/README.md), [manual checklist](e2e-checklist.md), [BLE transport](../reference/ble.md) and [security policy](../../SECURITY.md).
