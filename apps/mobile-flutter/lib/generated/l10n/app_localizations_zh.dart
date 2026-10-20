// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Open Ledger App';

  @override
  String get welcomeTitle => 'Open Ledger App';

  @override
  String get welcomeSubtitle => '兼容 Ledger Nano X 的硬件钱包';

  @override
  String get createWallet => '创建新钱包';

  @override
  String get importWallet => '导入钱包';

  @override
  String get enigmaWallet => '暗语设置';

  @override
  String get unlockTitle => '输入 PIN';

  @override
  String get unlockSubtitle => '输入 6 位 PIN 解锁';

  @override
  String get attemptsRemaining => '剩余尝试次数';

  @override
  String get lockedOut => '已锁定';

  @override
  String get lockedOutReason => '连续 5 次 PIN 输入错误，本机钱包已永久锁定。';

  @override
  String get lockedOutConsequence =>
      '重置会销毁本机全部密钥。钱包只能通过重新导入助记词恢复；没有助记词备份，资金将永久丢失。';

  @override
  String get resetWallet => '重置钱包';

  @override
  String get entropyTitle => '收集随机数';

  @override
  String get entropyInstruction => '点击屏幕任意位置收集随机数';

  @override
  String get entropyProgress => '次触摸';

  @override
  String get generateMnemonicTitle => '您的恢复短语';

  @override
  String get generateMnemonicWarning =>
      '按顺序记录这 12 个单词。不要与任何人分享。任何拥有这些单词的人都可以访问您的资金。';

  @override
  String get iveWrittenItDown => '我已抄写完成';

  @override
  String get continueButton => '继续';

  @override
  String get verifyMnemonicTitle => '验证恢复短语';

  @override
  String verifyWordPosition(Object position) {
    return '选择第 $position 个单词';
  }

  @override
  String get importMnemonicTitle => '导入钱包';

  @override
  String get importMnemonicHint => '输入 12 个恢复短语单词，用空格分隔';

  @override
  String get pasteFromClipboard => '粘贴';

  @override
  String wordsCount(Object count) {
    return '$count / 12 个单词';
  }

  @override
  String get validMnemonic => '有效的恢复短语';

  @override
  String get invalidMnemonic => '无效的恢复短语';

  @override
  String get import => '导入';

  @override
  String get setPinTitle => '创建 PIN';

  @override
  String get setPinSubtitle => '输入 6 位 PIN';

  @override
  String get confirmPin => '确认 PIN';

  @override
  String get confirmPinSubtitle => '确认您的 6 位 PIN';

  @override
  String get pinMismatch => 'PIN 不匹配，请重试';

  @override
  String get changePinTitle => '修改 PIN';

  @override
  String get enterOldPin => '输入旧 PIN';

  @override
  String get enterNewPin => '输入新 PIN';

  @override
  String get enterNewPinSubtitle => '输入新的 6 位 PIN';

  @override
  String get confirmNewPin => '确认新 PIN';

  @override
  String get confirmNewPinSubtitle => '确认您的新 6 位 PIN';

  @override
  String get incorrectPin => 'PIN 不正确';

  @override
  String get pinAlreadyInUse => '该 PIN 已被另一个钱包使用。';

  @override
  String get cancel => '取消';

  @override
  String get back => '返回';

  @override
  String get accountsTitle => '账户';

  @override
  String get vaultWord => '金库';

  @override
  String get switchVault => '切换金库';

  @override
  String get manageVaults => '管理金库';

  @override
  String get newVault => '新建金库';

  @override
  String get vaultLimitReached => '已达金库上限，请先移除一个。';

  @override
  String get vaultAlreadyInTier => '该钱包已经添加过了。';

  @override
  String get renameVault => '重命名';

  @override
  String get removeVault => '移除';

  @override
  String get removeVaultConfirm => '移除该金库？其资产只能通过对应助记词恢复。';

  @override
  String get vaultNameHint => '金库名称';

  @override
  String get vaultPinPrompt => '输入 PIN';

  @override
  String get standInTitle => '马甲钱包';

  @override
  String get standInNotSetUp => '未开启';

  @override
  String get standInConfigured => '已开启';

  @override
  String get standInThreatTitle => '这能防住什么';

  @override
  String get standInThreatBody =>
      '当你被要求当场解锁时，输入马甲 PIN 会展示这份马甲钱包，而不是真实钱包。它能应对现场的当面要求，但不能对抗对设备存储的取证分析。';

  @override
  String get standInModeSectionTitle => '使用马甲 PIN 时的行为';

  @override
  String get standInModeHide => '仅切换';

  @override
  String get standInModeHideDesc => '本次会话只展示马甲钱包。主钱包仍留在设备上，之后仍可用主 PIN 解锁。';

  @override
  String get standInModeWipe => '切换并擦除';

  @override
  String get standInModeWipeDesc => '展示马甲之前先擦除全部主钱包。不可逆——只能靠各钱包的助记词恢复。';

  @override
  String get standInWipeConfirmTitle => '启用擦除模式？';

  @override
  String get standInWipeConfirmBody =>
      '下次使用马甲 PIN 时，本设备上的全部主钱包将被永久擦除。请确认已离线备份各钱包助记词。此操作不可撤销。';

  @override
  String get standInCreateTitle => '创建马甲钱包';

  @override
  String get standInImportTab => '导入助记词';

  @override
  String get standInGenerateTab => '生成助记词';

  @override
  String get standInEnigmaTab => '暗语';

  @override
  String get standInPinTitle => '设置马甲 PIN';

  @override
  String get standInPinSubtitle => '请设置一个与当前 PIN 不同的 6 位 PIN';

  @override
  String get standInPinConfirmTitle => '确认马甲 PIN';

  @override
  String get standInMainPinTitle => '输入当前 PIN';

  @override
  String get standInMainPinSubtitle => '授权创建马甲钱包';

  @override
  String get standInChangePinTitle => '修改马甲 PIN';

  @override
  String get standInChangeModeTitle => '切换行为模式';

  @override
  String get standInRemoveTitle => '移除马甲钱包';

  @override
  String get standInRemoveConfirm => '移除马甲钱包？其资产只能通过对应助记词恢复。主钱包不受影响。';

  @override
  String get standInCurrentPinTitle => '输入当前马甲 PIN';

  @override
  String get standInNewPinTitle => '输入新的马甲 PIN';

  @override
  String get standInNewPinConfirmTitle => '确认新的马甲 PIN';

  @override
  String get standInPinSameAsMain => '马甲 PIN 必须与当前 PIN 不同。';

  @override
  String get standInAlreadyConfigured => '马甲钱包已配置。';

  @override
  String get standInNotConfigured => '尚未配置马甲钱包。';

  @override
  String get standInPrimaryRequired => '此操作需要主钱包会话。';

  @override
  String get standInCreated => '马甲钱包已创建。';

  @override
  String get standInPinUpdated => '马甲 PIN 已更新。';

  @override
  String get standInModeUpdated => '行为模式已更新。';

  @override
  String get standInRemoved => '马甲钱包已移除。';

  @override
  String get standInUnavailable => '当前会话不可用。';

  @override
  String get standInCurrentModeLabel => '行为模式';

  @override
  String get noAccounts => '尚无账户';

  @override
  String get settings => '设置';

  @override
  String get backupSeed => '备份助记词';

  @override
  String get accountDetail => '账户详情';

  @override
  String accountWithIndex(int index) {
    return '账户 $index';
  }

  @override
  String get receive => '收款';

  @override
  String get details => '详情';

  @override
  String get address => '地址';

  @override
  String get copyAddress => '复制地址';

  @override
  String get derivationPath => '派生路径';

  @override
  String get signTransaction => '签名交易';

  @override
  String get transaction => '交易签名';

  @override
  String get transactionDetails => '交易详情';

  @override
  String get from => '发送方';

  @override
  String get to => '接收方';

  @override
  String get value => '金额';

  @override
  String get networkFee => '网络费用';

  @override
  String get chain => '链';

  @override
  String get approve => '批准';

  @override
  String get reject => '拒绝';

  @override
  String get transactionApproved => '交易已签名';

  @override
  String get transactionRejected => '交易已拒绝';

  @override
  String get settingsTitle => '设置';

  @override
  String get appearance => '外观';

  @override
  String get theme => '主题';

  @override
  String get darkMode => '深色模式';

  @override
  String get lightMode => '浅色模式';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get language => '语言';

  @override
  String get security => '安全';

  @override
  String get changePin => '修改 PIN';

  @override
  String get resetWalletTitle => '重置钱包';

  @override
  String get resetWalletConfirm => '确定要重置吗？此操作会销毁本机全部密钥，且不可撤销。钱包只能通过重新导入助记词恢复。';

  @override
  String get reset => '重置';

  @override
  String get bleName => 'BLE 名称';

  @override
  String get bleNameHint => '输入 BLE 设备名称';

  @override
  String get about => '关于';

  @override
  String get version => '版本';

  @override
  String get backupSeedTitle => '备份助记词';

  @override
  String get backupSeedWarning => '永远不要分享您的助记词！任何人拥有这些单词都可以访问您的资金。';

  @override
  String get copyToClipboard => '复制到剪贴板';

  @override
  String get copiedToClipboard => '已复制到剪贴板！';

  @override
  String get enigmaTitle => '暗语钱包';

  @override
  String get enigmaDescription => '通过难忘的短语和密钥确定性生成钱包。';

  @override
  String get enterRiddle => '输入暗语';

  @override
  String get enterSecretKey => '输入密钥';

  @override
  String get generateWallet => '生成钱包';

  @override
  String get enigmaMnemonicTitle => '暗语恢复短语';

  @override
  String get enigmaMnemonicWarning => '保存这 24 个单词。您可以随时用暗语和密钥重新生成它们。';

  @override
  String get processing => '处理中';

  @override
  String get done => '完成';

  @override
  String get error => '错误';

  @override
  String get success => '成功';

  @override
  String get addAccount => '添加账户';

  @override
  String get startBle => '启动 BLE';

  @override
  String get stopBroadcast => '关闭广播';

  @override
  String get tapActiveChainToStop => '再次点按当前链可关闭广播';

  @override
  String get tapChainToStartBroadcast => '点按链开始广播';

  @override
  String get bleLogs => 'BLE 日志';

  @override
  String get signPending => '签名请求待审批';

  @override
  String bleBroadcastAs(String chain) {
    return '以 $chain 身份广播';
  }

  @override
  String get fingerprint => '指纹';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get languageJapanese => '日本語';

  @override
  String get languageKorean => '한국어';

  @override
  String get bluetooth => '蓝牙';

  @override
  String get deleteAllWalletData => '删除此设备上的所有钱包数据';

  @override
  String get ledgerCompatible => '兼容 Ledger Nano X';

  @override
  String get forgotPin => '忘记 PIN？';

  @override
  String get unexpectedError => '意外错误，请重试。';

  @override
  String get generateWithTouch => '通过触摸生成新的助记词';

  @override
  String get restoreFromSeed => '从助记词恢复钱包';

  @override
  String get advancedEnigma => '通过暗语生成钱包';

  @override
  String get tapRandomly => '在屏幕上随机点击以收集熵值来生成恢复短语。';

  @override
  String get retry => '重试';

  @override
  String get correct => '正确！';

  @override
  String get incorrectTryAgain => '错误 — 再试一次';

  @override
  String get whichWord => '您写下了哪个单词？';

  @override
  String get enterPinToReveal => '输入 PIN 以显示助记词';

  @override
  String get yourSeedPhrase => '您的助记词';

  @override
  String get writeDown12Words => '按顺序记录这 12 个单词并安全保管。';

  @override
  String get makeSurePrivate => '请确保您在私密环境中查看。';

  @override
  String get walletLockedHint => '钱包已永久锁定，请返回并重置钱包后才能继续使用。';

  @override
  String get yourRiddle => '您的暗语';

  @override
  String get secretKey => '密钥';

  @override
  String get mnemonicLanguage => '助记词语言';

  @override
  String get enterMemorablePhrase => '输入一个难忘的短语、问题或暗语...';

  @override
  String get tipLongUnique => '提示：使用长且独特的暗语和密钥以获取最大安全性。';

  @override
  String get yourEnigmaSeedPhrase => '您的暗语种子短语';

  @override
  String get continueToSetPin => '继续设置 PIN';

  @override
  String get noMnemonicGenerated => '未生成助记词。请返回重试。';

  @override
  String get writeDown24Words => '按顺序记录这 24 个单词并安全保管。任何人拥有这些单词都可访问您的资金。';

  @override
  String get neverShareSeed => '永远不要分享您的助记词！';

  @override
  String get passphraseOptional => '密码短语（可选）';

  @override
  String get advancedBip39Passphrase => '高级：添加 BIP39 密码短语（可选）';

  @override
  String get enterPassphraseOptional => '输入密码短语（可选）';

  @override
  String get bip39PassphraseExplanation =>
      'BIP39 密码短语可以创建一个完全不同的钱包。如果使用，您必须记住它——无法恢复。';

  @override
  String get displayLanguage => '显示语言';

  @override
  String get displayLanguageNote => '显示语言仅影响单词的显示方式，不影响钱包的生成方式。';

  @override
  String get leaveEmptyStandard => '留空以使用标准暗语钱包。';

  @override
  String get seedDerivedFromEnglish => '该种子源自英文助记词。无论显示语言如何，它始终相同。';

  @override
  String get historyTab => '历史';

  @override
  String get noSigningHistory => '暂无签名历史';

  @override
  String get transactionSignaturesWillAppear => '交易签名将显示在此处';

  @override
  String get signed => '已签名';

  @override
  String get rejectedStatus => '已拒绝';

  @override
  String get failedStatus => '失败';

  @override
  String get signingAddress => '签名地址';

  @override
  String get statusWord => '状态字';

  @override
  String get payload => '负载';

  @override
  String get justNow => '刚刚';

  @override
  String get noAccountSelected => '未选择账户';

  @override
  String get publicKey => '公钥';

  @override
  String get bleAccess => 'BLE 访问';

  @override
  String get enabled => '已启用';

  @override
  String get disabled => '已禁用';

  @override
  String get blePeripheral => 'BLE 外设';

  @override
  String get connected => '已连接';

  @override
  String get broadcasting => '广播中';

  @override
  String get advertisingAs => '正在以 Ledger Nano X 身份广播，等待连接。';

  @override
  String get startBleBroadcasting => '启动 BLE 广播以接受签名请求。';

  @override
  String get noBleActivity => '暂无 BLE 活动';

  @override
  String get currentApp => '当前应用';

  @override
  String get currentAppHint => '钱包会把设备识别为该应用。连接 Solana 账户前请先选择 Solana。';

  @override
  String get dataHex => '数据十六进制';

  @override
  String get dataSize => '数据大小';

  @override
  String get decodedAction => '解码操作';

  @override
  String get chainEthereum => '以太坊';

  @override
  String get chainEthereumEvm => '以太坊 & EVM 链';

  @override
  String get chainSolana => 'Solana';

  @override
  String get chainBitcoin => '比特币';

  @override
  String get chainTron => 'Tron';

  @override
  String get chainSui => 'Sui';

  @override
  String get chainPersonalMessage => 'Ethereum — 个人消息签名';

  @override
  String get chainEip712 => 'Ethereum — EIP-712';

  @override
  String get eip712TypedData => 'EIP-712 类型化数据';

  @override
  String get domainHash => '域哈希';

  @override
  String get structHash => '结构哈希';

  @override
  String get messageToSign => '待签名消息';

  @override
  String get gasLimit => 'Gas 限制';

  @override
  String get gasPrice => 'Gas 价格';

  @override
  String get maxFee => '最大费用';

  @override
  String get priorityFee => '优先费用';

  @override
  String get nonce => 'Nonce';

  @override
  String get chainId => '链 ID';

  @override
  String showAll(Object bytes) {
    return '显示全部（$bytes 字节）';
  }

  @override
  String get showMore => '展开';

  @override
  String get showLess => '收起';

  @override
  String get rawSignature => '原始签名';

  @override
  String get signatureResult => '签名结果';

  @override
  String get amount => '数量';

  @override
  String get spender => '支出方';

  @override
  String get methodLabel => '方法';

  @override
  String get messageLabel => '消息';

  @override
  String get backupSection => '备份';

  @override
  String get exportPrivateKey => '导出该账户私钥';

  @override
  String get exportPrivateKeySubtitle => '二维码导出 · 仅本设备显示';

  @override
  String get exportEntryHint => '助记词与全部账户私钥：设置 → 备份与导出';

  @override
  String get privateKeyExportTitle => '导出私钥';

  @override
  String get privateKeyWarning => '私钥可完全控制该账户的资产，且无法像助记词那样更换。请勿截屏、勿拍照。';

  @override
  String get encoding => '编码';

  @override
  String autoHideHint(int seconds) {
    return '${seconds}s 后自动隐藏 · 离开即清除';
  }

  @override
  String get iveBackedUp => '我已备份完成';

  @override
  String get exportSeedTitle => '助记词';

  @override
  String get mnemonicQrWarning => '请勿截屏、勿拍照、勿展示给他人。';

  @override
  String get englishBip39Note => '二维码为英文 12/24 词 BIP-39，通用钱包均可导入';

  @override
  String get passphraseNotIncluded =>
      '此钱包启用了 BIP-39 passphrase —— 它不在二维码内，请确认你已单独记下。';

  @override
  String walletChip(String fingerprint) {
    return '钱包 · $fingerprint';
  }

  @override
  String get backupAndExport => '备份与导出';

  @override
  String get exportSeedQrRow => '助记词二维码';

  @override
  String get exportSeedQrRowSubtitle => '12/24 词 · 可恢复全部账户';

  @override
  String get privateKeysRow => '私钥';

  @override
  String get privateKeysRowSubtitle => '按账户导出 · 通常无需导出';

  @override
  String get privateKeysRareNote => '助记词已足够恢复全部私钥，仅在目标钱包不支持助记词导入时才需要导出私钥。';

  @override
  String get verifySectionHeader => '验证';

  @override
  String get verifyRowSubtitle => '确认你抄写的备份正确无误';

  @override
  String get verifySeedTitle => '验证助记词';

  @override
  String get verifySeedHint => '输入你抄写备份中的助记词，用空格分隔。输入内容不会离开本设备。';

  @override
  String get verifyPassphraseTitle => '验证 passphrase';

  @override
  String get verifyPassphraseHint =>
      '输入你为本钱包设置的 BIP-39 passphrase。若从未设置，请留空——检查将确认本钱包无需 passphrase。';

  @override
  String get verifyEnigmaTitle => '验证暗语';

  @override
  String get verifyEnigmaHint => '输入你创建本钱包时使用的谜语与密钥。';

  @override
  String get enigmaRiddleLabel => '谜语';

  @override
  String get enigmaSecretLabel => '密钥';

  @override
  String get verifyAction => '验证';

  @override
  String get verifyResultMatch => '一致——你的备份正确。';

  @override
  String get verifyResultMismatch => '不一致。请检查是否输入有误后重试。';

  @override
  String get verifyResultUnavailable => '暂时无法核对。请解锁钱包并确认它有一个以太坊账户。';

  @override
  String get privacyShield => '内容已隐藏';

  @override
  String get disguiseTitle => '应用伪装';

  @override
  String get disguiseStandard => '标准';

  @override
  String get disguiseCalculator => '计算器';

  @override
  String get disguiseConfirmTitle => '更换应用伪装？';

  @override
  String disguiseConfirmBody(String name) {
    return '桌面图标与名称将变为「$name」，桌面刷新可能需要几秒钟。钱包数据与 PIN 不受影响。如需换回，打开本应用回到这里即可。';
  }

  @override
  String get disguiseConfirmButton => '更换';
}
