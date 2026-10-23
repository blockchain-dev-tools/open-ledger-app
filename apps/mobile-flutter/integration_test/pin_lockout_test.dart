// 场景三：PIN 错误 → 5 次锁定 → 重置钱包 → 冷启动仍为 Welcome
//
// 对应 Unlock 屏幕「max 5 attempts → lockout → Reset Wallet」那条安全路径。
// 重点不是「点得动」，而是「锁得住、清得干净」：
// 锁定后必须真的清掉设备上的钱包，而不是只改个界面状态。
//
// 运行：flutter test integration_test/pin_lockout_test.dart -d <device>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(snapshotDeviceState);
  tearDownAll(restoreDeviceState);

  testWidgets('PIN 连错 5 次 → 锁定 → 重置钱包 → 冷启动回 Welcome', (tester) async {
    // ── 1. 先造一个钱包（导入 + 设 PIN）────────────────────────────
    await launchAppFresh(tester);
    await importWalletAndSetPin(tester);

    // ── 2. 冷启动到解锁页 ─────────────────────────────────────────
    await coldStart(tester);
    await waitForKey(tester, kKeyUnlockDigit1);

    // ── 3. 连续输错 5 次 ──────────────────────────────────────────
    // 每次错误后页面有 ~400ms 复位延迟，必须等圆点清空再输下一次，
    // 否则后续点击会被 `_pin.length >= 6` 挡掉。
    for (var attempt = 1; attempt <= 5; attempt++) {
      await enterPin(tester, keyPrefix: 'unlock', pin: kWrongPin);
      await waitForPinCleared(tester);
    }

    // ── 4. 第 5 次之后进入锁定：数字键盘被锁定视图替换 ─────────────
    await waitForKey(tester, 'reset-wallet');
    expect(
      find.byKey(const Key(kKeyUnlockDigit1)),
      findsNothing,
      reason: '锁定后应隐藏数字键盘',
    );

    // ── 5. 锁定态冷启动：进入页面就直接是锁定视图，无需再输 PIN ────
    await coldStart(tester);
    await waitForKey(tester, 'reset-wallet');
    expect(
      find.byKey(const Key(kKeyUnlockDigit1)),
      findsNothing,
      reason: '已锁定冷启动不应先渲染数字键盘',
    );

    // ── 6. 重置要二次确认：取消不销毁，确认才销毁 → Welcome ────────
    await tapKey(tester, 'reset-wallet');
    await tapKey(tester, 'reset-wallet-cancel');
    await waitForKey(tester, 'reset-wallet');

    await tapKey(tester, 'reset-wallet');
    await tapKey(tester, 'reset-wallet-confirm');
    await waitForKey(tester, kKeyWelcomeImport, timeout: kCryptoTimeout);

    // ── 7. 冷启动仍是 Welcome —— 证明钱包是被真清掉，不是只切了界面 ─
    await coldStart(tester);
    expect(
      find.byKey(const Key(kKeyWelcomeImport)),
      findsOneWidget,
      reason: '重置后钱包不存在，冷启动必须回到 Welcome',
    );
    expect(
      find.byKey(const Key(kKeyUnlockDigit1)),
      findsNothing,
      reason: '重置后不应再出现解锁页',
    );
  });
}
