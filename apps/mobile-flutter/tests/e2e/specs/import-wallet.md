# Import Wallet — E2E Test

**Flow**: Welcome → Import Mnemonic → Set PIN → Vault → (restart) → Unlock → Vault

**Test data**:
- Mnemonic: `abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about` (12 words, BIP-39 valid)
- PIN: `123456`

## Steps

1. Launch app → **Welcome** screen visible
2. Tap "Import Existing" card
3. **ImportMnemonicScreen** — type/paste 12-word mnemonic
4. Verify validation indicator shows "Valid phrase" (green)
5. Tap "Import" button
6. **SetPinScreen** — enter `1 2 3 4 5 6` (Create PIN phase)
7. Confirm PIN — enter `1 2 3 4 5 6` again
8. **VaultScreen** — verify 5 chain sections visible (Ethereum, Solana, Bitcoin, Tron, Sui)
9. Kill and restart app
10. **UnlockScreen** — enter `1 2 3 4 5 6`
11. **VaultScreen** — verify accounts persist (5 chain sections, fingerprint banner)

## Verification criteria

- After import: Vault shows accounts (not "No accounts yet")
- After restart: Unlock screen appears (not Welcome)
- After unlock: same accounts present
