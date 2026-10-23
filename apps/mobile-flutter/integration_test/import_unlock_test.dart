// 场景一：导入助记词 → 设置 PIN → 冷启动解锁 → 进入金库
//
// 最短也最核心的一条 happy path：新装用户导入已有助记词、设 PIN，
// 之后每次冷启动都要能解锁进金库。
//
// 运行：flutter test integration_test/import_unlock_test.dart -d <device>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 跑前把设备的持久化快照存下来，跑完原样还原（不破坏已有钱包）。
  setUpAll(snapshotDeviceState);
  tearDownAll(restoreDeviceState);

  testWidgets('导入助记词 → 设 PIN → 冷启动解锁 → 进金库', (tester) async {
    // ── 1. 全新安装态：首屏是 Welcome ──────────────────────────────
    await launchAppFresh(tester);

    // ── 2. 导入助记词 + 两遍 PIN，直到金库（含指纹断言）────────────
    await importWalletAndSetPin(tester);

    // ── 3. 模拟冷启动：应落在 Unlock 而不是 Welcome ────────────────
    await coldStart(tester);
    expect(
      find.byKey(const Key(kKeyWelcomeImport)),
      findsNothing,
      reason: '已存在钱包，冷启动不应回到 Welcome',
    );
    await waitForKey(tester, kKeyUnlockDigit1);

    // ── 4. 用刚才的 PIN 解锁 → 再次进金库 ─────────────────────────
    await enterPin(tester, keyPrefix: 'unlock', pin: kTestPin);
    await waitForKey(tester, kKeyChainHeaderEth, timeout: kCryptoTimeout);
    expect(
      find.textContaining('Wallet: '),
      findsOneWidget,
      reason: '解锁后账号应重新派生出来',
    );
  });
}
