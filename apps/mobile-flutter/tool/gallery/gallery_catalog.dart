import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/sample_accounts.dart';

/// One gallery destination shown in the catalog and the side navigation.
class GalleryItem {
  final String title;
  final String subtitle;
  final IconData icon;

  /// Route path including query string (e.g. `/account/0?chain=eth`).
  final String path;

  /// Navigation payload (e.g. the mock [ChainAccount] for a screen).
  final Object? extra;

  /// Screens keep a back stack (catalog → screen), while foundation pages
  /// replace like tabs.
  final bool pushRoute;

  const GalleryItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.path,
    this.extra,
    this.pushRoute = false,
  });

  /// Query-less path part (`/account/0`).
  String get routePath => path.split('?').first;

  /// Value of the `chain` query parameter, if any.
  String? get chain => Uri.parse(path).queryParameters['chain'];

  /// Value of the `tab` query parameter — distinguishes Main-screen tab
  /// variants sharing the `/screens/main` route.
  String? get tab => Uri.parse(path).queryParameters['tab'];

  void open(BuildContext context) {
    if (pushRoute) {
      context.push(path, extra: extra);
    } else {
      context.go(path);
    }
  }
}

class GalleryGroup {
  final String label;
  final List<GalleryItem> items;

  const GalleryGroup({required this.label, required this.items});
}

const List<GalleryItem> _onboardingItems = [
  GalleryItem(
    title: 'Welcome',
    subtitle: '三入口：创建 / 导入 / 暗语',
    icon: Icons.home_outlined,
    path: '/screens/welcome',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Entropy',
    subtitle: '200 次触摸采集 → 生成助记词',
    icon: Icons.touch_app_outlined,
    path: '/screens/entropy',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Generate Mnemonic',
    subtitle: '12 词网格 + 确认勾选 + passphrase',
    icon: Icons.grid_3x3_outlined,
    path: '/screens/generate-mnemonic',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Verify Mnemonic',
    subtitle: '3/7/11 位置四选一验证',
    icon: Icons.quiz_outlined,
    path: '/screens/verify-mnemonic',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Import Mnemonic',
    subtitle: '自由文本导入 + 实时校验',
    icon: Icons.download_outlined,
    path: '/screens/import',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Secret Phrase',
    subtitle: '暗语 + 密钥 → 确定性钱包',
    icon: Icons.shield_outlined,
    path: '/screens/enigma',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Secret Phrase Mnemonic',
    subtitle: '24 词网格 + 语言切换 + seed hex',
    icon: Icons.key_outlined,
    path: '/screens/enigma-mnemonic',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Set PIN',
    subtitle: '两阶段 6 位 PIN（创建模式）',
    icon: Icons.pin_outlined,
    path: '/screens/set-pin',
    pushRoute: true,
  ),
];

const List<GalleryItem> _authItems = [
  GalleryItem(
    title: 'Unlock',
    subtitle: '冷启动 PIN 门 · 5 次锁定',
    icon: Icons.lock_open_outlined,
    path: '/screens/unlock',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Unlock · locked out',
    subtitle: '已锁定态 · 进入即显示锁定页（唯一重置出口）',
    icon: Icons.lock_outline,
    path: '/screens/unlock?state=locked',
    pushRoute: true,
  ),
];

const List<GalleryItem> _signingItems = [
  GalleryItem(
    title: 'Transaction',
    subtitle: '签名审批 · 倒计时 · 解码合约调用',
    icon: Icons.receipt_long_outlined,
    path: '/screens/transaction',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Address Confirm',
    subtitle: 'GET_PUBLIC_KEY · 展示地址并等待确认（60s 倒计时）',
    icon: Icons.badge_outlined,
    path: '/screens/confirm-address',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Signature Result',
    subtitle: '签名结果 · 可复制原始签名',
    icon: Icons.check_circle_outline,
    path: '/screens/signature-result',
    pushRoute: true,
  ),
];

const List<GalleryItem> _securityItems = [
  GalleryItem(
    title: 'Export Seed QR',
    subtitle: '助记词纯二维码导出 · 指纹 chip + 自动隐藏',
    icon: Icons.qr_code_2_outlined,
    path: '/screens/export-seed',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Export Seed QR · passphrase',
    subtitle: '带 BIP-39 passphrase 的告警态（passphrase 不在码内）',
    icon: Icons.info_outline,
    path: '/screens/export-seed?passphrase=1',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Export Private Key · ETH',
    subtitle: '账户级私钥二维码 · 编码 / 地址元信息',
    icon: Icons.key_outlined,
    path: '/export-private-key?chain=eth',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Backup & Export',
    subtitle: '设置枢纽：助记词二维码 / 私钥列表 / 警示',
    icon: Icons.folder_special_outlined,
    path: '/screens/backup-export',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Backup & Export · passphrase',
    subtitle: '枢纽页带 passphrase 提示态',
    icon: Icons.info_outline,
    path: '/screens/backup-export?passphrase=1',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Private Key List',
    subtitle: '全部账户私钥列表 · 按链编码 · 降级说明',
    icon: Icons.list_alt_outlined,
    path: '/screens/private-keys',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Verify Seed',
    subtitle: '助记词重输验证 · match 判定',
    icon: Icons.spellcheck,
    path: '/screens/verify-seed?result=match',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Verify Seed · mismatch',
    subtitle: '助记词验证失败态',
    icon: Icons.error_outline,
    path: '/screens/verify-seed?result=mismatch',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Verify Passphrase',
    subtitle: 'BIP-39 passphrase 验证 · 双向文案（可能是没设过）',
    icon: Icons.password_outlined,
    path: '/screens/verify-passphrase?result=mismatch',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Verify Enigma',
    subtitle: '暗语谜语 + 密钥验证 · 按落盘语言重导',
    icon: Icons.auto_awesome_outlined,
    path: '/screens/verify-enigma?result=match',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Privacy Shield',
    subtitle: '失焦 / 后台遮罩 · 覆盖秘密屏（ADR-011 §6）',
    icon: Icons.shield_outlined,
    path: '/screens/privacy-shield',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Stand-in · intro',
    subtitle: '马甲钱包未配置：威胁模型说明 + 模式选择（仅切换 / 切换并擦除）',
    icon: Icons.switch_account_outlined,
    path: '/screens/stand-in',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Stand-in · status',
    subtitle: '已配置状态页：改马甲 PIN / 切换模式 / 移除',
    icon: Icons.shield_outlined,
    path: '/screens/stand-in?configured=1',
    pushRoute: true,
  ),
];

