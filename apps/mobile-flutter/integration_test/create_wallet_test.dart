// 场景二：创建钱包（熵收集 → 助记词展示 → 抄写确认 → 校验问答 → 设 PIN → 金库）
//
// 这是链路最长的一条：200 次触点采集熵、派生助记词、再回答 3 道抽词题。
//
// 两个白盒亮点（外部 UI 驱动做不到）：
// 1. 直接从 GenerateMnemonicScreen 的 widget 字段读出「App 刚生成的那串助记词」，
//    所以测验答案可以精确计算，而不是猜；
// 2. 用 App 自己的本地化表反推「当前问的是第几个词」，不依赖界面语言。
//
// 运行：flutter test integration_test/create_wallet_test.dart -d <device>

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:open_ledger_app/ui/screens/entropy/entropy_screen.dart';
import 'package:open_ledger_app/ui/screens/generate_mnemonic/generate_mnemonic_screen.dart';
import 'package:open_ledger_app/ui/screens/verify_mnemonic/verify_mnemonic_screen.dart';
import 'package:open_ledger_app/ui/widgets/common/primary_button.dart';

import 'helpers/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(snapshotPrefs);
  tearDownAll(restorePrefs);

  testWidgets('创建钱包 → 熵 → 助记词 → 校验问答 → 设 PIN → 金库', (tester) async {
    await launchAppFresh(tester);

    // ── 1. Welcome → 熵收集页 ─────────────────────────────────────
    await tapKey(tester, 'entry-create');
    await waitFor(tester, find.byType(EntropyScreen), reason: '熵收集页');

    // ── 2. 连点 200 次（页面要求 200 个触点才够熵）────────────────
    // 触点区域是铺满 body 的 opaque GestureDetector，点屏幕中心即可。
    await tapRepeatedly(
      tester,
      tester.getCenter(find.byType(EntropyScreen)),
      200,
    );

    // ── 3. 助记词展示页：直接把 App 生成的那串读出来（白盒）──────
    await waitFor(
      tester,
      find.byType(GenerateMnemonicScreen),
      timeout: kCryptoTimeout,
      reason: '助记词展示页',
    );
    final generated = tester
        .widget<GenerateMnemonicScreen>(find.byType(GenerateMnemonicScreen))
        .mnemonic;
    expect(generated.split(' ').length, 12, reason: '应生成 12 个 BIP-39 单词');

    // ── 4. 勾选「我已抄下」→ 继续（未勾选时按钮是禁用的）──────────
    await tester.tap(find.text(l10n(tester, (l) => l.iveWrittenItDown)));
    await tester.pump();
    await tapHittable(tester, find.byType(PrimaryButton));

    // ── 5. 校验问答：认出问第几个词，再点对应的那个词 ─────────────
    await waitFor(tester, find.byType(VerifyMnemonicScreen), reason: '校验问答页');
    final words = generated.split(' ');
    for (var i = 0; i < kQuizPositions.length; i++) {
      final position = await waitForQuizPosition(tester);
      await tester.tap(find.text(words[position - 1]).first);
      await tester.pump();
    }

    // ── 6. 三题全对 → 设 PIN（两遍）→ 金库 ────────────────────────
    await waitForKey(tester, 'pin-btn-1');
    await enterPin(tester, keyPrefix: 'pin', pin: kTestPin);
    await enterPin(tester, keyPrefix: 'pin', pin: kTestPin);

    await waitForKey(tester, kKeyChainHeaderEth, timeout: kCryptoTimeout);
    expect(
      find.textContaining('Wallet: '),
      findsOneWidget,
      reason: '创建完成后金库应显示指纹',
    );

    // ── 7. 冷启动应落在 Unlock，且用这个 PIN 能解开 ────────────────
    await coldStart(tester);
    await waitForKey(tester, kKeyUnlockDigit1);
    await enterPin(tester, keyPrefix: 'unlock', pin: kTestPin);
    await waitForKey(tester, kKeyChainHeaderEth, timeout: kCryptoTimeout);
  });
}
