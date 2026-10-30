import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Ledger App'**
  String get appTitle;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Ledger App'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger Nano X Compatible Hardware Wallet'**
  String get welcomeSubtitle;

  /// No description provided for @createWallet.
  ///
  /// In en, this message translates to:
  /// **'Create New Wallet'**
  String get createWallet;

  /// No description provided for @importWallet.
  ///
  /// In en, this message translates to:
  /// **'Import Existing'**
  String get importWallet;

  /// No description provided for @enigmaWallet.
  ///
  /// In en, this message translates to:
  /// **'Secret Phrase Setup'**
  String get enigmaWallet;

  /// No description provided for @unlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get unlockTitle;

  /// No description provided for @unlockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your 6-digit PIN to unlock'**
  String get unlockSubtitle;

  /// No description provided for @attemptsRemaining.
  ///
  /// In en, this message translates to:
  /// **'Attempts remaining'**
  String get attemptsRemaining;

  /// No description provided for @lockedOut.
  ///
  /// In en, this message translates to:
  /// **'Locked out'**
  String get lockedOut;

  /// No description provided for @lockedOutReason.
  ///
  /// In en, this message translates to:
  /// **'Five incorrect PIN attempts have permanently locked this wallet.'**
  String get lockedOutReason;

  /// No description provided for @lockedOutConsequence.
  ///
  /// In en, this message translates to:
  /// **'Resetting destroys every key on this device. The wallet can only be restored by re-importing your recovery phrase — without a backup, the funds are lost.'**
  String get lockedOutConsequence;

  /// No description provided for @resetWallet.
  ///
  /// In en, this message translates to:
  /// **'Reset Wallet'**
  String get resetWallet;

  /// No description provided for @entropyTitle.
  ///
  /// In en, this message translates to:
  /// **'Collect Entropy'**
  String get entropyTitle;

  /// No description provided for @entropyInstruction.
  ///
  /// In en, this message translates to:
  /// **'Tap anywhere on the screen to collect entropy'**
  String get entropyInstruction;

  /// No description provided for @entropyProgress.
  ///
  /// In en, this message translates to:
  /// **'touches'**
  String get entropyProgress;

  /// No description provided for @generateMnemonicTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Recovery Phrase'**
  String get generateMnemonicTitle;

  /// No description provided for @generateMnemonicWarning.
  ///
  /// In en, this message translates to:
  /// **'Write down these 12 words in order. Never share them with anyone. Anyone with these words can access your funds.'**
  String get generateMnemonicWarning;

  /// No description provided for @iveWrittenItDown.
  ///
  /// In en, this message translates to:
  /// **'I\'ve written it down'**
  String get iveWrittenItDown;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @verifyMnemonicTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify Your Phrase'**
  String get verifyMnemonicTitle;

  /// No description provided for @verifyWordPosition.
  ///
  /// In en, this message translates to:
  /// **'Select word #{position}'**
  String verifyWordPosition(Object position);

  /// No description provided for @importMnemonicTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Wallet'**
  String get importMnemonicTitle;

  /// No description provided for @importMnemonicHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your 12- or 24-word recovery phrase, separated by spaces'**
  String get importMnemonicHint;

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get pasteFromClipboard;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQrCode;

  /// No description provided for @qrScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan recovery phrase'**
  String get qrScanTitle;

  /// No description provided for @qrScanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the recovery-phrase QR code'**
  String get qrScanHint;

  /// No description provided for @qrScanPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera access is denied. Enable it in Settings to scan a QR code.'**
  String get qrScanPermissionDenied;

  /// No description provided for @qrScanCameraError.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable. You can still type or paste your recovery phrase.'**
  String get qrScanCameraError;

  /// No description provided for @qrScanInvalid.
  ///
  /// In en, this message translates to:
  /// **'This QR code does not contain a 12- or 24-word recovery phrase.'**
  String get qrScanInvalid;

  /// No description provided for @wordsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} / {target} words'**
  String wordsCount(int count, int target);

  /// No description provided for @validMnemonic.
  ///
  /// In en, this message translates to:
  /// **'Valid recovery phrase'**
  String get validMnemonic;

  /// No description provided for @invalidMnemonic.
  ///
  /// In en, this message translates to:
  /// **'Invalid recovery phrase'**
  String get invalidMnemonic;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @setPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Create PIN'**
  String get setPinTitle;

  /// No description provided for @setPinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your 6-digit PIN'**
  String get setPinSubtitle;

  /// No description provided for @confirmPin.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get confirmPin;

  /// No description provided for @confirmPinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm your 6-digit PIN'**
  String get confirmPinSubtitle;

  /// No description provided for @pinMismatch.
  ///
  /// In en, this message translates to:
  /// **'PINs do not match. Try again.'**
  String get pinMismatch;

  /// No description provided for @changePinTitle.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get changePinTitle;

  /// No description provided for @enterOldPin.
  ///
  /// In en, this message translates to:
  /// **'Enter your old PIN'**
  String get enterOldPin;

  /// No description provided for @enterNewPin.
  ///
  /// In en, this message translates to:
  /// **'Enter your new PIN'**
  String get enterNewPin;

  /// No description provided for @enterNewPinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your new 6-digit PIN'**
  String get enterNewPinSubtitle;

  /// No description provided for @confirmNewPin.
  ///
  /// In en, this message translates to:
  /// **'Confirm New PIN'**
  String get confirmNewPin;

  /// No description provided for @confirmNewPinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm your new 6-digit PIN'**
  String get confirmNewPinSubtitle;

  /// No description provided for @incorrectPin.
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN'**
  String get incorrectPin;

  /// No description provided for @pinAlreadyInUse.
  ///
  /// In en, this message translates to:
  /// **'This PIN is already used by another wallet.'**
  String get pinAlreadyInUse;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @accountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accountsTitle;

  /// No description provided for @vaultWord.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get vaultWord;

  /// No description provided for @switchVault.
  ///
  /// In en, this message translates to:
  /// **'Switch Vault'**
  String get switchVault;

  /// No description provided for @manageVaults.
  ///
  /// In en, this message translates to:
  /// **'Manage Vaults'**
  String get manageVaults;

  /// No description provided for @newVault.
  ///
  /// In en, this message translates to:
  /// **'New Vault'**
  String get newVault;

  /// No description provided for @newVaultImportTab.
  ///
  /// In en, this message translates to:
  /// **'Import phrase'**
  String get newVaultImportTab;

  /// No description provided for @newVaultSecretTab.
  ///
  /// In en, this message translates to:
  /// **'Secret phrase'**
  String get newVaultSecretTab;

  /// No description provided for @vaultLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Vault limit reached. Remove a vault first.'**
  String get vaultLimitReached;

  /// No description provided for @vaultAlreadyInTier.
  ///
  /// In en, this message translates to:
  /// **'This wallet has already been added.'**
  String get vaultAlreadyInTier;

  /// No description provided for @renameVault.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameVault;

  /// No description provided for @removeVault.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeVault;

  /// No description provided for @removeVaultConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this vault? Its funds can only be recovered with its recovery phrase.'**
  String get removeVaultConfirm;

  /// No description provided for @vaultNameHint.
  ///
  /// In en, this message translates to:
  /// **'Vault name'**
  String get vaultNameHint;

  /// No description provided for @vaultPinPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN'**
  String get vaultPinPrompt;

  /// No description provided for @standInTitle.
  ///
  /// In en, this message translates to:
  /// **'Stand-in Wallet'**
  String get standInTitle;

  /// No description provided for @standInNotSetUp.
  ///
  /// In en, this message translates to:
  /// **'Not set up'**
  String get standInNotSetUp;

  /// No description provided for @standInConfigured.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get standInConfigured;

  /// No description provided for @standInThreatTitle.
  ///
  /// In en, this message translates to:
  /// **'What this protects'**
  String get standInThreatTitle;

  /// No description provided for @standInThreatBody.
  ///
  /// In en, this message translates to:
  /// **'If you are forced to unlock the device, enter the stand-in PIN to show this stand-in wallet instead of your real one. It defends against an on-the-spot demand, but it does not hide your real wallet from forensic analysis of the device storage.'**
  String get standInThreatBody;

  /// No description provided for @standInModeSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Behaviour when the stand-in PIN is used'**
  String get standInModeSectionTitle;

  /// No description provided for @standInModeHide.
  ///
  /// In en, this message translates to:
  /// **'Switch only'**
  String get standInModeHide;

  /// No description provided for @standInModeHideDesc.
  ///
  /// In en, this message translates to:
  /// **'Show the stand-in wallet for this session. Your main wallet stays on the device and can still be unlocked with your main PIN.'**
  String get standInModeHideDesc;

  /// No description provided for @standInModeWipe.
  ///
  /// In en, this message translates to:
  /// **'Switch & erase'**
  String get standInModeWipe;

  /// No description provided for @standInModeWipeDesc.
  ///
  /// In en, this message translates to:
  /// **'Erase every main wallet before showing the stand-in. Irreversible — recovery is only possible from each wallet\'s recovery phrase.'**
  String get standInModeWipeDesc;

  /// No description provided for @standInWipeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Use erase mode?'**
  String get standInWipeConfirmTitle;

  /// No description provided for @standInWipeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Every main wallet on this device will be permanently erased the next time the stand-in PIN is used. Make sure each recovery phrase is backed up offline. This cannot be undone.'**
  String get standInWipeConfirmBody;

  /// No description provided for @standInCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create the stand-in wallet'**
  String get standInCreateTitle;

  /// No description provided for @standInImportTab.
  ///
  /// In en, this message translates to:
  /// **'Import phrase'**
  String get standInImportTab;

  /// No description provided for @standInGenerateTab.
  ///
  /// In en, this message translates to:
  /// **'Generate phrase'**
  String get standInGenerateTab;

  /// No description provided for @standInEnigmaTab.
  ///
  /// In en, this message translates to:
  /// **'Secret Phrase'**
  String get standInEnigmaTab;

  /// No description provided for @standInPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Set stand-in PIN'**
  String get standInPinTitle;

  /// No description provided for @standInPinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a 6-digit PIN that differs from your current PIN'**
  String get standInPinSubtitle;

  /// No description provided for @standInPinConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm stand-in PIN'**
  String get standInPinConfirmTitle;

  /// No description provided for @standInMainPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your current PIN'**
  String get standInMainPinTitle;

  /// No description provided for @standInMainPinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Authorise creating the stand-in wallet'**
  String get standInMainPinSubtitle;

  /// No description provided for @standInChangePinTitle.
  ///
  /// In en, this message translates to:
  /// **'Change stand-in PIN'**
  String get standInChangePinTitle;

  /// No description provided for @standInChangeModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Change behaviour'**
  String get standInChangeModeTitle;

  /// No description provided for @standInRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove stand-in wallet'**
  String get standInRemoveTitle;

  /// No description provided for @standInRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove the stand-in wallet? Its funds can only be recovered with its recovery phrase. Your main wallet is not affected.'**
  String get standInRemoveConfirm;

  /// No description provided for @standInCurrentPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter current stand-in PIN'**
  String get standInCurrentPinTitle;

  /// No description provided for @standInNewPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter new stand-in PIN'**
  String get standInNewPinTitle;

  /// No description provided for @standInNewPinConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm new stand-in PIN'**
  String get standInNewPinConfirmTitle;

  /// No description provided for @standInPinSameAsMain.
  ///
  /// In en, this message translates to:
  /// **'The stand-in PIN must differ from your current PIN.'**
  String get standInPinSameAsMain;

  /// No description provided for @standInAlreadyConfigured.
  ///
  /// In en, this message translates to:
  /// **'A stand-in wallet is already configured.'**
  String get standInAlreadyConfigured;

  /// No description provided for @standInNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'No stand-in wallet configured.'**
  String get standInNotConfigured;

  /// No description provided for @standInPrimaryRequired.
  ///
  /// In en, this message translates to:
  /// **'This action requires your main wallet session.'**
  String get standInPrimaryRequired;

  /// No description provided for @standInCreated.
  ///
  /// In en, this message translates to:
  /// **'Stand-in wallet set up.'**
  String get standInCreated;

  /// No description provided for @standInPinUpdated.
  ///
  /// In en, this message translates to:
  /// **'Stand-in PIN updated.'**
  String get standInPinUpdated;

  /// No description provided for @standInModeUpdated.
  ///
  /// In en, this message translates to:
  /// **'Behaviour updated.'**
  String get standInModeUpdated;

  /// No description provided for @standInRemoved.
  ///
  /// In en, this message translates to:
  /// **'Stand-in wallet removed.'**
  String get standInRemoved;

  /// No description provided for @standInUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available in this session.'**
  String get standInUnavailable;

  /// No description provided for @standInCurrentModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Behaviour'**
  String get standInCurrentModeLabel;

  /// No description provided for @noAccounts.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet'**
  String get noAccounts;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @backupSeed.
  ///
  /// In en, this message translates to:
  /// **'Backup Seed'**
  String get backupSeed;

  /// No description provided for @accountDetail.
  ///
  /// In en, this message translates to:
  /// **'Account Details'**
  String get accountDetail;

  /// No description provided for @accountWithIndex.
  ///
  /// In en, this message translates to:
  /// **'Account {index}'**
  String accountWithIndex(int index);

  /// No description provided for @receive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receive;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @copyAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy Address'**
  String get copyAddress;

  /// No description provided for @addressRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Address Request'**
  String get addressRequestTitle;

  /// No description provided for @addressRequestHint.
  ///
  /// In en, this message translates to:
  /// **'A connected app is asking for this address. Approve to share the public address, or reject to decline. Your recovery phrase and private keys are not shared.'**
  String get addressRequestHint;

  /// No description provided for @derivationPath.
  ///
  /// In en, this message translates to:
  /// **'Derivation Path'**
  String get derivationPath;

  /// No description provided for @signTransaction.
  ///
  /// In en, this message translates to:
  /// **'Sign Transaction'**
  String get signTransaction;

  /// No description provided for @transaction.
  ///
  /// In en, this message translates to:
  /// **'Transaction Signing'**
  String get transaction;

  /// No description provided for @transactionDetails.
  ///
  /// In en, this message translates to:
  /// **'Transaction Details'**
  String get transactionDetails;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get from;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get to;

  /// No description provided for @value.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get value;

  /// No description provided for @networkFee.
  ///
  /// In en, this message translates to:
  /// **'Network Fee'**
  String get networkFee;

  /// No description provided for @chain.
  ///
  /// In en, this message translates to:
  /// **'Chain'**
  String get chain;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @transactionApproved.
  ///
  /// In en, this message translates to:
  /// **'Transaction signed'**
  String get transactionApproved;

  /// No description provided for @transactionRejected.
  ///
  /// In en, this message translates to:
  /// **'Transaction rejected'**
  String get transactionRejected;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @changePin.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get changePin;

  /// No description provided for @resetWalletTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset Wallet'**
  String get resetWalletTitle;

  /// No description provided for @resetWalletConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure? This deletes every key on this device and cannot be undone. The only way to restore the wallet is to re-import your recovery phrase.'**
  String get resetWalletConfirm;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @bleName.
  ///
  /// In en, this message translates to:
  /// **'BLE Name'**
  String get bleName;

  /// No description provided for @bleNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter BLE device name'**
  String get bleNameHint;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @backupSeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup Seed'**
  String get backupSeedTitle;

  /// No description provided for @backupSeedWarning.
  ///
  /// In en, this message translates to:
  /// **'Never share your seed phrase! Anyone with these words can access your funds.'**
  String get backupSeedWarning;

  /// No description provided for @copyToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get copyToClipboard;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard!'**
  String get copiedToClipboard;

  /// No description provided for @enigmaTitle.
  ///
  /// In en, this message translates to:
  /// **'Secret Phrase Wallet'**
  String get enigmaTitle;

  /// No description provided for @enigmaDescription.
  ///
  /// In en, this message translates to:
  /// **'Generate a deterministic wallet from a memorable phrase and secret key.'**
  String get enigmaDescription;

  /// No description provided for @enigmaMatchCount.
  ///
  /// In en, this message translates to:
  /// **'Matched {count} BIP-39 words'**
  String enigmaMatchCount(int count);

  /// No description provided for @enigmaNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No BIP-39 words matched — this phrase adds no entropy, so the wallet depends on the secret key alone.'**
  String get enigmaNoMatch;

  /// No description provided for @enterRiddle.
  ///
  /// In en, this message translates to:
  /// **'Enter your secret phrase'**
  String get enterRiddle;

  /// No description provided for @enterSecretKey.
  ///
  /// In en, this message translates to:
  /// **'Enter your secret key'**
  String get enterSecretKey;

  /// No description provided for @generateWallet.
  ///
  /// In en, this message translates to:
  /// **'Generate Wallet'**
  String get generateWallet;

  /// No description provided for @enigmaMnemonicTitle.
  ///
  /// In en, this message translates to:
  /// **'Secret Phrase Mnemonic'**
  String get enigmaMnemonicTitle;

  /// No description provided for @enigmaMnemonicWarning.
  ///
  /// In en, this message translates to:
  /// **'Save these 24 words. You can regenerate them anytime with your secret phrase and secret key.'**
  String get enigmaMnemonicWarning;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get processing;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add Account'**
  String get addAccount;

  /// No description provided for @startBle.
  ///
  /// In en, this message translates to:
  /// **'Start BLE'**
  String get startBle;

  /// No description provided for @stopBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Stop broadcasting'**
  String get stopBroadcast;

  /// No description provided for @tapActiveChainToStop.
  ///
  /// In en, this message translates to:
  /// **'Tap the active chain again to stop broadcasting.'**
  String get tapActiveChainToStop;

  /// No description provided for @tapChainToStartBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Tap a chain to start broadcasting.'**
  String get tapChainToStartBroadcast;

  /// No description provided for @bleLogs.
  ///
  /// In en, this message translates to:
  /// **'BLE Logs'**
  String get bleLogs;

  /// No description provided for @signPending.
  ///
  /// In en, this message translates to:
  /// **'Signing request pending'**
  String get signPending;

  /// No description provided for @bleBroadcastAs.
  ///
  /// In en, this message translates to:
  /// **'Broadcast as {chain}'**
  String bleBroadcastAs(String chain);

  /// No description provided for @fingerprint.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint'**
  String get fingerprint;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get languageChinese;

  /// No description provided for @languageJapanese.
  ///
  /// In en, this message translates to:
  /// **'日本語'**
  String get languageJapanese;

  /// No description provided for @languageKorean.
  ///
  /// In en, this message translates to:
  /// **'한국어'**
  String get languageKorean;

  /// No description provided for @bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get bluetooth;

  /// No description provided for @deleteAllWalletData.
  ///
  /// In en, this message translates to:
  /// **'Delete all wallet data from this device'**
  String get deleteAllWalletData;

  /// No description provided for @ledgerCompatible.
  ///
  /// In en, this message translates to:
  /// **'Ledger Nano X Compatible'**
  String get ledgerCompatible;

  /// No description provided for @forgotPin.
  ///
  /// In en, this message translates to:
  /// **'Forgot PIN?'**
  String get forgotPin;

  /// No description provided for @unexpectedError.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error. Please try again.'**
  String get unexpectedError;

  /// No description provided for @generateWithTouch.
  ///
  /// In en, this message translates to:
  /// **'Generate a new seed phrase with touch entropy'**
  String get generateWithTouch;

  /// No description provided for @restoreFromSeed.
  ///
  /// In en, this message translates to:
  /// **'Restore a wallet from your seed phrase'**
  String get restoreFromSeed;

  /// No description provided for @advancedEnigma.
  ///
  /// In en, this message translates to:
  /// **'Advanced entropy generation with Secret Phrase'**
  String get advancedEnigma;

  /// No description provided for @tapRandomly.
  ///
  /// In en, this message translates to:
  /// **'Tap randomly across the screen to collect entropy for your recovery phrase.'**
  String get tapRandomly;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @correct.
  ///
  /// In en, this message translates to:
  /// **'Correct!'**
  String get correct;

  /// No description provided for @incorrectTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Incorrect — try again'**
  String get incorrectTryAgain;

  /// No description provided for @whichWord.
  ///
  /// In en, this message translates to:
  /// **'Which word did you write down?'**
  String get whichWord;

  /// No description provided for @enterPinToReveal.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN to reveal the seed phrase'**
  String get enterPinToReveal;

  /// No description provided for @yourSeedPhrase.
  ///
  /// In en, this message translates to:
  /// **'Your Seed Phrase'**
  String get yourSeedPhrase;

  /// No description provided for @writeDown12Words.
  ///
  /// In en, this message translates to:
  /// **'Write these 12 words down and store them securely.'**
  String get writeDown12Words;

  /// No description provided for @makeSurePrivate.
  ///
  /// In en, this message translates to:
  /// **'Make sure you are in a private place before viewing.'**
  String get makeSurePrivate;

  /// No description provided for @walletLockedHint.
  ///
  /// In en, this message translates to:
  /// **'The wallet is permanently locked. Go back and reset your wallet to continue.'**
  String get walletLockedHint;

  /// No description provided for @yourRiddle.
  ///
  /// In en, this message translates to:
  /// **'Your Secret Phrase'**
  String get yourRiddle;

  /// No description provided for @secretKey.
  ///
  /// In en, this message translates to:
  /// **'Secret Key'**
  String get secretKey;

  /// No description provided for @mnemonicLanguage.
  ///
  /// In en, this message translates to:
  /// **'Mnemonic Language'**
  String get mnemonicLanguage;

  /// No description provided for @enterMemorablePhrase.
  ///
  /// In en, this message translates to:
  /// **'Enter a memorable sentence, question, or quote...'**
  String get enterMemorablePhrase;

  /// No description provided for @tipLongUnique.
  ///
  /// In en, this message translates to:
  /// **'Tip: Use a long, unique secret phrase and secret key for maximum security.'**
  String get tipLongUnique;

  /// No description provided for @yourEnigmaSeedPhrase.
  ///
  /// In en, this message translates to:
  /// **'Your Seed Phrase'**
  String get yourEnigmaSeedPhrase;

  /// No description provided for @continueToSetPin.
  ///
  /// In en, this message translates to:
  /// **'Continue to Set PIN'**
  String get continueToSetPin;

  /// No description provided for @noMnemonicGenerated.
  ///
  /// In en, this message translates to:
  /// **'No mnemonic generated. Please go back and try again.'**
  String get noMnemonicGenerated;

  /// No description provided for @writeDown24Words.
  ///
  /// In en, this message translates to:
  /// **'Write down these 24 words in order and store them securely. Anyone with these words can access your funds.'**
  String get writeDown24Words;

  /// No description provided for @neverShareSeed.
  ///
  /// In en, this message translates to:
  /// **'Never share your seed phrase!'**
  String get neverShareSeed;

  /// No description provided for @passphraseOptional.
  ///
  /// In en, this message translates to:
  /// **'Passphrase (optional)'**
  String get passphraseOptional;

  /// No description provided for @advancedBip39Passphrase.
  ///
  /// In en, this message translates to:
  /// **'Advanced: Add BIP39 passphrase (optional)'**
  String get advancedBip39Passphrase;

  /// No description provided for @enterPassphraseOptional.
  ///
  /// In en, this message translates to:
  /// **'Enter passphrase (optional)'**
  String get enterPassphraseOptional;

  /// No description provided for @bip39PassphraseExplanation.
  ///
  /// In en, this message translates to:
  /// **'A BIP39 passphrase creates a completely different wallet. If you use one, you MUST remember it — there is no way to recover it.'**
  String get bip39PassphraseExplanation;

  /// No description provided for @displayLanguage.
  ///
  /// In en, this message translates to:
  /// **'Display Language'**
  String get displayLanguage;

  /// No description provided for @displayLanguageNote.
  ///
  /// In en, this message translates to:
  /// **'The display language only affects how the words look, not how the wallet is generated.'**
  String get displayLanguageNote;

  /// No description provided for @leaveEmptyStandard.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for standard Secret Phrase wallet.'**
  String get leaveEmptyStandard;

  /// No description provided for @seedDerivedFromEnglish.
  ///
  /// In en, this message translates to:
  /// **'This seed is derived from the English mnemonic. It will always be the same regardless of display language.'**
  String get seedDerivedFromEnglish;

  /// No description provided for @historyTab.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTab;

  /// No description provided for @noSigningHistory.
  ///
  /// In en, this message translates to:
  /// **'No signing history'**
  String get noSigningHistory;

  /// No description provided for @transactionSignaturesWillAppear.
  ///
  /// In en, this message translates to:
  /// **'Transaction signatures will appear here'**
  String get transactionSignaturesWillAppear;

  /// No description provided for @signed.
  ///
  /// In en, this message translates to:
  /// **'Signed'**
  String get signed;

  /// No description provided for @rejectedStatus.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejectedStatus;

  /// No description provided for @failedStatus.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failedStatus;

  /// No description provided for @signingAddress.
  ///
  /// In en, this message translates to:
  /// **'Signing Address'**
  String get signingAddress;

  /// No description provided for @statusWord.
  ///
  /// In en, this message translates to:
  /// **'Status Word'**
  String get statusWord;

  /// No description provided for @payload.
  ///
  /// In en, this message translates to:
  /// **'Payload'**
  String get payload;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @noAccountSelected.
  ///
  /// In en, this message translates to:
  /// **'No account selected'**
  String get noAccountSelected;

  /// No description provided for @publicKey.
  ///
  /// In en, this message translates to:
  /// **'Public Key'**
  String get publicKey;

  /// No description provided for @bleAccess.
  ///
  /// In en, this message translates to:
  /// **'BLE Access'**
  String get bleAccess;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @blePeripheral.
  ///
  /// In en, this message translates to:
  /// **'BLE Peripheral'**
  String get blePeripheral;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @broadcasting.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting'**
  String get broadcasting;

  /// No description provided for @advertisingAs.
  ///
  /// In en, this message translates to:
  /// **'Advertising as Ledger Nano X. Ready for connections.'**
  String get advertisingAs;

  /// No description provided for @startBleBroadcasting.
  ///
  /// In en, this message translates to:
  /// **'Start BLE broadcasting to accept signing requests.'**
  String get startBleBroadcasting;

  /// No description provided for @noBleActivity.
  ///
  /// In en, this message translates to:
  /// **'No BLE activity yet'**
  String get noBleActivity;

  /// No description provided for @currentApp.
  ///
  /// In en, this message translates to:
  /// **'Current App'**
  String get currentApp;

  /// No description provided for @currentAppHint.
  ///
  /// In en, this message translates to:
  /// **'Wallet clients detect the device as this app. Choose Solana before connecting a Solana account.'**
  String get currentAppHint;

  /// No description provided for @dataHex.
  ///
  /// In en, this message translates to:
  /// **'Data hex'**
  String get dataHex;

  /// No description provided for @dataSize.
  ///
  /// In en, this message translates to:
  /// **'Data size'**
  String get dataSize;

  /// No description provided for @decodedAction.
  ///
  /// In en, this message translates to:
  /// **'Decoded Action'**
  String get decodedAction;

  /// No description provided for @chainEthereum.
  ///
  /// In en, this message translates to:
  /// **'Ethereum'**
  String get chainEthereum;

  /// No description provided for @chainEthereumEvm.
  ///
  /// In en, this message translates to:
  /// **'Ethereum & EVM chains'**
  String get chainEthereumEvm;

  /// No description provided for @chainSolana.
  ///
  /// In en, this message translates to:
  /// **'Solana'**
  String get chainSolana;

  /// No description provided for @chainBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin'**
  String get chainBitcoin;

  /// No description provided for @chainTron.
  ///
  /// In en, this message translates to:
  /// **'Tron'**
  String get chainTron;

  /// No description provided for @chainSui.
  ///
  /// In en, this message translates to:
  /// **'Sui'**
  String get chainSui;

  /// No description provided for @chainNear.
  ///
  /// In en, this message translates to:
  /// **'NEAR'**
  String get chainNear;

  /// No description provided for @chainTon.
  ///
  /// In en, this message translates to:
  /// **'TON'**
  String get chainTon;

  /// No description provided for @manageChains.
  ///
  /// In en, this message translates to:
  /// **'Manage chains'**
  String get manageChains;

  /// No description provided for @manageChainsSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage chains'**
  String get manageChainsSheetTitle;

  /// No description provided for @manageChainsSheetHint.
  ///
  /// In en, this message translates to:
  /// **'Turn a chain off to hide it here and from the Bluetooth app list. Its accounts stay.'**
  String get manageChainsSheetHint;

  /// No description provided for @chainPersonalMessage.
  ///
  /// In en, this message translates to:
  /// **'Ethereum — Personal Message'**
  String get chainPersonalMessage;

  /// No description provided for @chainEip712.
  ///
  /// In en, this message translates to:
  /// **'Ethereum — EIP-712'**
  String get chainEip712;

  /// No description provided for @eip712TypedData.
  ///
  /// In en, this message translates to:
  /// **'EIP-712 Typed Data'**
  String get eip712TypedData;

  /// No description provided for @domainHash.
  ///
  /// In en, this message translates to:
  /// **'Domain Hash'**
  String get domainHash;

  /// No description provided for @structHash.
  ///
  /// In en, this message translates to:
  /// **'Struct Hash'**
  String get structHash;

  /// No description provided for @messageToSign.
  ///
  /// In en, this message translates to:
  /// **'Message to sign'**
  String get messageToSign;

  /// No description provided for @gasLimit.
  ///
  /// In en, this message translates to:
  /// **'Gas Limit'**
  String get gasLimit;

  /// No description provided for @gasPrice.
  ///
  /// In en, this message translates to:
  /// **'Gas Price'**
  String get gasPrice;

  /// No description provided for @maxFee.
  ///
  /// In en, this message translates to:
  /// **'Max Fee'**
  String get maxFee;

  /// No description provided for @priorityFee.
  ///
  /// In en, this message translates to:
  /// **'Priority Fee'**
  String get priorityFee;

  /// No description provided for @nonce.
  ///
  /// In en, this message translates to:
  /// **'Nonce'**
  String get nonce;

  /// No description provided for @chainId.
  ///
  /// In en, this message translates to:
  /// **'Chain ID'**
  String get chainId;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'Show all ({bytes} bytes)'**
  String showAll(Object bytes);

  /// No description provided for @showMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get showMore;

  /// No description provided for @showLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get showLess;

  /// No description provided for @rawSignature.
  ///
  /// In en, this message translates to:
  /// **'Raw Signature'**
  String get rawSignature;

  /// No description provided for @signatureResult.
  ///
  /// In en, this message translates to:
  /// **'Signature Result'**
  String get signatureResult;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @spender.
  ///
  /// In en, this message translates to:
  /// **'Spender'**
  String get spender;

  /// No description provided for @methodLabel.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get methodLabel;

  /// No description provided for @messageLabel.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageLabel;

  /// No description provided for @backupSection.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backupSection;

  /// No description provided for @exportPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Export this account\'s private key'**
  String get exportPrivateKey;

  /// No description provided for @exportPrivateKeySubtitle.
  ///
  /// In en, this message translates to:
  /// **'QR export · shown on this device only'**
  String get exportPrivateKeySubtitle;

  /// No description provided for @exportEntryHint.
  ///
  /// In en, this message translates to:
  /// **'Recovery phrase & all private keys: Settings → Backup & Export'**
  String get exportEntryHint;

  /// No description provided for @privateKeyExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Private Key'**
  String get privateKeyExportTitle;

  /// No description provided for @privateKeyWarning.
  ///
  /// In en, this message translates to:
  /// **'A private key grants full control of this account\'s funds and, unlike the recovery phrase, it cannot be replaced. Never screenshot or photograph it.'**
  String get privateKeyWarning;

  /// No description provided for @encoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding'**
  String get encoding;

  /// No description provided for @autoHideHint.
  ///
  /// In en, this message translates to:
  /// **'Auto-hides in {seconds}s · cleared when you leave'**
  String autoHideHint(int seconds);

  /// No description provided for @iveBackedUp.
  ///
  /// In en, this message translates to:
  /// **'I\'ve backed it up'**
  String get iveBackedUp;

  /// No description provided for @exportSeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Recovery Phrase'**
  String get exportSeedTitle;

  /// No description provided for @mnemonicQrWarning.
  ///
  /// In en, this message translates to:
  /// **'Do not screenshot, photograph, or show this to anyone.'**
  String get mnemonicQrWarning;

  /// No description provided for @englishBip39Note.
  ///
  /// In en, this message translates to:
  /// **'English 12/24-word BIP-39 — importable by any wallet'**
  String get englishBip39Note;

  /// No description provided for @passphraseNotIncluded.
  ///
  /// In en, this message translates to:
  /// **'This wallet has a BIP-39 passphrase. It is NOT in the QR — make sure you recorded it separately.'**
  String get passphraseNotIncluded;

  /// No description provided for @walletChip.
  ///
  /// In en, this message translates to:
  /// **'Wallet · {fingerprint}'**
  String walletChip(String fingerprint);

  /// No description provided for @backupAndExport.
  ///
  /// In en, this message translates to:
  /// **'Backup & Export'**
  String get backupAndExport;

  /// No description provided for @exportSeedQrRow.
  ///
  /// In en, this message translates to:
  /// **'Recovery Phrase QR'**
  String get exportSeedQrRow;

  /// No description provided for @exportSeedQrRowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'12/24 words · restores every account'**
  String get exportSeedQrRowSubtitle;

  /// No description provided for @privateKeysRow.
  ///
  /// In en, this message translates to:
  /// **'Private Keys'**
  String get privateKeysRow;

  /// No description provided for @privateKeysRowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Per account · usually unnecessary'**
  String get privateKeysRowSubtitle;

  /// No description provided for @privateKeysRareNote.
  ///
  /// In en, this message translates to:
  /// **'The recovery phrase already restores every private key. Export these only when the receiving wallet cannot import a recovery phrase.'**
  String get privateKeysRareNote;

  /// No description provided for @verifySectionHeader.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verifySectionHeader;

  /// No description provided for @verifyRowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check you recorded it correctly'**
  String get verifyRowSubtitle;

  /// No description provided for @verifySeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify Recovery Phrase'**
  String get verifySeedTitle;

  /// No description provided for @verifySeedHint.
  ///
  /// In en, this message translates to:
  /// **'Type the words from your written backup, separated by spaces. Nothing you type leaves this device.'**
  String get verifySeedHint;

  /// No description provided for @verifyPassphraseTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify Passphrase'**
  String get verifyPassphraseTitle;

  /// No description provided for @verifyPassphraseHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the BIP-39 passphrase you set for this wallet. If you never set one, leave it empty — the check then confirms the wallet needs none.'**
  String get verifyPassphraseHint;

  /// No description provided for @verifyEnigmaTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify Secret Phrase'**
  String get verifyEnigmaTitle;

  /// No description provided for @verifyEnigmaHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the riddle and key you used to create this wallet.'**
  String get verifyEnigmaHint;

  /// No description provided for @enigmaRiddleLabel.
  ///
  /// In en, this message translates to:
  /// **'Riddle'**
  String get enigmaRiddleLabel;

  /// No description provided for @enigmaSecretLabel.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get enigmaSecretLabel;

  /// No description provided for @verifyAction.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verifyAction;

  /// No description provided for @verifyResultMatch.
  ///
  /// In en, this message translates to:
  /// **'Matches — your backup is correct.'**
  String get verifyResultMatch;

  /// No description provided for @verifyResultMismatch.
  ///
  /// In en, this message translates to:
  /// **'Doesn\'t match. Check for typos and try again.'**
  String get verifyResultMismatch;

  /// No description provided for @verifyResultUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Can\'t check right now. Unlock the wallet and make sure it has an Ethereum account.'**
  String get verifyResultUnavailable;

  /// No description provided for @privacyShield.
  ///
  /// In en, this message translates to:
  /// **'Content hidden'**
  String get privacyShield;

  /// No description provided for @disguiseTitle.
  ///
  /// In en, this message translates to:
  /// **'App Disguise'**
  String get disguiseTitle;

  /// No description provided for @disguiseStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get disguiseStandard;

  /// No description provided for @disguiseCalculator.
  ///
  /// In en, this message translates to:
  /// **'Calculator'**
  String get disguiseCalculator;

  /// No description provided for @disguiseConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch the app disguise?'**
  String get disguiseConfirmTitle;

  /// No description provided for @disguiseConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The launcher icon and name will change to \"{name}\". It may take a few seconds to appear on the home screen. Your data and PIN are not affected. To switch back, open this app and return here.'**
  String disguiseConfirmBody(String name);

  /// No description provided for @disguiseConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get disguiseConfirmButton;

  /// No description provided for @keystoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Keystone QR'**
  String get keystoneTitle;

  /// No description provided for @keystoneEntryExport.
  ///
  /// In en, this message translates to:
  /// **'Connect as a host'**
  String get keystoneEntryExport;

  /// No description provided for @keystoneEntryScan.
  ///
  /// In en, this message translates to:
  /// **'Scan to sign'**
  String get keystoneEntryScan;

  /// No description provided for @keystoneExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export account'**
  String get keystoneExportTitle;

  /// No description provided for @keystoneExportHint.
  ///
  /// In en, this message translates to:
  /// **'Scan this code in the host wallet to import the accounts it carries'**
  String get keystoneExportHint;

  /// No description provided for @keystoneExportFormatMetaMask.
  ///
  /// In en, this message translates to:
  /// **'MetaMask (5 addresses)'**
  String get keystoneExportFormatMetaMask;

  /// No description provided for @keystoneExportFormatKeystone.
  ///
  /// In en, this message translates to:
  /// **'OKX / Keystone (sync code)'**
  String get keystoneExportFormatKeystone;

  /// No description provided for @keystoneExportAccountRange.
  ///
  /// In en, this message translates to:
  /// **'Accounts {start}–{end}'**
  String keystoneExportAccountRange(int start, int end);

  /// No description provided for @keystoneExportPageAddresses.
  ///
  /// In en, this message translates to:
  /// **'Addresses in this code'**
  String get keystoneExportPageAddresses;

  /// No description provided for @keystoneExportPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get keystoneExportPath;

  /// No description provided for @keystoneExportPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get keystoneExportPrev;

  /// No description provided for @keystoneExportNext.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get keystoneExportNext;

  /// No description provided for @keystoneScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan the signing request'**
  String get keystoneScanTitle;

  /// No description provided for @keystoneScanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code shown by MetaMask'**
  String get keystoneScanHint;

  /// No description provided for @keystoneScanProgress.
  ///
  /// In en, this message translates to:
  /// **'Collecting frames {received}/{total}'**
  String keystoneScanProgress(int received, int total);

  /// No description provided for @keystoneReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review request'**
  String get keystoneReviewTitle;

  /// No description provided for @keystoneReviewDataType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get keystoneReviewDataType;

  /// No description provided for @keystoneReviewChain.
  ///
  /// In en, this message translates to:
  /// **'Chain ID'**
  String get keystoneReviewChain;

  /// No description provided for @keystoneReviewOrigin.
  ///
  /// In en, this message translates to:
  /// **'Origin'**
  String get keystoneReviewOrigin;

  /// No description provided for @keystoneReviewPath.
  ///
  /// In en, this message translates to:
  /// **'Derivation path'**
  String get keystoneReviewPath;

  /// No description provided for @keystoneReviewAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get keystoneReviewAddress;

  /// No description provided for @keystoneReviewDataHash.
  ///
  /// In en, this message translates to:
  /// **'Signing hash'**
  String get keystoneReviewDataHash;

  /// No description provided for @keystoneReviewDataSize.
  ///
  /// In en, this message translates to:
  /// **'Payload'**
  String get keystoneReviewDataSize;

  /// No description provided for @keystoneReviewTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get keystoneReviewTo;

  /// No description provided for @keystoneReviewAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get keystoneReviewAmount;

  /// No description provided for @keystoneReviewMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get keystoneReviewMessage;

  /// No description provided for @keystoneReviewCalldata.
  ///
  /// In en, this message translates to:
  /// **'Calldata'**
  String get keystoneReviewCalldata;

  /// No description provided for @keystoneReviewUnknownMethod.
  ///
  /// In en, this message translates to:
  /// **'unknown method'**
  String get keystoneReviewUnknownMethod;

  /// No description provided for @keystoneReviewWarning.
  ///
  /// In en, this message translates to:
  /// **'Only approve when the origin and the address match what MetaMask is asking for.'**
  String get keystoneReviewWarning;

  /// No description provided for @keystoneDataTypeTransaction.
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get keystoneDataTypeTransaction;

  /// No description provided for @keystoneDataTypePersonalMessage.
  ///
  /// In en, this message translates to:
  /// **'Personal message'**
  String get keystoneDataTypePersonalMessage;

  /// No description provided for @keystoneDataTypeTypedTransaction.
  ///
  /// In en, this message translates to:
  /// **'Typed transaction'**
  String get keystoneDataTypeTypedTransaction;

  /// No description provided for @keystoneDataTypeUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Unsupported ({type})'**
  String keystoneDataTypeUnsupported(int type);

  /// No description provided for @keystoneApprove.
  ///
  /// In en, this message translates to:
  /// **'Sign'**
  String get keystoneApprove;

  /// No description provided for @keystoneReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get keystoneReject;

  /// No description provided for @keystoneSignatureTitle.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get keystoneSignatureTitle;

  /// No description provided for @keystoneSignatureHint.
  ///
  /// In en, this message translates to:
  /// **'Scan this code back into MetaMask'**
  String get keystoneSignatureHint;

  /// No description provided for @keystoneDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get keystoneDone;

  /// No description provided for @keystoneRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get keystoneRetry;

  /// No description provided for @keystoneErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timed out waiting for the request frames.'**
  String get keystoneErrorTimeout;

  /// No description provided for @keystoneErrorUnexpectedQr.
  ///
  /// In en, this message translates to:
  /// **'That QR code is not a Keystone signing request.'**
  String get keystoneErrorUnexpectedQr;

  /// No description provided for @keystoneErrorInvalidRequest.
  ///
  /// In en, this message translates to:
  /// **'This signing request could not be parsed.'**
  String get keystoneErrorInvalidRequest;

  /// No description provided for @keystoneErrorCodecUnavailable.
  ///
  /// In en, this message translates to:
  /// **'QR support is unavailable in this build.'**
  String get keystoneErrorCodecUnavailable;

  /// No description provided for @keystoneErrorSigning.
  ///
  /// In en, this message translates to:
  /// **'Signing failed. Nothing was sent to the host.'**
  String get keystoneErrorSigning;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
