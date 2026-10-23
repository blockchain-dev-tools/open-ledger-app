// 真机端到端测试的共享脚手架。
//
// 设计要点：
// 1. 测试与 App 跑在同一个进程里，直接读内存中的 widget 树（find.byKey），
//    不截图、不依赖系统无障碍树 —— 因此定位精确、零渲染成本，还能读内部状态。
// 2. 持久化是真实的：钱包走 Keystore/Keychain 支撑的安全存储，设置走
//    SharedPreferences（与 App 同一 applicationId）。所以本脚手架默认
//    「先快照、结束还原」，不会弄丢设备上已有的钱包。
// 3. 一律用 Key / 类型 / BIP-39 单词定位，尽量不用文案；必须用文案时，
//    通过 [l10n] 从 App 自己的本地化表里取，因此 en/zh/ja/ko 都能跑。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/infrastructure/persistence/secure_storage.dart';
import 'package:open_ledger_app/main.dart' as app;
import 'package:open_ledger_app/ui/widgets/common/primary_button.dart';
import 'package:open_ledger_app/ui/widgets/pin/pin_dot_indicator.dart';

/// 标准 BIP-39 测试助记词（全零熵 → abandon ×11 + about）。
const String kTestMnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

/// 测试用 PIN。与设备上任何真实 PIN 无关，测试开始会清库。
const String kTestPin = '246813';

/// 一个必然错误的 PIN，用于锁定流程。
const String kWrongPin = '111111';

/// 冷启动首屏可能出现的 Key。
const String kKeyWelcomeImport = 'entry-import';
const String kKeyUnlockDigit1 = 'unlock-btn-1';

/// 金库页的 eth 分组头（Chain.ethereum.id == 'ethereum'）。
const String kKeyChainHeaderEth = 'chain-header-ethereum';

/// 助记词校验问答问的是第几个词（源码 `_quizPositions`）。
const List<int> kQuizPositions = [3, 7, 11];

// ── 超时 ───────────────────────────────────────────────────────────────

/// App 启动（读设置 → 建依赖 → 查钱包 → 建路由）。
const Duration kBootTimeout = Duration(seconds: 30);

/// 涉及加密/派生的步骤（Argon2id m=64MiB,t=3,p=4、助记词→种子→5 链派生）会明显更慢。
const Duration kCryptoTimeout = Duration(seconds: 90);

// ══════════════════════════════════════════════════════════════════════
//  持久化：非破坏式隔离
// ══════════════════════════════════════════════════════════════════════

Map<String, Object?> _prefsSnapshot = const {};
Map<String, String> _secureSnapshot = const {};

/// 记录设备当前的持久化状态：设置（SharedPreferences）+ 钱包（安全存储）。
/// 测试文件在 `setUpAll` 里调用。
///
/// 有了它，测试即使把库清空跑完，`tearDownAll` 也能把设备还原成跑之前的样子。
/// 两者都要快照 —— 钱包已迁到 Keystore/Keychain 支撑的存储（ADR-007），
/// 只快照 prefs 会在还原时弄丢设备上已有的钱包。
Future<void> snapshotDeviceState() async {
  final prefs = await SharedPreferences.getInstance();
  _prefsSnapshot = {for (final key in prefs.getKeys()) key: prefs.get(key)};
  _secureSnapshot = await SecureStorage().readAll();
}

/// 还原 `snapshotDeviceState()` 记录的状态。测试文件在 `tearDownAll` 里调用。
Future<void> restoreDeviceState() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  for (final entry in _prefsSnapshot.entries) {
    final value = entry.value;
    if (value is String) {
      await prefs.setString(entry.key, value);
    } else if (value is bool) {
      await prefs.setBool(entry.key, value);
    } else if (value is int) {
      await prefs.setInt(entry.key, value);
    } else if (value is double) {
      await prefs.setDouble(entry.key, value);
    } else if (value is List<String>) {
      await prefs.setStringList(entry.key, value);
    }
  }

  final secure = SecureStorage();
  await secure.deleteAll();
  for (final entry in _secureSnapshot.entries) {
    await secure.setItem(entry.key, entry.value);
  }
}

// ══════════════════════════════════════════════════════════════════════
//  本地化
// ══════════════════════════════════════════════════════════════════════

