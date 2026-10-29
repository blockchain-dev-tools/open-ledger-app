// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Open Ledger App';

  @override
  String get welcomeTitle => 'Open Ledger App';

  @override
  String get welcomeSubtitle => 'Your Ledger Nano X Compatible Hardware Wallet';

  @override
  String get createWallet => 'Create New Wallet';

  @override
  String get importWallet => 'Import Existing';

  @override
  String get enigmaWallet => 'Secret Phrase Setup';

  @override
  String get unlockTitle => 'Enter PIN';

  @override
  String get unlockSubtitle => 'Enter your 6-digit PIN to unlock';

  @override
  String get attemptsRemaining => 'Attempts remaining';

  @override
  String get lockedOut => 'Locked out';

  @override
  String get lockedOutReason =>
      'Five incorrect PIN attempts have permanently locked this wallet.';

  @override
  String get lockedOutConsequence =>
      'Resetting destroys every key on this device. The wallet can only be restored by re-importing your recovery phrase — without a backup, the funds are lost.';

  @override
  String get resetWallet => 'Reset Wallet';

  @override
  String get entropyTitle => 'Collect Entropy';

  @override
  String get entropyInstruction =>
      'Tap anywhere on the screen to collect entropy';

  @override
  String get entropyProgress => 'touches';

  @override
  String get generateMnemonicTitle => 'Your Recovery Phrase';

  @override
  String get generateMnemonicWarning =>
      'Write down these 12 words in order. Never share them with anyone. Anyone with these words can access your funds.';

  @override
  String get iveWrittenItDown => 'I\'ve written it down';

  @override
  String get continueButton => 'Continue';

  @override
  String get verifyMnemonicTitle => 'Verify Your Phrase';

  @override
  String verifyWordPosition(Object position) {
    return 'Select word #$position';
  }

  @override
  String get importMnemonicTitle => 'Import Wallet';

  @override
  String get importMnemonicHint =>
      'Enter your 12- or 24-word recovery phrase, separated by spaces';

  @override
  String get pasteFromClipboard => 'Paste';

  @override
  String get scanQrCode => 'Scan QR';

  @override
  String get qrScanTitle => 'Scan recovery phrase';

  @override
  String get qrScanHint => 'Point the camera at the recovery-phrase QR code';

  @override
  String get qrScanPermissionDenied =>
      'Camera access is denied. Enable it in Settings to scan a QR code.';

  @override
  String get qrScanCameraError =>
      'Camera unavailable. You can still type or paste your recovery phrase.';

  @override
  String get qrScanInvalid =>
      'This QR code does not contain a 12- or 24-word recovery phrase.';

  @override
  String wordsCount(int count, int target) {
    return '$count / $target words';
  }

  @override
  String get validMnemonic => 'Valid recovery phrase';

  @override
  String get invalidMnemonic => 'Invalid recovery phrase';

  @override
  String get import => 'Import';

  @override
  String get setPinTitle => 'Create PIN';

  @override
  String get setPinSubtitle => 'Enter your 6-digit PIN';

  @override
  String get confirmPin => 'Confirm PIN';

  @override
  String get confirmPinSubtitle => 'Confirm your 6-digit PIN';

  @override
  String get pinMismatch => 'PINs do not match. Try again.';

  @override
  String get changePinTitle => 'Change PIN';

  @override
  String get enterOldPin => 'Enter your old PIN';

  @override
  String get enterNewPin => 'Enter your new PIN';

  @override
  String get enterNewPinSubtitle => 'Enter your new 6-digit PIN';

  @override
  String get confirmNewPin => 'Confirm New PIN';

  @override
  String get confirmNewPinSubtitle => 'Confirm your new 6-digit PIN';

  @override
  String get incorrectPin => 'Incorrect PIN';

  @override
  String get pinAlreadyInUse => 'This PIN is already used by another wallet.';

  @override
  String get cancel => 'Cancel';

  @override
  String get back => 'Back';

  @override
  String get accountsTitle => 'Accounts';

  @override
  String get vaultWord => 'Vault';

  @override
  String get switchVault => 'Switch Vault';

  @override
  String get manageVaults => 'Manage Vaults';

  @override
  String get newVault => 'New Vault';

  @override
  String get vaultLimitReached => 'Vault limit reached. Remove a vault first.';

  @override
  String get vaultAlreadyInTier => 'This wallet has already been added.';

  @override
  String get renameVault => 'Rename';

  @override
  String get removeVault => 'Remove';

  @override
  String get removeVaultConfirm =>
      'Remove this vault? Its funds can only be recovered with its recovery phrase.';

  @override
  String get vaultNameHint => 'Vault name';

  @override
  String get vaultPinPrompt => 'Enter your PIN';

  @override
  String get standInTitle => 'Stand-in Wallet';

  @override
  String get standInNotSetUp => 'Not set up';

  @override
  String get standInConfigured => 'Set up';

  @override
  String get standInThreatTitle => 'What this protects';

  @override
  String get standInThreatBody =>
      'If you are forced to unlock the device, enter the stand-in PIN to show this stand-in wallet instead of your real one. It defends against an on-the-spot demand, but it does not hide your real wallet from forensic analysis of the device storage.';

  @override
  String get standInModeSectionTitle =>
      'Behaviour when the stand-in PIN is used';

  @override
  String get standInModeHide => 'Switch only';

  @override
  String get standInModeHideDesc =>
      'Show the stand-in wallet for this session. Your main wallet stays on the device and can still be unlocked with your main PIN.';

  @override
  String get standInModeWipe => 'Switch & erase';

  @override
  String get standInModeWipeDesc =>
      'Erase every main wallet before showing the stand-in. Irreversible — recovery is only possible from each wallet\'s recovery phrase.';

  @override
  String get standInWipeConfirmTitle => 'Use erase mode?';

  @override
  String get standInWipeConfirmBody =>
      'Every main wallet on this device will be permanently erased the next time the stand-in PIN is used. Make sure each recovery phrase is backed up offline. This cannot be undone.';

  @override
  String get standInCreateTitle => 'Create the stand-in wallet';

  @override
  String get standInImportTab => 'Import phrase';

  @override
  String get standInGenerateTab => 'Generate phrase';

  @override
  String get standInEnigmaTab => 'Secret Phrase';

  @override
  String get standInPinTitle => 'Set stand-in PIN';

  @override
  String get standInPinSubtitle =>
      'Choose a 6-digit PIN that differs from your current PIN';

  @override
  String get standInPinConfirmTitle => 'Confirm stand-in PIN';

  @override
  String get standInMainPinTitle => 'Enter your current PIN';

  @override
  String get standInMainPinSubtitle => 'Authorise creating the stand-in wallet';

  @override
  String get standInChangePinTitle => 'Change stand-in PIN';

  @override
  String get standInChangeModeTitle => 'Change behaviour';

  @override
  String get standInRemoveTitle => 'Remove stand-in wallet';

  @override
  String get standInRemoveConfirm =>
      'Remove the stand-in wallet? Its funds can only be recovered with its recovery phrase. Your main wallet is not affected.';

  @override
  String get standInCurrentPinTitle => 'Enter current stand-in PIN';

  @override
  String get standInNewPinTitle => 'Enter new stand-in PIN';

  @override
  String get standInNewPinConfirmTitle => 'Confirm new stand-in PIN';

  @override
  String get standInPinSameAsMain =>
      'The stand-in PIN must differ from your current PIN.';

  @override
  String get standInAlreadyConfigured =>
      'A stand-in wallet is already configured.';

  @override
  String get standInNotConfigured => 'No stand-in wallet configured.';

  @override
  String get standInPrimaryRequired =>
      'This action requires your main wallet session.';

  @override
  String get standInCreated => 'Stand-in wallet set up.';

  @override
  String get standInPinUpdated => 'Stand-in PIN updated.';

  @override
  String get standInModeUpdated => 'Behaviour updated.';

  @override
  String get standInRemoved => 'Stand-in wallet removed.';

  @override
  String get standInUnavailable => 'Not available in this session.';

  @override
  String get standInCurrentModeLabel => 'Behaviour';

  @override
  String get noAccounts => 'No accounts yet';

  @override
  String get settings => 'Settings';

  @override
  String get backupSeed => 'Backup Seed';

  @override
  String get accountDetail => 'Account Details';

  @override
  String accountWithIndex(int index) {
    return 'Account $index';
  }

  @override
  String get receive => 'Receive';

  @override
  String get details => 'Details';

  @override
  String get address => 'Address';

  @override
  String get copyAddress => 'Copy Address';

  @override
  String get addressRequestTitle => 'Address Request';

  @override
  String get addressRequestHint =>
      'A connected app is asking for this address. Approve to share the public address, or reject to decline. Your recovery phrase and private keys are not shared.';

  @override
  String get derivationPath => 'Derivation Path';

  @override
  String get signTransaction => 'Sign Transaction';

  @override
  String get transaction => 'Transaction Signing';

  @override
  String get transactionDetails => 'Transaction Details';

  @override
  String get from => 'From';

  @override
  String get to => 'To';

  @override
  String get value => 'Value';

  @override
  String get networkFee => 'Network Fee';

  @override
  String get chain => 'Chain';

  @override
  String get approve => 'Approve';

  @override
  String get reject => 'Reject';

  @override
  String get transactionApproved => 'Transaction signed';

  @override
  String get transactionRejected => 'Transaction rejected';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get lightMode => 'Light Mode';

  @override
  String get themeSystem => 'System';

  @override
  String get language => 'Language';

  @override
  String get security => 'Security';

  @override
  String get changePin => 'Change PIN';

  @override
  String get resetWalletTitle => 'Reset Wallet';

  @override
  String get resetWalletConfirm =>
      'Are you sure? This deletes every key on this device and cannot be undone. The only way to restore the wallet is to re-import your recovery phrase.';

  @override
  String get reset => 'Reset';

  @override
  String get bleName => 'BLE Name';

  @override
  String get bleNameHint => 'Enter BLE device name';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get backupSeedTitle => 'Backup Seed';

  @override
  String get backupSeedWarning =>
      'Never share your seed phrase! Anyone with these words can access your funds.';

  @override
  String get copyToClipboard => 'Copy to Clipboard';

  @override
  String get copiedToClipboard => 'Copied to clipboard!';

  @override
  String get enigmaTitle => 'Secret Phrase Wallet';

  @override
  String get enigmaDescription =>
      'Generate a deterministic wallet from a memorable phrase and secret key.';

  @override
  String enigmaMatchCount(int count) {
    return 'Matched $count BIP-39 words';
  }

  @override
  String get enigmaNoMatch =>
      'No BIP-39 words matched — this phrase adds no entropy, so the wallet depends on the secret key alone.';

  @override
  String get enterRiddle => 'Enter your secret phrase';

  @override
  String get enterSecretKey => 'Enter your secret key';

  @override
  String get generateWallet => 'Generate Wallet';

  @override
  String get enigmaMnemonicTitle => 'Secret Phrase Mnemonic';

  @override
  String get enigmaMnemonicWarning =>
      'Save these 24 words. You can regenerate them anytime with your secret phrase and secret key.';

  @override
  String get processing => 'Processing';

  @override
  String get done => 'Done';

  @override
  String get error => 'Error';

  @override
  String get success => 'Success';

  @override
  String get addAccount => 'Add Account';

  @override
  String get startBle => 'Start BLE';

  @override
  String get stopBroadcast => 'Stop broadcasting';

  @override
  String get tapActiveChainToStop =>
      'Tap the active chain again to stop broadcasting.';

  @override
  String get tapChainToStartBroadcast => 'Tap a chain to start broadcasting.';

  @override
  String get bleLogs => 'BLE Logs';

  @override
  String get signPending => 'Signing request pending';

  @override
  String bleBroadcastAs(String chain) {
    return 'Broadcast as $chain';
  }

  @override
  String get fingerprint => 'Fingerprint';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get languageJapanese => '日本語';

  @override
  String get languageKorean => '한국어';

  @override
  String get bluetooth => 'Bluetooth';

  @override
  String get deleteAllWalletData => 'Delete all wallet data from this device';

  @override
  String get ledgerCompatible => 'Ledger Nano X Compatible';

  @override
  String get forgotPin => 'Forgot PIN?';

  @override
  String get unexpectedError => 'Unexpected error. Please try again.';

  @override
  String get generateWithTouch =>
      'Generate a new seed phrase with touch entropy';

  @override
  String get restoreFromSeed => 'Restore a wallet from your seed phrase';

  @override
  String get advancedEnigma => 'Advanced entropy generation with Secret Phrase';

  @override
  String get tapRandomly =>
      'Tap randomly across the screen to collect entropy for your recovery phrase.';

  @override
  String get retry => 'Retry';

  @override
  String get correct => 'Correct!';

  @override
  String get incorrectTryAgain => 'Incorrect — try again';

  @override
  String get whichWord => 'Which word did you write down?';

  @override
  String get enterPinToReveal => 'Enter your PIN to reveal the seed phrase';

  @override
  String get yourSeedPhrase => 'Your Seed Phrase';

  @override
  String get writeDown12Words =>
      'Write these 12 words down and store them securely.';

  @override
  String get makeSurePrivate =>
      'Make sure you are in a private place before viewing.';

  @override
  String get walletLockedHint =>
      'The wallet is permanently locked. Go back and reset your wallet to continue.';

  @override
  String get yourRiddle => 'Your Secret Phrase';

  @override
  String get secretKey => 'Secret Key';

  @override
  String get mnemonicLanguage => 'Mnemonic Language';

  @override
  String get enterMemorablePhrase =>
      'Enter a memorable sentence, question, or quote...';

  @override
  String get tipLongUnique =>
      'Tip: Use a long, unique secret phrase and secret key for maximum security.';

  @override
  String get yourEnigmaSeedPhrase => 'Your Seed Phrase';

  @override
  String get continueToSetPin => 'Continue to Set PIN';

  @override
  String get noMnemonicGenerated =>
      'No mnemonic generated. Please go back and try again.';

  @override
  String get writeDown24Words =>
      'Write down these 24 words in order and store them securely. Anyone with these words can access your funds.';

  @override
  String get neverShareSeed => 'Never share your seed phrase!';

  @override
  String get passphraseOptional => 'Passphrase (optional)';

  @override
  String get advancedBip39Passphrase =>
      'Advanced: Add BIP39 passphrase (optional)';

  @override
  String get enterPassphraseOptional => 'Enter passphrase (optional)';

  @override
  String get bip39PassphraseExplanation =>
      'A BIP39 passphrase creates a completely different wallet. If you use one, you MUST remember it — there is no way to recover it.';

  @override
  String get displayLanguage => 'Display Language';

  @override
  String get displayLanguageNote =>
      'The display language only affects how the words look, not how the wallet is generated.';

  @override
  String get leaveEmptyStandard =>
      'Leave empty for standard Secret Phrase wallet.';

  @override
  String get seedDerivedFromEnglish =>
      'This seed is derived from the English mnemonic. It will always be the same regardless of display language.';

  @override
  String get historyTab => 'History';

  @override
  String get noSigningHistory => 'No signing history';

  @override
  String get transactionSignaturesWillAppear =>
      'Transaction signatures will appear here';

  @override
  String get signed => 'Signed';

  @override
  String get rejectedStatus => 'Rejected';

  @override
  String get failedStatus => 'Failed';

  @override
  String get signingAddress => 'Signing Address';

  @override
  String get statusWord => 'Status Word';

  @override
  String get payload => 'Payload';

  @override
  String get justNow => 'Just now';

  @override
  String get noAccountSelected => 'No account selected';

  @override
  String get publicKey => 'Public Key';

  @override
  String get bleAccess => 'BLE Access';

  @override
  String get enabled => 'Enabled';

  @override
  String get disabled => 'Disabled';

  @override
  String get blePeripheral => 'BLE Peripheral';

  @override
  String get connected => 'Connected';

  @override
  String get broadcasting => 'Broadcasting';

  @override
  String get advertisingAs =>
      'Advertising as Ledger Nano X. Ready for connections.';

  @override
  String get startBleBroadcasting =>
      'Start BLE broadcasting to accept signing requests.';

  @override
  String get noBleActivity => 'No BLE activity yet';

  @override
  String get currentApp => 'Current App';

  @override
  String get currentAppHint =>
      'Wallet clients detect the device as this app. Choose Solana before connecting a Solana account.';

  @override
  String get dataHex => 'Data hex';

  @override
  String get dataSize => 'Data size';

  @override
  String get decodedAction => 'Decoded Action';

  @override
  String get chainEthereum => 'Ethereum';

  @override
  String get chainEthereumEvm => 'Ethereum & EVM chains';

  @override
  String get chainSolana => 'Solana';

  @override
  String get chainBitcoin => 'Bitcoin';

  @override
  String get chainTron => 'Tron';

  @override
  String get chainSui => 'Sui';

  @override
  String get chainPersonalMessage => 'Ethereum — Personal Message';

  @override
  String get chainEip712 => 'Ethereum — EIP-712';

  @override
  String get eip712TypedData => 'EIP-712 Typed Data';

  @override
  String get domainHash => 'Domain Hash';

  @override
  String get structHash => 'Struct Hash';

  @override
  String get messageToSign => 'Message to sign';

  @override
  String get gasLimit => 'Gas Limit';

  @override
  String get gasPrice => 'Gas Price';

  @override
  String get maxFee => 'Max Fee';

  @override
  String get priorityFee => 'Priority Fee';

  @override
  String get nonce => 'Nonce';

  @override
  String get chainId => 'Chain ID';

  @override
  String showAll(Object bytes) {
    return 'Show all ($bytes bytes)';
  }

  @override
  String get showMore => 'Show more';

  @override
  String get showLess => 'Show less';

  @override
  String get rawSignature => 'Raw Signature';

  @override
  String get signatureResult => 'Signature Result';

  @override
  String get amount => 'Amount';

  @override
  String get spender => 'Spender';

  @override
  String get methodLabel => 'Method';

  @override
  String get messageLabel => 'Message';

  @override
  String get backupSection => 'Backup';

  @override
  String get exportPrivateKey => 'Export this account\'s private key';

  @override
  String get exportPrivateKeySubtitle =>
      'QR export · shown on this device only';

  @override
  String get exportEntryHint =>
      'Recovery phrase & all private keys: Settings → Backup & Export';

  @override
  String get privateKeyExportTitle => 'Export Private Key';

  @override
  String get privateKeyWarning =>
      'A private key grants full control of this account\'s funds and, unlike the recovery phrase, it cannot be replaced. Never screenshot or photograph it.';

  @override
  String get encoding => 'Encoding';

  @override
  String autoHideHint(int seconds) {
    return 'Auto-hides in ${seconds}s · cleared when you leave';
  }

  @override
  String get iveBackedUp => 'I\'ve backed it up';

  @override
  String get exportSeedTitle => 'Recovery Phrase';

  @override
  String get mnemonicQrWarning =>
      'Do not screenshot, photograph, or show this to anyone.';

  @override
  String get englishBip39Note =>
      'English 12/24-word BIP-39 — importable by any wallet';

  @override
  String get passphraseNotIncluded =>
      'This wallet has a BIP-39 passphrase. It is NOT in the QR — make sure you recorded it separately.';

  @override
  String walletChip(String fingerprint) {
    return 'Wallet · $fingerprint';
  }

  @override
  String get backupAndExport => 'Backup & Export';

  @override
  String get exportSeedQrRow => 'Recovery Phrase QR';

  @override
  String get exportSeedQrRowSubtitle => '12/24 words · restores every account';

  @override
  String get privateKeysRow => 'Private Keys';

  @override
  String get privateKeysRowSubtitle => 'Per account · usually unnecessary';

  @override
  String get privateKeysRareNote =>
      'The recovery phrase already restores every private key. Export these only when the receiving wallet cannot import a recovery phrase.';

  @override
  String get verifySectionHeader => 'Verify';

  @override
  String get verifyRowSubtitle => 'Check you recorded it correctly';

  @override
  String get verifySeedTitle => 'Verify Recovery Phrase';

  @override
  String get verifySeedHint =>
      'Type the words from your written backup, separated by spaces. Nothing you type leaves this device.';

  @override
  String get verifyPassphraseTitle => 'Verify Passphrase';

  @override
  String get verifyPassphraseHint =>
      'Enter the BIP-39 passphrase you set for this wallet. If you never set one, leave it empty — the check then confirms the wallet needs none.';

  @override
  String get verifyEnigmaTitle => 'Verify Secret Phrase';

  @override
  String get verifyEnigmaHint =>
      'Enter the riddle and key you used to create this wallet.';

  @override
  String get enigmaRiddleLabel => 'Riddle';

  @override
  String get enigmaSecretLabel => 'Key';

  @override
  String get verifyAction => 'Verify';

  @override
  String get verifyResultMatch => 'Matches — your backup is correct.';

  @override
  String get verifyResultMismatch =>
      'Doesn\'t match. Check for typos and try again.';

  @override
  String get verifyResultUnavailable =>
      'Can\'t check right now. Unlock the wallet and make sure it has an Ethereum account.';

  @override
  String get privacyShield => 'Content hidden';

  @override
  String get disguiseTitle => 'App Disguise';

  @override
  String get disguiseStandard => 'Standard';

  @override
  String get disguiseCalculator => 'Calculator';

  @override
  String get disguiseConfirmTitle => 'Switch the app disguise?';

  @override
  String disguiseConfirmBody(String name) {
    return 'The launcher icon and name will change to \"$name\". It may take a few seconds to appear on the home screen. Your data and PIN are not affected. To switch back, open this app and return here.';
  }

  @override
  String get disguiseConfirmButton => 'Switch';
}
