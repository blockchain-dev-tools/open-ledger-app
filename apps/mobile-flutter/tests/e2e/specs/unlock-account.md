# Unlock + Account Detail — E2E Test

**Flow**: Unlock → Vault → Account Detail → Back → Lock → Re-unlock

**Test data**:
- PIN: `123456`
- Precondition: Wallet already exists (imported or created in prior test)

## Steps

1. Launch app with existing wallet
2. **UnlockScreen** — enter `1 2 3 4 5 6`
3. **VaultScreen** — verify accounts visible
4. Expand Ethereum section — tap chain header
5. Tap first Ethereum account
6. **AccountDetailScreen** — verify address, QR code, derivation path displayed
7. Go back (back gesture / button)
8. **VaultScreen** — verify still on Vault
9. Lock wallet (via settings or timeout)
10. **UnlockScreen** — verify returned to PIN entry
11. Enter wrong PIN 3 times — verify error messages shown
12. Enter correct PIN — verify return to Vault

## Verification criteria

- Account detail shows correct chain info
- Back navigation returns to Vault without data loss
- Wrong PIN shows error counter
- Correct PIN after failures still works