/// 取 App **当前语言**下的文案。
///
/// 直接用 `l10n((l) => l.continueButton)` 定位，就不会把测试写死成英文 ——
/// 设备切到中文/日文/韩文也照样能跑。
///
/// 定位要点：`AppLocalizations` 由 MaterialApp 内部的 `Localizations` 提供，
/// 而 `Localizations` 是 `MaterialApp` 的**后代**（不是祖先）—— 必须从位于它
/// 下方的 element（Navigator / Scaffold）往上查；查 MaterialApp 自身只会拿到
/// null。
String l10n(WidgetTester tester, String Function(AppLocalizations l) pick) {
  for (final el in find.byType(Navigator).evaluate()) {
    final l = Localizations.of<AppLocalizations>(el, AppLocalizations);
    if (l != null) return pick(l);
  }
  for (final el in find.byType(Scaffold).evaluate()) {
    final l = Localizations.of<AppLocalizations>(el, AppLocalizations);
    if (l != null) return pick(l);
  }
  throw StateError(
    '找不到 AppLocalizations：App 未挂载，或 MaterialApp 的 localizationsDelegates '
    '里缺 AppLocalizations.delegate',
  );
}

// ══════════════════════════════════════════════════════════════════════
//  等待
// ══════════════════════════════════════════════════════════════════════

/// 反复 pump 直到 [finder] 命中；超时即失败（不静默继续）。
///
/// 不用 `pumpAndSettle`：真机上有常驻动画/定时器时会永不 settle，
/// 而这里只关心「某个 widget 是否出现」，轮询更可控。
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = kBootTimeout,
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(
    '等待超时（${timeout.inSeconds}s）：'
    '${reason ?? finder.describeMatch(Plurality.many)}',
  );
}

/// 等待任意一个 [finders] 命中；超时即失败。
Future<void> waitForAny(
  WidgetTester tester,
  List<Finder> finders, {
  Duration timeout = kBootTimeout,
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final finder in finders) {
      if (finder.evaluate().isNotEmpty) return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('等待超时（${timeout.inSeconds}s）：$reason');
}

/// 等待 [key] 对应 widget 出现。
Future<void> waitForKey(
  WidgetTester tester,
  String key, {
  Duration timeout = kBootTimeout,
}) => waitFor(
  tester,
  find.byKey(Key(key)),
  timeout: timeout,
  reason: 'Key("$key")',
);

/// 等待 [key] 对应 widget 消失（用于确认已离开某个页面）。
Future<void> waitKeyGone(
  WidgetTester tester,
  String key, {
  Duration timeout = kBootTimeout,
}) async {
  final finder = find.byKey(Key(key));
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('等待 Key("$key") 消失超时（${timeout.inSeconds}s）');
}

// ══════════════════════════════════════════════════════════════════════
//  交互
// ══════════════════════════════════════════════════════════════════════

/// 等待 [key] 出现后点击它。
Future<void> tapKey(WidgetTester tester, String key) async {
  await waitForKey(tester, key);
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

/// 等待 [finder] 变为「可命中」后点击它。
///
/// 用于键盘/动画导致元素暂时被遮挡、不接受指针事件的场景。
Future<void> tapHittable(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = kBootTimeout,
}) async {
  await waitFor(
    tester,
    finder.hitTestable(),
    timeout: timeout,
    reason: '可命中的 ${finder.describeMatch(Plurality.one)}',
  );
  await tester.tap(finder.first);
  await tester.pump();
}

/// 在同一个坐标上连点 [count] 次（熵收集页需要 200 个触点）。
Future<void> tapRepeatedly(WidgetTester tester, Offset at, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.tapAt(at);
  }
  await tester.pump();
}

/// 通过数字键盘依次输入 [pin] 的每一位。
///
/// [keyPrefix] 与 `PinNumberPad.keyPrefix` 一致：`'pin'`（设置页）或
/// `'unlock'`（解锁页）。注意第 6 位输入后页面会自行触发校验，
/// 调用方需自行等待后续状态（见 [waitForPinCleared]）。
Future<void> enterPin(
  WidgetTester tester, {
  required String keyPrefix,
  required String pin,
}) async {
  for (final digit in pin.split('')) {
    await tapKey(tester, '$keyPrefix-btn-$digit');
  }
}

/// 读取 PIN 圆点当前填充数。
///
/// 直接读 widget 的内部字段 —— 这是「白盒」能力，外部驱动读不到。
int pinDotFilled(WidgetTester tester) {
  final finder = find.byType(PinDotIndicator);
  if (finder.evaluate().isEmpty) return -1;
  return tester.widget<PinDotIndicator>(finder.first).filledCount;
}

/// 等待 PIN 输入被清空。
///
/// 校验失败后页面有 ~400ms 的复位延迟（清空圆点 + 停止抖动），
/// 在这之前再点数字会被忽略。锁定视图出现时也算「已复位」。
Future<void> waitForPinCleared(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (find.byType(PinDotIndicator).evaluate().isEmpty) return;
    if (pinDotFilled(tester) == 0) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('等待 PIN 输入清空超时（${timeout.inSeconds}s）');
}