/// The Main-screen bottom-nav tabs plus the Vault BLE scenarios (per-chain
/// radio button + log sheet). Each mounts the shared `/screens/main` route
/// so the real AppBar + bottom nav chrome is preserved.
const List<GalleryItem> _tabItems = [
  GalleryItem(
    title: 'Vault · idle',
    subtitle: '钱包账户列表 + 右下悬浮蓝牙按钮（点按选链启动）',
    icon: Icons.account_balance_wallet_outlined,
    path: '/screens/main?bleState=idle',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Vault · broadcasting',
    subtitle: 'Ethereum 广播中：FAB 显示链图标 + 脉冲环',
    icon: Icons.bluetooth_outlined,
    path: '/screens/main?chain=ethereum',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Vault · connected',
    subtitle: '客户端已连接：FAB 实心态 + 对勾角标',
    icon: Icons.bluetooth_connected_outlined,
    path: '/screens/main?chain=ethereum&bleState=connected',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'BLE control sheet',
    subtitle: '悬浮按钮面板：状态 / 热切换链 / 停止',
    icon: Icons.touch_app_outlined,
    path: '/screens/main?blepanel=1',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'BLE logs sheet',
    subtitle: '同一抽屉内的日志视图：APDU 日志（fake 回放）',
    icon: Icons.article_outlined,
    path: '/screens/main?logs=1',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Tab · History',
    subtitle: '签名历史（通过 / 拒绝 / 失败）',
    icon: Icons.history_outlined,
    path: '/screens/main?tab=1',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Tab · Settings',
    subtitle: '外观 / 安全 / BLE / 关于',
    icon: Icons.settings_outlined,
    path: '/screens/main?tab=2',
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Tab · Settings · stand-in session',
    subtitle: '隐匿会话下的设置页：马甲行可点且显示「未开启」',
    icon: Icons.switch_account_outlined,
    path: '/screens/main?tab=2&standin=1',
    pushRoute: true,
  ),
];

const List<GalleryItem> _accountItems = [
  GalleryItem(
    title: 'Account Detail · Ethereum',
    subtitle: '身份头 / Details 卡 / 地址卡（QR + 复制）',
    icon: Icons.currency_bitcoin_outlined,
    path: '/account/0?chain=eth',
    extra: ethAccount,
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Account Detail · Solana',
    subtitle: 'base58 长地址 · Ed25519 公钥',
    icon: Icons.bubble_chart_outlined,
    path: '/account/0?chain=sol',
    extra: solAccount,
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Account Detail · Solana #1',
    subtitle: '第二个 Solana 账户 · 序号取路径第 4 段（索引 1，非列表位）',
    icon: Icons.bubble_chart_outlined,
    path: '/account/1?chain=sol1',
    extra: solAccount2,
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Account Detail · Bitcoin',
    subtitle: 'bech32 地址 · m/84 native segwit',
    icon: Icons.token_outlined,
    path: '/account/0?chain=btc',
    extra: btcAccount,
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Account Detail · Tron',
    subtitle: 'Base58Check T 开头地址',
    icon: Icons.change_history_outlined,
    path: '/account/0?chain=tron',
    extra: tronAccount,
    pushRoute: true,
  ),
  GalleryItem(
    title: 'Account Detail · Sui',
    subtitle: '0x 长地址 · Ed25519 公钥',
    icon: Icons.water_drop_outlined,
    path: '/account/0?chain=sui',
    extra: suiAccount,
    pushRoute: true,
  ),
];

/// Catalog sections rendered in order.
const List<GalleryGroup> galleryGroups = [
  GalleryGroup(
    label: 'Foundations',
    items: [
      GalleryItem(
        title: 'Design Tokens · Dark',
        subtitle: '暗色主题 ColorTokens 与圆角 R',
        icon: Icons.palette_outlined,
        path: '/tokens/dark',
      ),
      GalleryItem(
        title: 'Design Tokens · Light',
        subtitle: '亮色主题 ColorTokens 与圆角 R',
        icon: Icons.palette_outlined,
        path: '/tokens/light',
      ),
    ],
  ),
  GalleryGroup(
    label: 'Components',
    items: [
      GalleryItem(
        title: 'Common Components',
        subtitle: '按钮 / 分区标题 / 复制 / PIN / 链图标 / 警示条',
        icon: Icons.widgets_outlined,
        path: '/components',
      ),
    ],
  ),
  GalleryGroup(label: 'Onboarding', items: _onboardingItems),
  GalleryGroup(label: 'Auth', items: _authItems),
  GalleryGroup(label: 'Main tabs', items: _tabItems),
  GalleryGroup(label: 'Account detail', items: _accountItems),
  GalleryGroup(label: 'Signing', items: _signingItems),
  GalleryGroup(label: 'Security', items: _securityItems),
];
