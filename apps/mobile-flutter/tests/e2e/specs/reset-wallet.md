# Reset Wallet — E2E Test

**Flow**: Welcome → Import Mnemonic → Set PIN → Vault → Settings → Reset → Welcome → (restart) → Welcome

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
8. **VaultScreen** — verify 5 chain sections visible
9. Tap settings gear icon
10. **SettingsScreen** — scroll to "Reset Wallet" tile, tap it
11. Confirm dialog — tap "Reset"
12. **WelcomeScreen** — verify app title "Open Ledger App" visible (wallet cleared)
13. Kill and restart app
14. **WelcomeScreen** — verify still on Welcome (not Unlock)

## Verification criteria

- After reset: Welcome screen shows (not Vault)
- After restart: Welcome screen still shows (wallet data gone)