/// 收起软键盘，并等待视口高度恢复。
///
/// 真机上键盘一弹出，body 高度只剩 ~430px：导入页的 Column 会溢出 133px，
/// 把 Import 按钮挤出可视区，`tap` 会报 "would not hit test"。
/// 收起键盘既是真实用户会做的动作，也让该页布局恢复。
Future<void> dismissKeyboard(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  FocusManager.instance.primaryFocus?.unfocus();

  // 平台键盘收起是异步的：轮询 MediaQuery.viewInsets 直到归零。
  final appFinder = find.byType(MaterialApp);
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (appFinder.evaluate().isEmpty) return;
    final insets = MediaQuery.viewInsetsOf(appFinder.evaluate().first).bottom;
    if (insets == 0) return;
  }
}

// ══════════════════════════════════════════════════════════════════════
//  启动
// ══════════════════════════════════════════════════════════════════════

/// 模拟「杀进程重开」：拆掉当前 widget 树，再 pump 一个全新的 App 实例。
///
/// 新实例会重新读持久化，所以能真实验证「冷启动态」——这是外部 UI 驱动
/// 做不到的（它只能重启 Activity，拿不到我们关心的初始路由决策）。
Future<void> coldStart(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  await tester.pumpWidget(const app.OpenLedgerAppApp());
  await waitForAny(
    tester,
    [
      find.byKey(const Key(kKeyWelcomeImport)),
      find.byKey(const Key(kKeyUnlockDigit1)),
      // A wallet that was locked out before the restart goes straight to the
      // lockout view — the pad is never rendered.
      find.byKey(const Key('reset-wallet')),
    ],
    timeout: kBootTimeout,
    reason: 'App 首屏（Welcome / Unlock / 锁定页）',
  );
}

/// 清空持久化后冷启动 —— 等价于「全新安装首次打开」。
///
/// 设置与钱包都要清：钱包在安全存储里，只清 prefs 会留下旧钱包，
/// App 会直接进解锁页而不是 Welcome。
/// 返回时 App 已停在 Welcome。
Future<void> launchAppFresh(WidgetTester tester) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await SecureStorage().deleteAll();

  await coldStart(tester);
  expect(
    find.byKey(const Key(kKeyWelcomeImport)),
    findsOneWidget,
    reason: '清库后首屏应为 Welcome',
  );
}

// ══════════════════════════════════════════════════════════════════════
//  组合流程（多个场景共用）
// ══════════════════════════════════════════════════════════════════════

/// 走完「导入助记词 → 设 PIN」，返回时已停在金库。
///
/// 前置条件：App 处于 Welcome（用 [launchAppFresh] 保证）。
Future<void> importWalletAndSetPin(
  WidgetTester tester, {
  String pin = kTestPin,
  String mnemonic = kTestMnemonic,
}) async {
  await tapKey(tester, kKeyWelcomeImport);
  await waitForKey(tester, 'mnemonic-input');

  // 真实走 onChanged → Rust validateMnemonic
  await tester.enterText(find.byKey(const Key('mnemonic-input')), mnemonic);
  await tester.pump(const Duration(milliseconds: 300));

  // 校验通过才显示绿勾 —— 顺带证明 Rust 校验在测试包里可用
  expect(
    find.byIcon(Icons.check_circle),
    findsOneWidget,
    reason: '助记词应通过 Rust 校验并显示绿勾',
  );

  // 不收起键盘的话，页面溢出 133px，Import 按钮点不到
  await dismissKeyboard(tester);

  expect(find.byType(PrimaryButton), findsOneWidget);
  await tapHittable(tester, find.byType(PrimaryButton));

  // 两遍 6 位 PIN → setupWallet（Argon2id 64MiB，慢）
  await waitForKey(tester, 'pin-btn-1');
  await enterPin(tester, keyPrefix: 'pin', pin: pin);
  await enterPin(tester, keyPrefix: 'pin', pin: pin);

  await waitForKey(tester, kKeyChainHeaderEth, timeout: kCryptoTimeout);
  expect(
    find.textContaining('Wallet: '),
    findsOneWidget,
    reason: '金库应显示助记词指纹，证明账号真的派生出来了',
  );
}

/// 读出助记词校验页当前问的是第几个词。
///
/// 不碰私有状态：用本地化文案反推，因此任意语言都成立。
Future<int> waitForQuizPosition(WidgetTester tester) async {
  final deadline = DateTime.now().add(kBootTimeout);
  while (DateTime.now().isBefore(deadline)) {
    final shown = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .toSet();
    for (final position in kQuizPositions) {
      if (shown.contains(l10n(tester, (l) => l.verifyWordPosition(position)))) {
        return position;
      }
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('没能识别校验页当前问的是第几个词');
}
