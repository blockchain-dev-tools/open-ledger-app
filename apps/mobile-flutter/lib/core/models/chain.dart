/// Chain identity — the single source of truth for everything that differs
/// between wallet chains: icon, default derivation path, and the Ledger app
/// the chain is exposed as over BLE.
///
/// Previously these facts were duplicated across six places (label/icon
/// maps in `utils/formatting.dart`, app↔chain maps in the BLE control
/// adapter, the name/version switch in `ApduHandler`, the chain order in the
/// control sheet, and the default derivation paths in BOTH
/// `services/account_service.dart` and `ui/screens/accounts/accounts_tab.dart`).
/// Adding or renaming a chain meant editing all of them; the derivation-path
/// pair could drift silently. Everything now derives from here.
///
/// Pure Dart on purpose — `core/` must not depend on Flutter, and display
/// strings live in l10n (see `AppLocalizations.chainLabel`).
library;

/// A wallet chain Open Ledger App supports.
enum Chain {
  ethereum,
  solana,
  bitcoin,
  tron,
  sui;

  /// Chains offered by account, BLE-picker and private-key export UI.
  /// BTC and Sui are temporarily hidden pending validation. Restore them
  /// here after testing; keep [values] intact for storage and protocols.
  static const visible = [ethereum, solana, tron];

  /// Persisted identifier, used in [WalletAccounts] metadata, signing
  /// history, and the BLE control UI. Also the enum name, so
  /// `Chain.values.map((c) => c.id)` stays stable for storage.
  String get id => name;

  /// Branded SVG icon under `assets/icons/chains/`.
  String get iconAssetPath => switch (this) {
        Chain.ethereum => 'assets/icons/chains/eth.svg',
        Chain.solana => 'assets/icons/chains/sol.svg',
        Chain.bitcoin => 'assets/icons/chains/btc.svg',
        Chain.tron => 'assets/icons/chains/tron.svg',
        Chain.sui => 'assets/icons/chains/sui.svg',
      };

  /// Account 0's BIP-32 path — auto-derived on wallet setup and unlock.
  String get defaultAccountPath => switch (this) {
        Chain.ethereum => "m/44'/60'/0'/0/0",
        Chain.solana => "m/44'/501'/0'/0'",
        Chain.bitcoin => "m/84'/0'/0'/0/0",
        Chain.tron => "m/44'/195'/0'/0/0",
        Chain.sui => "m/44'/784'/0'/0'/0'",
      };

  /// Whether the account number sits in the 4th path segment rather than the
  /// last one.
  ///
  /// Solana and Sui harden the account segment and keep the trailing address
  /// index at 0 (`m/44'/501'/{account}'/0'`); EVM and Tron vary the final
  /// address index instead (`m/44'/60'/0'/0/{account}`). Reading "the last
  /// segment" therefore reports 0 for every Solana/Sui account.
  bool get _accountInFourthSegment => this == solana || this == sui;

  /// The derivation path for account [index] on this chain — the inverse of
  /// [accountIndexFromPath].
  String accountPathForIndex(int index) {
    final parts = defaultAccountPath.split('/');
    if (_accountInFourthSegment) {
      parts[3] = "$index'";
    } else {
      parts[parts.length - 1] = '$index';
    }
    return parts.join('/');
  }

  /// The account number encoded in a derivation [path] on this chain.
  ///
  /// Reads the segment that varies per account, not a list position: a list of
  /// `[eth#0, eth#1, sol#0]` labels its rows 0/1/0, and Solana's second
  /// account (`m/44'/501'/1'/0'`) reads 1, not 0.
  int accountIndexFromPath(String path) {
    final parts = path.split('/');
    final pos = _accountInFourthSegment ? 3 : parts.length - 1;
    if (pos < 0 || pos >= parts.length) return 0;
    return int.tryParse(parts[pos].replaceAll("'", '')) ?? 0;
  }

  /// The Ledger app this chain is exposed as over BLE.
  LedgerApp get ledgerApp => switch (this) {
        Chain.ethereum => LedgerApp.ethereum,
        Chain.solana => LedgerApp.solana,
        Chain.bitcoin => LedgerApp.bitcoin,
        Chain.tron => LedgerApp.tron,
        Chain.sui => LedgerApp.sui,
      };

  /// Resolve a persisted chain id, or `null` for pseudo-chains
  /// (`'personal_msg'`, `'eip712'`) and unknown values.
  static Chain? fromId(String? id) {
    if (id == null) return null;
    for (final chain in values) {
      if (chain.id == id) return chain;
    }
    return null;
  }
}

/// A Ledger "app" as seen by a host wallet through `GET_APP_AND_VERSION`
/// and selected with `OPEN_APP`.
///
/// The name and version are what the host reads off the wire, so they must
/// match the real Ledger app the chain is emulated as.
enum LedgerApp {
  ethereum(ledgerName: 'Ethereum', version: '1.10.3'),
  solana(ledgerName: 'Solana', version: '1.7.0'),
  bitcoin(ledgerName: 'Bitcoin', version: '2.1.0'),
  tron(ledgerName: 'Tron', version: '0.5.0'),
  sui(ledgerName: 'Sui', version: '0.1.0');

  const LedgerApp({required this.ledgerName, required this.version});

  /// Name reported to the host (`GET_APP_AND_VERSION`) and matched against
  /// an `OPEN_APP` payload.
  final String ledgerName;

  /// Version reported to the host alongside [ledgerName].
  final String version;

  /// The chain this app serves. One app per chain today; when a single app
  /// serves several chains this becomes a list and only this mapping moves.
  Chain get chain => Chain.values.byName(name);

  /// Name reported while no app is open (the BOLOS dashboard).
  ///
  /// A real device on the dashboard answers `GET_APP_AND_VERSION` with
  /// format `0x00` and this name; Ledger's own client
  /// (`getAppAndVersion.ts`) rejects any format other than `0x01`, which is
  /// exactly how wallets learn they must ask the user to open an app.
  static const String dashboardName = 'BOLOS';

  /// Parse an `OPEN_APP` app name, or `null` if it names no known app.
  ///
  /// Hosts send the exact app name ("Bitcoin", "Ethereum", …); the
  /// containment fallback tolerates the shortened variants some wallets use.
  static LedgerApp? fromLedgerName(String raw) {
    final name = raw.toLowerCase().trim();
    if (name.isEmpty) return null;
    for (final app in values) {
      if (name == app.ledgerName.toLowerCase()) return app;
    }
    for (final app in values) {
      if (name.contains(app.ledgerName.toLowerCase())) return app;
    }
    return null;
  }
}
