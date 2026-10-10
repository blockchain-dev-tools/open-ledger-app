# Create Wallet — E2E Test

**Flow**: Welcome → Entropy (200 tap points) → Generate Mnemonic → Verify Mnemonic (3 quizzes) → Set PIN → Vault → (restart) → Unlock → Vault

**Test data**:
- Entropy: 200 tap events at random positions
- PIN: `123456`

## Steps

1. Launch app → **Welcome** screen visible
2. Tap "Create New Wallet" card
3. **EntropyScreen** — collect 200 touch points (tap at scattered locations)
4. **GenerateMnemonicScreen** — verify 12-word grid displayed
5. Tap "Continue" / confirm mnemonic saved
6. **VerifyMnemonicScreen** — answer 3 quiz words (positions 3, 7, 11)
7. Tap "Confirm"
8. **SetPinScreen** — enter `1 2 3 4 5 6` (Create PIN)
9. Confirm PIN — enter `1 2 3 4 5 6`
10. **VaultScreen** — verify 5 chain sections visible
11. Kill and restart app
12. **UnlockScreen** — enter `1 2 3 4 5 6`
13. **VaultScreen** — verify accounts persist

## Verification criteria

- After create: Vault shows accounts (not "No accounts yet")
- After restart: Unlock screen appears (not Welcome)
- After unlock: same accounts present
