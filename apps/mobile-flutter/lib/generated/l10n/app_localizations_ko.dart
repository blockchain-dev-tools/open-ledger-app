// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'Open Ledger App';

  @override
  String get welcomeTitle => 'Open Ledger App';

  @override
  String get welcomeSubtitle => 'Ledger Nano X 호환 하드웨어 지갑';

  @override
  String get createWallet => '새 지갑 만들기';

  @override
  String get importWallet => '지갑 가져오기';

  @override
  String get enigmaWallet => '비밀 문구 설정';

  @override
  String get unlockTitle => 'PIN 입력';

  @override
  String get unlockSubtitle => '잠금 해제를 위해 6자리 PIN 입력';

  @override
  String get attemptsRemaining => '남은 시도 횟수';

  @override
  String get lockedOut => '잠김';

  @override
  String get lockedOutReason => 'PIN을 5회 잘못 입력하여 이 기기의 지갑이 영구적으로 잠겼습니다.';

  @override
  String get lockedOutConsequence =>
      '초기화하면 이 기기의 모든 키가 삭제됩니다. 지갑은 복구 문구를 다시 가져와야만 복원할 수 있으며, 백업이 없으면 자금을 영구적으로 잃게 됩니다.';

  @override
  String get resetWallet => '지갑 초기화';

  @override
  String get entropyTitle => '엔트로피 수집';

  @override
  String get entropyInstruction => '화면 아무 곳이나 터치하여 엔트로피 수집';

  @override
  String get entropyProgress => '터치';

  @override
  String get generateMnemonicTitle => '복구 구문';

  @override
  String get generateMnemonicWarning =>
      '이 12개 단어를 순서대로 적어두세요. 절대 다른 사람과 공유하지 마세요. 이 단어를 가진 사람은 누구나 자금에 접근할 수 있습니다.';

  @override
  String get iveWrittenItDown => '받아 적었습니다';

  @override
  String get continueButton => '계속';

  @override
  String get verifyMnemonicTitle => '구문 확인';

  @override
  String verifyWordPosition(Object position) {
    return '단어 #$position 선택';
  }

  @override
  String get importMnemonicTitle => '지갑 가져오기';

  @override
  String get importMnemonicHint => '12개 또는 24개 단어로 된 복구 구문을 공백으로 구분하여 입력';

  @override
  String get pasteFromClipboard => '붙여넣기';

  @override
  String get scanQrCode => 'QR 스캔';

  @override
  String get qrScanTitle => '복구 구문 스캔';

  @override
  String get qrScanHint => '카메라를 복구 구문 QR 코드에 맞추세요';

  @override
  String get qrScanPermissionDenied => '카메라 접근이 거부되었습니다. 설정에서 허용해 주세요.';

  @override
  String get qrScanCameraError =>
      '카메라를 사용할 수 없습니다. 복구 구문을 직접 입력하거나 붙여넣을 수 있습니다.';

  @override
  String get qrScanInvalid => '이 QR 코드에는 12개 또는 24개 단어의 복구 구문이 없습니다.';

  @override
  String wordsCount(int count, int target) {
    return '$count / $target개 단어';
  }

  @override
  String get validMnemonic => '유효한 복구 구문';

  @override
  String get invalidMnemonic => '유효하지 않은 복구 구문';

  @override
  String get import => '가져오기';

  @override
  String get setPinTitle => 'PIN 생성';

  @override
  String get setPinSubtitle => '6자리 PIN 입력';

  @override
  String get confirmPin => 'PIN 확인';

  @override
  String get confirmPinSubtitle => '6자리 PIN 재입력';

  @override
  String get pinMismatch => 'PIN이 일치하지 않습니다. 다시 시도하세요.';

  @override
  String get changePinTitle => 'PIN 변경';

  @override
  String get enterOldPin => '현재 PIN 입력';

  @override
  String get enterNewPin => '새 PIN 입력';

  @override
  String get enterNewPinSubtitle => '새 6자리 PIN 입력';

  @override
  String get confirmNewPin => '새 PIN 확인';

  @override
  String get confirmNewPinSubtitle => '새 6자리 PIN 재입력';

  @override
  String get incorrectPin => '잘못된 PIN';

  @override
  String get pinAlreadyInUse => '이 PIN은 다른 지갑에서 사용 중입니다.';

  @override
  String get cancel => '취소';

  @override
  String get back => '뒤로';

  @override
  String get accountsTitle => '계정';

  @override
  String get vaultWord => '금고';

  @override
  String get switchVault => '지갑 전환';

  @override
  String get manageVaults => '지갑 관리';

  @override
  String get newVault => '새 지갑';

  @override
  String get vaultLimitReached => '지갑 한도에 도달했습니다. 먼저 하나를 삭제하세요.';

  @override
  String get vaultAlreadyInTier => '이미 추가된 지갑입니다.';

  @override
  String get renameVault => '이름 변경';

  @override
  String get removeVault => '삭제';

  @override
  String get removeVaultConfirm => '이 지갑을 삭제할까요? 자산은 복구 구문으로만 복원할 수 있습니다.';

  @override
  String get vaultNameHint => '지갑 이름';

  @override
  String get vaultPinPrompt => 'PIN을 입력하세요';

  @override
  String get standInTitle => '대역 지갑';

  @override
  String get standInNotSetUp => '미설정';

  @override
  String get standInConfigured => '설정됨';

  @override
  String get standInThreatTitle => '이것이 막아주는 것';

  @override
  String get standInThreatBody =>
      '현장에서 잠금 해제를 요구받았을 때 대역 PIN을 입력하면 실제 지갑 대신 이 대역 지갑이 표시됩니다. 현장의 요구에는 대응하지만, 기기 저장소의 포렌식 분석에는 대응하지 않습니다.';

  @override
  String get standInModeSectionTitle => '대역 PIN 사용 시 동작';

  @override
  String get standInModeHide => '전환만';

  @override
  String get standInModeHideDesc =>
      '이 세션에서는 대역 지갑만 표시합니다. 실제 지갑은 기기에 남아 있으며 나중에 실제 PIN으로 잠금 해제할 수 있습니다.';

  @override
  String get standInModeWipe => '전환 후 삭제';

  @override
  String get standInModeWipeDesc =>
      '대역을 표시하기 전에 모든 실제 지갑을 삭제합니다. 되돌릴 수 없으며 각 지갑의 복구 문구로만 복원할 수 있습니다.';

  @override
  String get standInWipeConfirmTitle => '삭제 모드를 사용할까요?';

  @override
  String get standInWipeConfirmBody =>
      '다음에 대역 PIN을 사용하면 이 기기의 모든 실제 지갑이 영구적으로 삭제됩니다. 각 복구 문구를 오프라인에 백업했는지 확인하세요. 되돌릴 수 없습니다.';

  @override
  String get standInCreateTitle => '대역 지갑 만들기';

  @override
  String get standInImportTab => '문구 가져오기';

  @override
  String get standInGenerateTab => '문구 생성';

  @override
  String get standInEnigmaTab => '비밀 문구';

  @override
  String get standInPinTitle => '대역 PIN 설정';

  @override
  String get standInPinSubtitle => '현재 PIN과 다른 6자리 PIN을 설정하세요';

  @override
  String get standInPinConfirmTitle => '대역 PIN 확인';

  @override
  String get standInMainPinTitle => '현재 PIN 입력';

  @override
  String get standInMainPinSubtitle => '대역 지갑 생성을 승인';

  @override
  String get standInChangePinTitle => '대역 PIN 변경';

  @override
  String get standInChangeModeTitle => '동작 변경';

  @override
  String get standInRemoveTitle => '대역 지갑 삭제';

  @override
  String get standInRemoveConfirm =>
      '대역 지갑을 삭제할까요? 자산은 복구 문구로만 복원할 수 있습니다. 실제 지갑은 영향을 받지 않습니다.';

  @override
  String get standInCurrentPinTitle => '현재 대역 PIN 입력';

  @override
  String get standInNewPinTitle => '새 대역 PIN 입력';

  @override
  String get standInNewPinConfirmTitle => '새 대역 PIN 확인';

  @override
  String get standInPinSameAsMain => '대역 PIN은 현재 PIN과 달라야 합니다.';

  @override
  String get standInAlreadyConfigured => '대역 지갑이 이미 설정되어 있습니다.';

  @override
  String get standInNotConfigured => '대역 지갑이 설정되지 않았습니다.';

  @override
  String get standInPrimaryRequired => '이 작업에는 실제 지갑 세션이 필요합니다.';

  @override
  String get standInCreated => '대역 지갑이 설정되었습니다.';

  @override
  String get standInPinUpdated => '대역 PIN이 업데이트되었습니다.';

  @override
  String get standInModeUpdated => '동작이 업데이트되었습니다.';

  @override
  String get standInRemoved => '대역 지갑이 삭제되었습니다.';

  @override
  String get standInUnavailable => '이 세션에서는 사용할 수 없습니다.';

  @override
  String get standInCurrentModeLabel => '동작';

  @override
  String get noAccounts => '계정이 없습니다';

  @override
  String get settings => '설정';

  @override
  String get backupSeed => '시드 백업';

  @override
  String get accountDetail => '계정 세부정보';

  @override
  String accountWithIndex(int index) {
    return '계정 $index';
  }

  @override
  String get receive => '받기';

  @override
  String get details => '상세';

  @override
  String get address => '주소';

  @override
  String get copyAddress => '주소 복사';

  @override
  String get derivationPath => '파생 경로';

  @override
  String get signTransaction => '거래 서명';

  @override
  String get transaction => '거래 서명';

  @override
  String get transactionDetails => '거래 세부정보';

  @override
  String get from => '보내는 주소';

  @override
  String get to => '받는 주소';

  @override
  String get value => '금액';

  @override
  String get networkFee => '네트워크 수수료';

  @override
  String get chain => '체인';

  @override
  String get approve => '승인';

  @override
  String get reject => '거부';

  @override
  String get transactionApproved => '거래가 서명되었습니다';

  @override
  String get transactionRejected => '거래가 거부되었습니다';

  @override
  String get settingsTitle => '설정';

  @override
  String get appearance => '화면';

  @override
  String get theme => '테마';

  @override
  String get darkMode => '다크 모드';

  @override
  String get lightMode => '라이트 모드';

  @override
  String get themeSystem => '시스템';

  @override
  String get language => '언어';

  @override
  String get security => '보안';

  @override
  String get changePin => 'PIN 변경';

  @override
  String get resetWalletTitle => '지갑 초기화';

  @override
  String get resetWalletConfirm =>
      '정말로 초기화하시겠습니까? 이 기기의 모든 키를 삭제하며 되돌릴 수 없습니다. 지갑은 복구 문구를 다시 가져와야만 복원할 수 있습니다.';

  @override
  String get reset => '초기화';

  @override
  String get bleName => 'BLE 이름';

  @override
  String get bleNameHint => 'BLE 장치 이름 입력';

  @override
  String get about => '정보';

  @override
  String get version => '버전';

  @override
  String get backupSeedTitle => '시드 백업';

  @override
  String get backupSeedWarning =>
      '시드 구문을 절대 공유하지 마세요! 이 단어를 가진 사람은 누구나 자금에 접근할 수 있습니다.';

  @override
  String get copyToClipboard => '클립보드에 복사';

  @override
  String get copiedToClipboard => '클립보드에 복사되었습니다!';

  @override
  String get enigmaTitle => '비밀 문구 지갑';

  @override
  String get enigmaDescription => '기억하기 쉬운 문구와 비밀 키로 결정적 지갑을 생성합니다.';

  @override
  String get enterRiddle => '비밀 문구 입력';

  @override
  String get enterSecretKey => '비밀 키 입력';

  @override
  String get generateWallet => '지갑 생성';

  @override
  String get enigmaMnemonicTitle => '비밀 문구 복구 구문';

  @override
  String get enigmaMnemonicWarning =>
      '이 24개 단어를 저장하세요. 비밀 문구와 비밀 키로 언제든지 다시 생성할 수 있습니다.';

  @override
  String get processing => '처리 중';

  @override
  String get done => '완료';

  @override
  String get error => '오류';

  @override
  String get success => '성공';

  @override
  String get addAccount => '계정 추가';

  @override
  String get startBle => 'BLE 시작';

  @override
  String get stopBroadcast => '브로드캐스트 중지';

  @override
  String get tapActiveChainToStop => '활성 체인을 다시 탭하면 중지됩니다';

  @override
  String get tapChainToStartBroadcast => '체인을 탭하여 브로드캐스트 시작';

  @override
  String get bleLogs => 'BLE 로그';

  @override
  String get signPending => '서명 요청 대기 중';

  @override
  String bleBroadcastAs(String chain) {
    return '$chain 브로드캐스트 시작';
  }

  @override
  String get fingerprint => '지문';

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
  String get deleteAllWalletData => '이 기기에서 모든 지갑 데이터 삭제';

  @override
  String get ledgerCompatible => 'Ledger Nano X 호환';

  @override
  String get forgotPin => 'PIN을 잊으셨나요?';

  @override
  String get unexpectedError => '예기치 않은 오류가 발생했습니다. 다시 시도하세요.';

  @override
  String get generateWithTouch => '터치 엔트로피로 새 시드 구문 생성';

  @override
  String get restoreFromSeed => '시드 구문에서 지갑 복원';

  @override
  String get advancedEnigma => '비밀 문구를 통한 고급 엔트로피 생성';

  @override
  String get tapRandomly => '화면을 무작위로 터치하여 복구 구문을 위한 엔트로피를 수집하세요.';

  @override
  String get retry => '다시 시도';

  @override
  String get correct => '정답!';

  @override
  String get incorrectTryAgain => '오답 — 다시 시도하세요';

  @override
  String get whichWord => '어떤 단어를 기록했나요?';

  @override
  String get enterPinToReveal => '시드 구문을 보려면 PIN을 입력하세요';

  @override
  String get yourSeedPhrase => '내 시드 구문';

  @override
  String get writeDown12Words => '이 12개 단어를 순서대로 적고 안전하게 보관하세요.';

  @override
  String get makeSurePrivate => '확인하기 전에 개인적인 공간에 있는지 확인하세요.';

  @override
  String get walletLockedHint =>
      '지갑이 영구적으로 잠겼습니다. 돌아가서 지갑을 초기화해야 계속 사용할 수 있습니다.';

  @override
  String get yourRiddle => '내 비밀 문구';

  @override
  String get secretKey => '비밀 키';

  @override
  String get mnemonicLanguage => '니모닉 언어';

  @override
  String get enterMemorablePhrase => '기억에 남는 문구, 질문 또는 비밀 문구를 입력하세요...';

  @override
  String get tipLongUnique => '팁: 최대 보안을 위해 길고 고유한 비밀 문구와 비밀 키를 사용하세요.';

  @override
  String get yourEnigmaSeedPhrase => '내 비밀 문구 시드 구문';

  @override
  String get continueToSetPin => 'PIN 설정으로 계속';

  @override
  String get noMnemonicGenerated => '니모닉이 생성되지 않았습니다. 돌아가서 다시 시도하세요.';

  @override
  String get writeDown24Words =>
      '이 24개 단어를 순서대로 적고 안전하게 보관하세요. 이 단어를 가진 사람은 누구나 자금에 접근할 수 있습니다.';

  @override
  String get neverShareSeed => '시드 구문을 절대 공유하지 마세요!';

  @override
  String get passphraseOptional => '암호문 (선택 사항)';

  @override
  String get advancedBip39Passphrase => '고급: BIP39 암호문 추가 (선택 사항)';

  @override
  String get enterPassphraseOptional => '암호문 입력 (선택 사항)';

  @override
  String get bip39PassphraseExplanation =>
      'BIP39 암호문은 완전히 다른 지갑을 생성합니다. 사용하는 경우 반드시 기억해야 합니다 — 복구할 방법이 없습니다.';

  @override
  String get displayLanguage => '표시 언어';

  @override
  String get displayLanguageNote =>
      '표시 언어는 단어의 모양에만 영향을 미치며 지갑 생성 방식에는 영향을 미치지 않습니다.';

  @override
  String get leaveEmptyStandard => '표준 비밀 문구 지갑의 경우 비워 두세요.';

  @override
  String get seedDerivedFromEnglish =>
      '이 시드는 영어 니모닉에서 파생되었습니다. 표시 언어에 관계없이 항상 동일합니다.';

  @override
  String get historyTab => '기록';

  @override
  String get noSigningHistory => '서명 기록 없음';

  @override
  String get transactionSignaturesWillAppear => '거래 서명이 여기에 표시됩니다';

  @override
  String get signed => '서명됨';

  @override
  String get rejectedStatus => '거부됨';

  @override
  String get failedStatus => '실패';

  @override
  String get signingAddress => '서명 주소';

  @override
  String get statusWord => '상태 워드';

  @override
  String get payload => '페이로드';

  @override
  String get justNow => '방금 전';

  @override
  String get noAccountSelected => '선택된 계정 없음';

  @override
  String get publicKey => '공개 키';

  @override
  String get bleAccess => 'BLE 접근';

  @override
  String get enabled => '활성화됨';

  @override
  String get disabled => '비활성화됨';

  @override
  String get blePeripheral => 'BLE 주변기기';

  @override
  String get connected => '연결됨';

  @override
  String get broadcasting => '브로드캐스팅 중';

  @override
  String get advertisingAs => 'Ledger Nano X로 광고 중입니다. 연결을 기다리고 있습니다.';

  @override
  String get startBleBroadcasting => 'BLE 브로드캐스팅을 시작하여 서명 요청을 수락하세요.';

  @override
  String get noBleActivity => '아직 BLE 활동 없음';

  @override
  String get currentApp => '현재 앱';

  @override
  String get currentAppHint =>
      '지갑은 기기를 이 앱으로 인식합니다. Solana 계정을 연결하기 전에 Solana를 선택하세요.';

  @override
  String get dataHex => '데이터 HEX';

  @override
  String get dataSize => '데이터 크기';

  @override
  String get decodedAction => '디코딩된 작업';

  @override
  String get chainEthereum => '이더리움';

  @override
  String get chainEthereumEvm => '이더리움 & EVM 체인';

  @override
  String get chainSolana => 'Solana';

  @override
  String get chainBitcoin => '비트코인';

  @override
  String get chainTron => 'Tron';

  @override
  String get chainSui => 'Sui';

  @override
  String get chainPersonalMessage => 'Ethereum — 개인 메시지';

  @override
  String get chainEip712 => 'Ethereum — EIP-712';

  @override
  String get eip712TypedData => 'EIP-712 타입 데이터';

  @override
  String get domainHash => '도메인 해시';

  @override
  String get structHash => '구조체 해시';

  @override
  String get messageToSign => '서명할 메시지';

  @override
  String get gasLimit => '가스 한도';

  @override
  String get gasPrice => '가스 가격';

  @override
  String get maxFee => '최대 수수료';

  @override
  String get priorityFee => '우선 수수료';

  @override
  String get nonce => '논스';

  @override
  String get chainId => '체인 ID';

  @override
  String showAll(Object bytes) {
    return '모두 표시 ($bytes 바이트)';
  }

  @override
  String get showMore => '더 보기';

  @override
  String get showLess => '접기';

  @override
  String get rawSignature => '원시 서명';

  @override
  String get signatureResult => '서명 결과';

  @override
  String get amount => '금액';

  @override
  String get spender => '지출자';

  @override
  String get methodLabel => '메서드';

  @override
  String get messageLabel => '메시지';

  @override
  String get backupSection => '백업';

  @override
  String get exportPrivateKey => '이 계정의 개인 키 내보내기';

  @override
  String get exportPrivateKeySubtitle => 'QR 내보내기 · 이 기기에만 표시';

  @override
  String get exportEntryHint => '복구 문구와 모든 개인 키: 설정 → 백업 및 내보내기';

  @override
  String get privateKeyExportTitle => '개인 키 내보내기';

  @override
  String get privateKeyWarning =>
      '개인 키는 이 계정의 자산을 완전히 제어할 수 있으며, 복구 문구와 달리 교체할 수 없습니다. 스크린샷이나 촬영을 하지 마세요.';

  @override
  String get encoding => '인코딩';

  @override
  String autoHideHint(int seconds) {
    return '$seconds초 후 자동 숨김 · 나가면 삭제';
  }

  @override
  String get iveBackedUp => '백업했습니다';

  @override
  String get exportSeedTitle => '복구 문구';

  @override
  String get mnemonicQrWarning => '스크린샷, 촬영, 타인에게 보여주기를 하지 마세요.';

  @override
  String get englishBip39Note => '영어 12/24단어 BIP-39 — 모든 지갑에서 가져올 수 있습니다';

  @override
  String get passphraseNotIncluded =>
      '이 지갑은 BIP-39 암호문을 사용합니다. QR에 포함되지 않습니다 — 별도로 기록했는지 확인하세요.';

  @override
  String walletChip(String fingerprint) {
    return '지갑 · $fingerprint';
  }

  @override
  String get backupAndExport => '백업 및 내보내기';

  @override
  String get exportSeedQrRow => '복구 문구 QR';

  @override
  String get exportSeedQrRowSubtitle => '12/24단어 · 모든 계정 복구';

  @override
  String get privateKeysRow => '개인 키';

  @override
  String get privateKeysRowSubtitle => '계정별 · 보통 불필요';

  @override
  String get privateKeysRareNote =>
      '복구 문구만으로 모든 개인 키를 복구할 수 있습니다. 받는 지갑이 복구 문구 가져오기를 지원하지 않을 때만 내보내세요.';

  @override
  String get verifySectionHeader => '검증';

  @override
  String get verifyRowSubtitle => '기록한 백업이 올바른지 확인합니다';

  @override
  String get verifySeedTitle => '복구 문구 검증';

  @override
  String get verifySeedHint =>
      '기록해 둔 백업의 단어를 공백으로 구분해 입력하세요. 입력한 내용은 이 기기를 벗어나지 않습니다.';

  @override
  String get verifyPassphraseTitle => '패스프레이즈 검증';

  @override
  String get verifyPassphraseHint =>
      '이 지갑에 설정한 BIP-39 패스프레이즈를 입력하세요. 설정한 적이 없다면 비워 두세요 — 검사는 이 지갑에 패스프레이즈가 필요 없음을 확인합니다.';

  @override
  String get verifyEnigmaTitle => '암호 문구 검증';

  @override
  String get verifyEnigmaHint => '이 지갑을 만들 때 사용한 수수께끼와 키를 입력하세요.';

  @override
  String get enigmaRiddleLabel => '수수께끼';

  @override
  String get enigmaSecretLabel => '키';

  @override
  String get verifyAction => '검증';

  @override
  String get verifyResultMatch => '일치합니다 — 백업이 올바릅니다.';

  @override
  String get verifyResultMismatch => '일치하지 않습니다. 오타가 없는지 확인하고 다시 시도하세요.';

  @override
  String get verifyResultUnavailable =>
      '지금은 확인할 수 없습니다. 지갑을 잠금 해제하고 이더리움 계정이 있는지 확인하세요.';

  @override
  String get privacyShield => '내용이 숨겨졌습니다';

  @override
  String get disguiseTitle => '앱 위장';

  @override
  String get disguiseStandard => '기본';

  @override
  String get disguiseCalculator => '계산기';

  @override
  String get disguiseConfirmTitle => '앱 위장을 변경할까요?';

  @override
  String disguiseConfirmBody(String name) {
    return '런처 아이콘과 이름이 「$name」(으)로 바뀝니다. 홈 화면에 반영되기까지 몇 초가 걸릴 수 있습니다. 지갑 데이터와 PIN은 영향을 받지 않습니다. 되돌리려면 이 앱을 열어 이 화면으로 다시 오세요.';
  }

  @override
  String get disguiseConfirmButton => '변경';
}
