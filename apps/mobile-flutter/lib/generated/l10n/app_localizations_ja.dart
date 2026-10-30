// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Open Ledger App';

  @override
  String get welcomeTitle => 'Open Ledger App';

  @override
  String get welcomeSubtitle => 'Ledger Nano X互換ハードウェアウォレット';

  @override
  String get createWallet => '新規ウォレット作成';

  @override
  String get importWallet => 'ウォレットをインポート';

  @override
  String get enigmaWallet => '合言葉セットアップ';

  @override
  String get unlockTitle => 'PINを入力';

  @override
  String get unlockSubtitle => '6桁のPINを入力してロック解除';

  @override
  String get attemptsRemaining => '残り試行回数';

  @override
  String get lockedOut => 'ロックアウト';

  @override
  String get lockedOutReason => 'PINを5回誤入力したため、この端末のウォレットは永久にロックされました。';

  @override
  String get lockedOutConsequence =>
      'リセットすると本端末のすべての鍵が削除されます。ウォレットはリカバリーフレーズの再インポートでのみ復元でき、バックアップがない場合は資金を永久に失います。';

  @override
  String get resetWallet => 'ウォレットをリセット';

  @override
  String get entropyTitle => 'エントロピー収集';

  @override
  String get entropyInstruction => '画面の任意の場所をタップしてエントロピーを収集';

  @override
  String get entropyProgress => 'タップ';

  @override
  String get generateMnemonicTitle => 'リカバリーフレーズ';

  @override
  String get generateMnemonicWarning =>
      'これら12の単語を順番に書き留めてください。誰とも共有しないでください。これらの単語があれば誰でも資金にアクセスできます。';

  @override
  String get iveWrittenItDown => '書き留めました';

  @override
  String get continueButton => '続ける';

  @override
  String get verifyMnemonicTitle => 'フレーズを確認';

  @override
  String verifyWordPosition(Object position) {
    return '単語 #$position を選択';
  }

  @override
  String get importMnemonicTitle => 'ウォレットをインポート';

  @override
  String get importMnemonicHint => '12語または24語のリカバリーフレーズをスペース区切りで入力';

  @override
  String get pasteFromClipboard => '貼り付け';

  @override
  String get scanQrCode => 'QRをスキャン';

  @override
  String get qrScanTitle => 'リカバリーフレーズをスキャン';

  @override
  String get qrScanHint => 'カメラをリカバリーフレーズのQRコードに向けてください';

  @override
  String get qrScanPermissionDenied => 'カメラへのアクセスが拒否されました。設定で許可してください。';

  @override
  String get qrScanCameraError => 'カメラを利用できません。リカバリーフレーズは手入力または貼り付けできます。';

  @override
  String get qrScanInvalid => 'このQRコードには12語または24語のリカバリーフレーズが含まれていません。';

  @override
  String wordsCount(int count, int target) {
    return '$count / $target 語';
  }

  @override
  String get validMnemonic => '有効なリカバリーフレーズ';

  @override
  String get invalidMnemonic => '無効なリカバリーフレーズ';

  @override
  String get import => 'インポート';

  @override
  String get setPinTitle => 'PINを作成';

  @override
  String get setPinSubtitle => '6桁のPINを入力';

  @override
  String get confirmPin => 'PIN確認';

  @override
  String get confirmPinSubtitle => '6桁のPINを再入力';

  @override
  String get pinMismatch => 'PINが一致しません。再試行してください。';

  @override
  String get changePinTitle => 'PIN変更';

  @override
  String get enterOldPin => '現在のPINを入力';

  @override
  String get enterNewPin => '新しいPINを入力';

  @override
  String get enterNewPinSubtitle => '新しい6桁のPINを入力';

  @override
  String get confirmNewPin => '新しいPINを確認';

  @override
  String get confirmNewPinSubtitle => '新しい6桁のPINを再入力';

  @override
  String get incorrectPin => 'PINが正しくありません';

  @override
  String get pinAlreadyInUse => 'このPINは別のウォレットで使用されています。';

  @override
  String get cancel => 'キャンセル';

  @override
  String get back => '戻る';

  @override
  String get accountsTitle => 'アカウント';

  @override
  String get vaultWord => '金庫';

  @override
  String get switchVault => '金庫を切り替え';

  @override
  String get manageVaults => '金庫を管理';

  @override
  String get newVault => '新しい金庫';

  @override
  String get newVaultImportTab => 'フレーズをインポート';

  @override
  String get newVaultSecretTab => '合言葉';

  @override
  String get vaultLimitReached => '金庫の上限に達しました。先に一つ削除してください。';

  @override
  String get vaultAlreadyInTier => 'このウォレットは既に追加されています。';

  @override
  String get renameVault => '名前を変更';

  @override
  String get removeVault => '削除';

  @override
  String get removeVaultConfirm => 'この金庫を削除しますか？資産は復元フレーズでのみ復元できます。';

  @override
  String get vaultNameHint => '金庫名';

  @override
  String get vaultPinPrompt => 'PIN を入力';

  @override
  String get standInTitle => '代役ウォレット';

  @override
  String get standInNotSetUp => '未設定';

  @override
  String get standInConfigured => '設定済み';

  @override
  String get standInThreatTitle => 'これが防げるもの';

  @override
  String get standInThreatBody =>
      'その場でロック解除を求められたとき、代役 PIN を入力すると本当のウォレットではなくこの代役ウォレットを表示します。その場の要求には有効ですが、端末ストレージのフォレンジック分析には対応しません。';

  @override
  String get standInModeSectionTitle => '代役 PIN 使用時の動作';

  @override
  String get standInModeHide => '切り替えのみ';

  @override
  String get standInModeHideDesc =>
      'このセッションでは代役ウォレットのみを表示します。本体ウォレットは端末に残り、後で本体 PIN で解除できます。';

  @override
  String get standInModeWipe => '切り替え＋消去';

  @override
  String get standInModeWipeDesc =>
      '代役を表示する前にすべての本体ウォレットを消去します。不可逆——各ウォレットのリカバリーフレーズでのみ復元できます。';

  @override
  String get standInWipeConfirmTitle => '消去モードを使用しますか？';

  @override
  String get standInWipeConfirmBody =>
      '次に代役 PIN を使用すると、この端末のすべての本体ウォレットが完全に消去されます。各リカバリーフレーズをオフラインでバックアップ済みか確認してください。この操作は元に戻せません。';

  @override
  String get standInCreateTitle => '代役ウォレットを作成';

  @override
  String get standInImportTab => 'フレーズをインポート';

  @override
  String get standInGenerateTab => 'フレーズを生成';

  @override
  String get standInEnigmaTab => '合言葉';

  @override
  String get standInPinTitle => '代役 PIN を設定';

  @override
  String get standInPinSubtitle => '現在の PIN とは異なる 6 桁の PIN を設定してください';

  @override
  String get standInPinConfirmTitle => '代役 PIN を確認';

  @override
  String get standInMainPinTitle => '現在の PIN を入力';

  @override
  String get standInMainPinSubtitle => '代役ウォレットの作成を承認';

  @override
  String get standInChangePinTitle => '代役 PIN を変更';

  @override
  String get standInChangeModeTitle => '動作を変更';

  @override
  String get standInRemoveTitle => '代役ウォレットを削除';

  @override
  String get standInRemoveConfirm =>
      '代役ウォレットを削除しますか？資産はリカバリーフレーズでのみ復元できます。本体ウォレットには影響しません。';

  @override
  String get standInCurrentPinTitle => '現在の代役 PIN を入力';

  @override
  String get standInNewPinTitle => '新しい代役 PIN を入力';

  @override
  String get standInNewPinConfirmTitle => '新しい代役 PIN を確認';

  @override
  String get standInPinSameAsMain => '代役 PIN は現在の PIN と異なる必要があります。';

  @override
  String get standInAlreadyConfigured => '代役ウォレットはすでに設定されています。';

  @override
  String get standInNotConfigured => '代役ウォレットが設定されていません。';

  @override
  String get standInPrimaryRequired => 'この操作には本体ウォレットのセッションが必要です。';

  @override
  String get standInCreated => '代役ウォレットを設定しました。';

  @override
  String get standInPinUpdated => '代役 PIN を更新しました。';

  @override
  String get standInModeUpdated => '動作を更新しました。';

  @override
  String get standInRemoved => '代役ウォレットを削除しました。';

  @override
  String get standInUnavailable => 'このセッションでは利用できません。';

  @override
  String get standInCurrentModeLabel => '動作';

  @override
  String get noAccounts => 'アカウントがありません';

  @override
  String get settings => '設定';

  @override
  String get backupSeed => 'シードバックアップ';

  @override
  String get accountDetail => 'アカウント詳細';

  @override
  String accountWithIndex(int index) {
    return 'アカウント $index';
  }

  @override
  String get receive => '受け取る';

  @override
  String get details => '詳細';

  @override
  String get address => 'アドレス';

  @override
  String get copyAddress => 'アドレスをコピー';

  @override
  String get addressRequestTitle => 'アドレス要求';

  @override
  String get addressRequestHint =>
      '接続中のアプリがこのアドレスを要求しています。承認すると公開アドレスを返し、拒否すると要求を断ります。リカバリーフレーズと秘密鍵は送信されません。';

  @override
  String get derivationPath => '導出パス';

  @override
  String get signTransaction => '取引に署名';

  @override
  String get transaction => '取引署名';

  @override
  String get transactionDetails => '取引詳細';

  @override
  String get from => '送信元';

  @override
  String get to => '送信先';

  @override
  String get value => '金額';

  @override
  String get networkFee => 'ネットワーク手数料';

  @override
  String get chain => 'チェーン';

  @override
  String get approve => '承認';

  @override
  String get reject => '拒否';

  @override
  String get transactionApproved => '取引が署名されました';

  @override
  String get transactionRejected => '取引が拒否されました';

  @override
  String get settingsTitle => '設定';

  @override
  String get appearance => '外観';

  @override
  String get theme => 'テーマ';

  @override
  String get darkMode => 'ダークモード';

  @override
  String get lightMode => 'ライトモード';

  @override
  String get themeSystem => 'システム';

  @override
  String get language => '言語';

  @override
  String get security => 'セキュリティ';

  @override
  String get changePin => 'PIN変更';

  @override
  String get resetWalletTitle => 'ウォレットをリセット';

  @override
  String get resetWalletConfirm =>
      '本当にリセットしますか？本端末のすべての鍵を削除し、この操作は元に戻せません。ウォレットはリカバリーフレーズの再インポートでのみ復元できます。';

  @override
  String get reset => 'リセット';

  @override
  String get bleName => 'BLE名';

  @override
  String get bleNameHint => 'BLEデバイス名を入力';

  @override
  String get about => 'について';

  @override
  String get version => 'バージョン';

  @override
  String get backupSeedTitle => 'シードバックアップ';

  @override
  String get backupSeedWarning =>
      'シードフレーズを絶対に共有しないでください！これらの単語があれば誰でも資金にアクセスできます。';

  @override
  String get copyToClipboard => 'クリップボードにコピー';

  @override
  String get copiedToClipboard => 'クリップボードにコピーしました！';

  @override
  String get enigmaTitle => '合言葉ウォレット';

  @override
  String get enigmaDescription => '記憶に残るフレーズと秘密鍵から決定論的ウォレットを生成します。';

  @override
  String enigmaMatchCount(int count) {
    return 'BIP-39 の単語に $count 個一致しました';
  }

  @override
  String get enigmaNoMatch =>
      'BIP-39 の単語が見つかりません。このフレーズはエントロピーに寄与せず、ウォレットは秘密鍵のみに依存します。';

  @override
  String get enterRiddle => '合言葉を入力';

  @override
  String get enterSecretKey => '秘密鍵を入力';

  @override
  String get generateWallet => 'ウォレットを生成';

  @override
  String get enigmaMnemonicTitle => '合言葉リカバリーフレーズ';

  @override
  String get enigmaMnemonicWarning =>
      'これら24の単語を保存してください。合言葉と秘密鍵を使っていつでも再生成できます。';

  @override
  String get processing => '処理中';

  @override
  String get done => '完了';

  @override
  String get error => 'エラー';

  @override
  String get success => '成功';

  @override
  String get addAccount => 'アカウント追加';

  @override
  String get btcAddressTypeTitle => 'ビットコインのアドレスタイプ';

  @override
  String get btcAddressTypeHint =>
      '4つのタイプはそれぞれ別の派生パスの独立したアカウントです。取引所やウォレットが対応する形式を選んでください。';

  @override
  String get btcAddressTypeLegacy => 'Legacy';

  @override
  String get btcAddressTypeNestedSegwit => 'Nested SegWit';

  @override
  String get btcAddressTypeNativeSegwit => 'Native SegWit';

  @override
  String get btcAddressTypeTaproot => 'Taproot';

  @override
  String get startBle => 'BLE開始';

  @override
  String get stopBroadcast => 'ブロードキャストを停止';

  @override
  String get tapActiveChainToStop => '選択中のチェーンをもう一度タップすると停止します';

  @override
  String get tapChainToStartBroadcast => 'チェーンをタップしてブロードキャストを開始';

  @override
  String get bleLogs => 'BLEログ';

  @override
  String get signPending => '署名要求処理中';

  @override
  String bleBroadcastAs(String chain) {
    return '$chainとしてブロードキャスト';
  }

  @override
  String get fingerprint => '指紋';

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
  String get deleteAllWalletData => 'このデバイスからすべてのウォレットデータを削除';

  @override
  String get ledgerCompatible => 'Ledger Nano X互換';

  @override
  String get forgotPin => 'PINをお忘れですか？';

  @override
  String get unexpectedError => '予期しないエラーが発生しました。再試行してください。';

  @override
  String get generateWithTouch => 'タッチエントロピーで新しいシードフレーズを生成';

  @override
  String get restoreFromSeed => 'シードフレーズからウォレットを復元';

  @override
  String get advancedEnigma => '合言葉による高度なエントロピー生成';

  @override
  String get tapRandomly => '画面をランダムにタップしてリカバリーフレーズのエントロピーを収集してください。';

  @override
  String get retry => '再試行';

  @override
  String get correct => '正解！';

  @override
  String get incorrectTryAgain => '不正解 — もう一度';

  @override
  String get whichWord => '書き留めた単語はどれですか？';

  @override
  String get enterPinToReveal => 'PINを入力してシードフレーズを表示';

  @override
  String get yourSeedPhrase => 'あなたのシードフレーズ';

  @override
  String get writeDown12Words => 'これら12の単語を順番に書き留め、安全に保管してください。';

  @override
  String get makeSurePrivate => '閲覧する前に、プライベートな場所にいることを確認してください。';

  @override
  String get walletLockedHint => 'ウォレットは永久にロックされました。戻ってウォレットをリセットしてください。';

  @override
  String get yourRiddle => 'あなたの合言葉';

  @override
  String get secretKey => '秘密鍵';

  @override
  String get mnemonicLanguage => 'ニーモニック言語';

  @override
  String get enterMemorablePhrase => '覚えやすいフレーズ、質問、または合言葉を入力...';

  @override
  String get tipLongUnique => 'ヒント：最大限のセキュリティのために、長くてユニークな合言葉と秘密鍵を使用してください。';

  @override
  String get yourEnigmaSeedPhrase => 'あなたの合言葉シードフレーズ';

  @override
  String get continueToSetPin => 'PIN設定に進む';

  @override
  String get noMnemonicGenerated => 'ニーモニックが生成されていません。戻ってもう一度試してください。';

  @override
  String get writeDown24Words =>
      'これら24の単語を順番に書き留め、安全に保管してください。これらの単語があれば誰でも資金にアクセスできます。';

  @override
  String get neverShareSeed => 'シードフレーズを絶対に共有しないでください！';

  @override
  String get passphraseOptional => 'パスフレーズ（任意）';

  @override
  String get advancedBip39Passphrase => '詳細設定：BIP39パスフレーズを追加（任意）';

  @override
  String get enterPassphraseOptional => 'パスフレーズを入力（任意）';

  @override
  String get bip39PassphraseExplanation =>
      'BIP39パスフレーズは完全に異なるウォレットを作成します。使用する場合は必ず覚えておいてください。復元する方法はありません。';

  @override
  String get displayLanguage => '表示言語';

  @override
  String get displayLanguageNote => '表示言語は単語の見た目にのみ影響し、ウォレットの生成方法には影響しません。';

  @override
  String get leaveEmptyStandard => '標準の合言葉ウォレットの場合は空欄にしてください。';

  @override
  String get seedDerivedFromEnglish =>
      'このシードは英語のニーモニックから派生しています。表示言語に関係なく常に同じです。';

  @override
  String get historyTab => '履歴';

  @override
  String get noSigningHistory => '署名履歴はありません';

  @override
  String get transactionSignaturesWillAppear => '取引署名がここに表示されます';

  @override
  String get signed => '署名済み';

  @override
  String get rejectedStatus => '拒否';

  @override
  String get failedStatus => '失敗';

  @override
  String get signingAddress => '署名アドレス';

  @override
  String get statusWord => 'ステータスワード';

  @override
  String get payload => 'ペイロード';

  @override
  String get justNow => 'たった今';

  @override
  String get noAccountSelected => 'アカウントが選択されていません';

  @override
  String get publicKey => '公開鍵';

  @override
  String get bleAccess => 'BLEアクセス';

  @override
  String get enabled => '有効';

  @override
  String get disabled => '無効';

  @override
  String get blePeripheral => 'BLEペリフェラル';

  @override
  String get connected => '接続済み';

  @override
  String get broadcasting => 'ブロードキャスト中';

  @override
  String get advertisingAs => 'Ledger Nano Xとしてアドバタイズ中。接続を待っています。';

  @override
  String get startBleBroadcasting => 'BLEブロードキャストを開始して署名リクエストを受け付けます。';

  @override
  String get noBleActivity => 'まだBLEアクティビティはありません';

  @override
  String get currentApp => '現在のアプリ';

  @override
  String get currentAppHint =>
      'ウォレットはデバイスをこのアプリとして認識します。Solana アカウントを接続する前に Solana を選択してください。';

  @override
  String get dataHex => 'データHEX';

  @override
  String get dataSize => 'データサイズ';

  @override
  String get decodedAction => 'デコードされたアクション';

  @override
  String get chainEthereum => 'イーサリアム';

  @override
  String get chainEthereumEvm => 'イーサリアム & EVM チェーン';

  @override
  String get chainSolana => 'Solana';

  @override
  String get chainBitcoin => 'ビットコイン';

  @override
  String get chainTron => 'Tron';

  @override
  String get chainSui => 'Sui';

  @override
  String get chainNear => 'NEAR';

  @override
  String get chainTon => 'TON';

  @override
  String get manageChains => 'チェーン管理';

  @override
  String get manageChainsSheetTitle => 'チェーン管理';

  @override
  String get manageChainsSheetHint =>
      'チェーンをオフにすると、ここにも Bluetooth のアプリ一覧にも表示されません。アカウントは保持されます。';

  @override
  String get chainPersonalMessage => 'Ethereum — パーソナルメッセージ';

  @override
  String get chainEip712 => 'Ethereum — EIP-712';

  @override
  String get eip712TypedData => 'EIP-712型付きデータ';

  @override
  String get domainHash => 'ドメインハッシュ';

  @override
  String get structHash => '構造体ハッシュ';

  @override
  String get messageToSign => '署名するメッセージ';

  @override
  String get gasLimit => 'ガスリミット';

  @override
  String get gasPrice => 'ガス価格';

  @override
  String get maxFee => '最大手数料';

  @override
  String get priorityFee => '優先手数料';

  @override
  String get nonce => 'ノンス';

  @override
  String get chainId => 'チェーンID';

  @override
  String showAll(Object bytes) {
    return 'すべて表示（$bytes バイト）';
  }

  @override
  String get showMore => 'もっと見る';

  @override
  String get showLess => '折りたたむ';

  @override
  String get rawSignature => '生の署名';

  @override
  String get signatureResult => '署名結果';

  @override
  String get amount => '金額';

  @override
  String get spender => '支出者';

  @override
  String get methodLabel => 'メソッド';

  @override
  String get messageLabel => 'メッセージ';

  @override
  String get backupSection => 'バックアップ';

  @override
  String get exportPrivateKey => 'このアカウントの秘密鍵をエクスポート';

  @override
  String get exportPrivateKeySubtitle => 'QR エクスポート · この端末のみに表示';

  @override
  String get exportEntryHint => 'リカバリーフレーズと全秘密鍵：設定 → バックアップとエクスポート';

  @override
  String get privateKeyExportTitle => '秘密鍵をエクスポート';

  @override
  String get privateKeyWarning =>
      '秘密鍵はこのアカウントの資産を完全に支配でき、リカバリーフレーズと違い差し替えができません。スクリーンショットや撮影はしないでください。';

  @override
  String get encoding => 'エンコード';

  @override
  String autoHideHint(int seconds) {
    return '$seconds 秒後に自動非表示 · 離れると消去';
  }

  @override
  String get iveBackedUp => 'バックアップしました';

  @override
  String get exportSeedTitle => 'リカバリーフレーズ';

  @override
  String get mnemonicQrWarning => 'スクリーンショット・撮影・他人への提示はしないでください。';

  @override
  String get englishBip39Note => '英語 12/24 語の BIP-39 — どのウォレットでもインポート可能';

  @override
  String get passphraseNotIncluded =>
      'このウォレットは BIP-39 パスフレーズを有効にしています。QR には含まれません — 別途記録したか確認してください。';

  @override
  String walletChip(String fingerprint) {
    return 'ウォレット · $fingerprint';
  }

  @override
  String get backupAndExport => 'バックアップとエクスポート';

  @override
  String get exportSeedQrRow => 'リカバリーフレーズ QR';

  @override
  String get exportSeedQrRowSubtitle => '12/24 語 · すべてのアカウントを復元';

  @override
  String get privateKeysRow => '秘密鍵';

  @override
  String get privateKeysRowSubtitle => 'アカウント単位 · 通常は不要';

  @override
  String get privateKeysRareNote =>
      'リカバリーフレーズだけで全秘密鍵を復元できます。受け取り側のウォレットがリカバリーフレーズのインポートに対応していない場合のみエクスポートしてください。';

  @override
  String get verifySectionHeader => '検証';

  @override
  String get verifyRowSubtitle => '書き留めた内容が正しいか確認します';

  @override
  String get verifySeedTitle => 'リカバリーフレーズを検証';

  @override
  String get verifySeedHint =>
      '書き留めたバックアップの単語をスペース区切りで入力してください。入力内容がこの端末から出ることはありません。';

  @override
  String get verifyPassphraseTitle => 'パスフレーズを検証';

  @override
  String get verifyPassphraseHint =>
      'このウォレットに設定した BIP-39 パスフレーズを入力してください。設定していない場合は空欄のままにしてください。';

  @override
  String get verifyEnigmaTitle => '秘密のフレーズを検証';

  @override
  String get verifyEnigmaHint => 'このウォレットの作成に使ったリドルとキーを入力してください。';

  @override
  String get enigmaRiddleLabel => 'リドル';

  @override
  String get enigmaSecretLabel => 'キー';

  @override
  String get verifyAction => '検証';

  @override
  String get verifyResultMatch => '一致しました — バックアップは正しいです。';

  @override
  String get verifyResultMismatch => '一致しません。入力ミスがないか確認して再試行してください。';

  @override
  String get verifyResultUnavailable =>
      '現在確認できません。ウォレットのロックを解除し、イーサリアムアカウントがあることを確認してください。';

  @override
  String get privacyShield => '内容を非表示にしました';

  @override
  String get disguiseTitle => 'アプリ偽装';

  @override
  String get disguiseStandard => '標準';

  @override
  String get disguiseCalculator => '電卓';

  @override
  String get disguiseConfirmTitle => 'アプリ偽装を変更しますか？';

  @override
  String disguiseConfirmBody(String name) {
    return 'ホーム画面のアイコンと名前が「$name」に変わります。反映まで数秒かかることがあります。ウォレットのデータや PIN には影響しません。元に戻すには、本アプリを開いてこの画面に戻ってください。';
  }

  @override
  String get disguiseConfirmButton => '変更';

  @override
  String get keystoneTitle => 'Keystone QR';

  @override
  String get keystoneEntryExport => 'ホストとして接続';

  @override
  String get keystoneEntryScan => 'スキャンして署名';

  @override
  String get keystoneExportTitle => 'アカウントをエクスポート';

  @override
  String get keystoneExportHint => 'ホストウォレットでこのコードをスキャンして、含まれるアカウントをインポートします';

  @override
  String get keystoneExportFormatMetaMask => 'MetaMask（5 アドレス）';

  @override
  String get keystoneExportFormatKeystone => 'OKX / Keystone（同期コード）';

  @override
  String keystoneExportAccountRange(int start, int end) {
    return 'アカウント $start–$end';
  }

  @override
  String get keystoneExportPageAddresses => 'このコードに含まれるアドレス';

  @override
  String get keystoneExportPath => 'パス';

  @override
  String get keystoneExportPrev => '前のページ';

  @override
  String get keystoneExportNext => '次のページ';

  @override
  String get keystoneScanTitle => '署名リクエストをスキャン';

  @override
  String get keystoneScanHint => 'MetaMask に表示された QR コードにカメラを向けてください';

  @override
  String keystoneScanProgress(int received, int total) {
    return 'フレームを収集中 $received/$total';
  }

  @override
  String get keystoneReviewTitle => 'リクエストを確認';

  @override
  String get keystoneReviewDataType => '種類';

  @override
  String get keystoneReviewChain => 'チェーン ID';

  @override
  String get keystoneReviewOrigin => 'オリジン';

  @override
  String get keystoneReviewPath => '導出パス';

  @override
  String get keystoneReviewAddress => 'アドレス';

  @override
  String get keystoneReviewDataHash => '署名対象ハッシュ';

  @override
  String get keystoneReviewDataSize => 'データ長';

  @override
  String get keystoneReviewTo => '送金先';

  @override
  String get keystoneReviewAmount => '金額';

  @override
  String get keystoneReviewMessage => 'メッセージ';

  @override
  String get keystoneReviewCalldata => 'コールデータ';

  @override
  String get keystoneReviewUnknownMethod => '不明なメソッド';

  @override
  String get keystoneReviewWarning =>
      'オリジンとアドレスが MetaMask の表示と一致する場合のみ承認してください。';

  @override
  String get keystoneDataTypeTransaction => 'トランザクション';

  @override
  String get keystoneDataTypePersonalMessage => 'パーソナルメッセージ';

  @override
  String get keystoneDataTypeTypedTransaction => 'エンコード済みトランザクション';

  @override
  String keystoneDataTypeUnsupported(int type) {
    return '非対応（$type）';
  }

  @override
  String get keystoneApprove => '署名';

  @override
  String get keystoneReject => '拒否';

  @override
  String get keystoneSignatureTitle => '署名結果';

  @override
  String get keystoneSignatureHint => 'このコードを MetaMask でスキャンして完了します';

  @override
  String get keystoneDone => '完了';

  @override
  String get keystoneRetry => '再試行';

  @override
  String get keystoneErrorTimeout => 'リクエストのフレーム待ちがタイムアウトしました。';

  @override
  String get keystoneErrorUnexpectedQr =>
      'この QR コードは Keystone の署名リクエストではありません。';

  @override
  String get keystoneErrorInvalidRequest => 'この署名リクエストを解析できませんでした。';

  @override
  String get keystoneErrorCodecUnavailable => 'このビルドでは QR を利用できません。';

  @override
  String get keystoneErrorSigning => '署名に失敗しました。ホストには何も送信していません。';
}
