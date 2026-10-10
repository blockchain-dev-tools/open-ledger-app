/// APDU command dispatcher — routes commands by CLA byte to chain handlers.
///
/// Ported from open-ledger-mono: `packages/apdu/src/handler.ts`
///
/// Each chain handler derives keys and signs transactions using the
/// [ICryptoService] abstraction (implemented by the Rust FFI adapter at
/// runtime). Handlers require wallet context (pre-computed seed hex) to be
/// set via [setContext] before any signing or address-derivation operations.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/interfaces/crypto_service.dart';
import '../core/models/apdu_message.dart';
import '../core/models/chain.dart';
import '../protocols/apdu/apdu_constants.dart';
import 'path_parser.dart';

/// Dispatches APDU commands to the appropriate chain handler.
///
/// Usage:
/// ```dart
/// final handler = ApduHandler(crypto: CryptoServiceAdapter());
/// handler.setContext(seedHex: '...');
/// final response = handler.handle(command);
/// handler.clearContext();
/// ```
class ApduHandler {
  final ICryptoService _crypto;

  ApduHandler({required this._crypto});

  // ── Wallet context ──────────────────────────────────────────────────

  /// Pre-computed seed hex (from BIP-39 or wallet's seed function).
  /// When set, this takes priority over mnemonic+passphrase for key derivation.
  String? _seedHex;

  /// Whether the context has been set (seed is available).
  bool get hasContext => _seedHex != null;

  // ── Ledger app state (CLA 0xE0 routing table selection) ─────────────

  /// App currently opened via BOLOS OPEN_APP (INS 0xD8), or `null` while the
  /// device sits on the dashboard.
  ///
  /// CLA 0xE0 is shared by the OS, the Ethereum app and the Solana app,
  /// and their INS tables OVERLAP (0x04 = ETH_SIGN in the Ethereum app but
  /// GET_VERSION in the Solana app; 0x06 = GET_APP_CONFIGURATION in Ethereum
  /// but SIGN in Solana; 0x0A = PROVIDE_ERC20 in Ethereum and never existed
  /// in Solana). The only correct way to disambiguate is the app the host
  /// explicitly opened — same as a real Ledger device.
  ///
  /// `null` (dashboard) is faithful to a real device: nothing is open, so
  /// no CLA-0xE0 INS table is loaded and those commands are refused.
  /// Bitcoin (`0xE1`/`0xF8`) and Sui (`0x07`) carry their own CLA and never
  /// depend on this — their CLA already identifies them. Tron shares `0xE0`
  /// with Ethereum/Solana and IS selected here, like a real device where only
  /// one app runs at a time; a legacy `0x14` alias is routed directly.
  LedgerApp? _currentApp;

  /// The currently open Ledger app, or `null` on the dashboard.
  LedgerApp? get currentApp => _currentApp;

  /// Set the exposed app from the device UI, simulating the physical
  /// "open app" action a user performs on a real Ledger before connecting
  /// a wallet. `null` returns to the dashboard.
  ///
  /// Wallets read the current app via GET_APP_AND_VERSION (CLA 0xB0 INS
  /// 0x01) and refuse to proceed — e.g. a Solana account stays "app not
  /// open" — until that response names the app they need.
  void setCurrentApp(LedgerApp? app) => _activateApp(app);

  /// Switch the active INS table.
  void _activateApp(LedgerApp? app) {
    _currentApp = app;
  }

  /// Set the wallet context required for key derivation and signing.
  ///
  /// [seedHex] must be pre-computed by the caller (e.g. [WalletService.seedHex])
  /// to ensure consistency between BLE and Vault-screen addresses.
  ///
  /// Must be called before any chain handler that needs crypto (ETH sign,
  /// SOL pubkey, BTC address, etc.).
  void setContext({required String seedHex}) {
    _seedHex = seedHex;
  }

  /// Clear the cached context.
  void clearContext() {
    _seedHex = null;
  }

  // ── Main dispatch ───────────────────────────────────────────────────

  /// Route an APDU command to the correct handler based on CLA byte.
  ///
  /// Returns an [ApduResponse] with the result or an error status word.
  ApduResponse handle(ApduCommand command) {
    switch (command.cla) {
      case Cla.os:
      case Cla.global:
        return _handleOs(command);
      case Cla.bitcoin:
      case Cla.bitcoinExt:
        return _handleBitcoin(command);
      case Cla.tron:
        return _handleTron(command);
      case Cla.sui:
        return _handleSui(command);
      default:
        return _errorResponse(Sw.claNotSupported);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // OS / Global handler (CLA 0xe0 / 0xb0)
  // ─────────────────────────────────────────────────────────────────

  ApduResponse _handleOs(ApduCommand command) {
    // B0 A7 — sent by newer Ledger SDKs after getAppAndVersion.
    // Unknown purpose; returning 9000 lets the SDK proceed.
    if (command.cla == Cla.global && command.ins == 0xa7) {
      return ApduResponse(data: null, sw1: 0x90, sw2: 0x00);
    }

    // B0 01 — GET_APP_AND_VERSION (BOLOS dashboard level).
    if (command.cla == Cla.global && command.ins == Ins.getVersion) {
      return _buildGetAppAndVersion();
    }

    // B0 02 — legacy GET_APP_NAME probe; respond with the device name.
    if (command.cla == Cla.global && command.ins == Ins.getAppName) {
      final nameBytes = Uint8List.fromList('OpenLedger'.codeUnits);
      return ApduResponse(data: nameBytes, sw1: 0x90, sw2: 0x00);
    }

    // E0 D8 — OPEN_APP. Client selects which app to use; data is the app
    // name in ASCII. This drives the CLA-0xE0 INS routing table.
    if (command.cla == Cla.os && command.ins == Ins.openApp) {
      _setCurrentApp(command.data);
      return ApduResponse(data: null, sw1: 0x90, sw2: 0x00);
    }

    // E0 A7 — QUIT_APP. Back to the dashboard: no app table is loaded and
    // any half-finished EIP-712 domain cache is dropped.
    if (command.cla == Cla.os && command.ins == Ins.quitApp) {
      _activateApp(null);
      return ApduResponse(data: null, sw1: 0x90, sw2: 0x00);
    }

    // CLA 0xE0's INS table belongs to the app the host opened. On the
    // dashboard nothing is open, so there is no table to dispatch through —
    // a real device answers INS_NOT_SUPPORTED.
    final app = _currentApp;
    if (app == null) {
      return _errorResponse(Sw.insNotSupported);
    }
    return switch (app) {
      // The Solana and Tron apps reuse CLA 0xE0 with their own INS tables.
      LedgerApp.solana => _handleSolanaApp(command),
      LedgerApp.tron => _handleTronApp(command),
      // The Ethereum app owns the default CLA-0xE0 table.
      LedgerApp.ethereum => _handleEthereumApp(command),
      // Bitcoin (0xE1/0xF8) and Sui (0x07) are routed by CLA, so nothing is
      // ever served through 0xE0 while one of them is open.
      LedgerApp.bitcoin || LedgerApp.sui =>
        _errorResponse(Sw.insNotSupported),
    };
  }

  /// Parse an OPEN_APP payload ("Ethereum" / "Solana" / "Bitcoin" / …) and
  /// switch the active INS table.
  ///
  /// An unrecognized name leaves the current table untouched.
  void _setCurrentApp(Uint8List? data) {
    if (data == null || data.isEmpty) return;
    final name = String.fromCharCodes(
            data.where((b) => b >= 0x20 && b < 0x7f))
        .toLowerCase();
    final app = LedgerApp.fromLedgerName(name);
    if (app == null) return;
    _activateApp(app);
  }

  /// INS 0xE0 dispatch while the Ethereum app is open (the default).
  ApduResponse _handleEthereumApp(ApduCommand command) {
    switch (command.ins) {
      // ── OS-level commands ───────────────────────────────────────
      case Ins.getVersion: // CLA E0 → Ethereum app GET_VERSION
        return _buildGetVersion();

      case Ins.getAppName: // 0x02 — ETH_GET_ADDRESS
        return _handleGetPublicKey(command);

      // ── Ethereum app configuration ───────────────────────────────
      // Standard Ledger ETH_GET_APP_CONFIGURATION = INS 0x06. Host
      // wallets probe this before sign requests; it must not be treated
      // as transaction signing.
      case Ins.getAppConfiguration:
        return _buildGetAppConfiguration();

      // ── Ethereum signing ──────────────────────────────────────────
      // Standard Ledger ETH_SIGN = INS 0x04
      case Ins.ethSign:
        return _handleEthSignTx(command);

      case Ins.signEthPersonalMessage:
        return _handleEthSignPersonal(command);

      // ── ERC-20 token metadata provisioning (INS 0x0A) ─────────────
      // Sent before token transfers so the device can show ticker/amount.
      // No confirmation, no data to persist — just acknowledge.
      case Ins.ethProvideErc20TokenInfo:
        return ApduResponse(data: null, sw1: 0x90, sw2: 0x00);

      // ── EIP-712 typed-data signing (INS 0x0C) ─────────────────────
      // The single official entrypoint is SIGN_EIP_712_MESSAGE (0x0C).
      // Only the V0 single-step form (P2=0x00) is implemented; P2=0x01 is
      // the V1 streaming form, reserved and refused with 0x6A86.
      case Ins.ethSignEip712:
        return _handleEthSignEip712(command);

      default:
        return _errorResponse(Sw.insNotSupported);
    }
  }

  /// INS 0xE0 dispatch while the Solana app is open.
  ///
  /// Real Ledger Solana app INS table (hw-app-solana):
  ///   0x04 GET_VERSION · 0x05 GET_ADDR · 0x06 SIGN · 0x07 SIGN_OFFCHAIN
  /// Message chunking uses P2 flags (P2_EXTEND=0x01 | P2_MORE=0x02);
  /// single-chunk messages are handled today, multi-chunk assembly is
  /// tracked in BACKLOG.
  ApduResponse _handleSolanaApp(ApduCommand command) {
    switch (command.ins) {
      case Ins.solGetVersion: // 0x04
        return _buildSolVersion();
      case Ins.solGetAddress: // 0x05
        return _handleSolGetAddress(command);
      case Ins.solSignMessage: // 0x06
      case Ins.solSignOffchainMessage: // 0x07
        return _handleSolSignMessage(command);
      default:
        return _errorResponse(Sw.insNotSupported);
    }
  }

  /// Solana GET_VERSION response: [flags(1)] [major] [minor] [patch] + 9000.
  ApduResponse _buildSolVersion() {
    return ApduResponse(
      data: Uint8List.fromList([0x00, 0x01, 0x00, 0x00]),
      sw1: 0x90,
      sw2: 0x00,
    );
  }

  /// Solana GET_ADDR (INS 0x05): data = BIP-32 derivation path.
  ///
  /// Response: **bare 32-byte Ed25519 pubkey** + 9000. The real app-solana
  /// replies with the raw key and no length prefix — @ledgerhq/hw-app-solana
  /// returns the payload as-is (`getAddress` → `sendToDevice`, which only
  /// strips the two SW bytes). A `0x20` length prefix must NOT be added:
  /// hosts would then treat 33 bytes as the pubkey, producing a 45-character
  /// "address" that no wallet can use.
  ApduResponse _handleSolGetAddress(ApduCommand command) {
    if (!hasContext) return _errorResponse(Sw.securityStatusNotSatisfied);

    final path = _parseDerivationPath(command.data);
    if (path == null && (command.data == null || command.data!.isEmpty)) {
      // Default Solana path.
      return _errorResponse(Sw.wrongData);
    }
    if (path == null) return _errorResponse(Sw.wrongData);

    final seedHex = _computeSeed();
    final privKey = _crypto.deriveEd25519PrivateKey(seedHex, path);
    if (privKey == null) return _errorResponse(Sw.unknownError);
    final pubkey = _crypto.solanaPublicKeyBytes(_crypto.hexEncode(privKey));
    if (pubkey == null) return _errorResponse(Sw.unknownError);

    final resp = Uint8List(pubkey.length + 2);
    resp.setRange(0, pubkey.length, pubkey);
    resp[pubkey.length] = 0x90;
    resp[pubkey.length + 1] = 0x00;
    return ApduResponse.fromBytes(resp);
  }

  /// INS 0xE0 dispatch while the Tron app is open.
  ///
  /// Real Ledger Tron app INS table (`@ledgerhq/hw-app-trx`, CLA 0xE0):
  ///   0x02 GET_ADDRESS · 0x04 SIGN · 0x05 SIGN_HASH · 0x06 VERSION
  ///   0x08 SIGN_MESSAGE
  ///
  /// Host wallets (TronLink, OKX) speak CLA 0xE0 for Tron, not the legacy
  /// 0x14 alias this codebase used before — they rely on the app opened via
  /// OPEN_APP / GET_APP_AND_VERSION to disambiguate, exactly like Solana.
  ApduResponse _handleTronApp(ApduCommand command) {
    switch (command.ins) {
      case Ins.tronGetPublicKey: // 0x02 — GET_ADDRESS
        return _handleTronGetAddress(command);
      case Ins.tronGetAppConfiguration: // 0x06 — VERSION / app configuration
        return _buildTronAppConfiguration();
      // Tron signing needs a sha256-based secp256k1 signer returning
      // r||s||v with the raw recovery id (not EIP-155/EIP-191 v). The Rust
      // FFI does not expose one yet, so these are reported unsupported
      // rather than emitting a wrong signature from the Ethereum keccak
      // signer.
      case Ins.tronSignTx: // 0x04 — SIGN
      case Ins.tronSignHash: // 0x05 — SIGN_HASH
      case Ins.tronSignPersonalMessage: // 0x08 — SIGN_MESSAGE
        return _errorResponse(Sw.insNotSupported);
      default:
        return _errorResponse(Sw.insNotSupported);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Response builders — OS / Global
  // ─────────────────────────────────────────────────────────────────

  /// BOLOS firmware version reported while the dashboard is up.
  ///
  /// Mirrors the SE version this device already reports in GET_VERSION so
  /// the two never disagree.
  static const String _firmwareVersion = '1.10.3';

  /// Build GET_APP_AND_VERSION response (CLA 0xB0, INS 0x01).
  ///
  /// Reports the app currently open, or the dashboard when none is. Wallets
  /// call this on connect and poll it until it names the app they need
  /// (Ethereum / Solana / Bitcoin / Tron / Sui), so the payload must match
  /// what a real device sends in both states.
  ///
  /// Format: [format] [name_len] [name] [ver_len] [ver] [flags_len] [flags]
  ///         [0x90 0x00]
  ///
  /// An open app reports format `0x01`; the dashboard reports format `0x00`
  /// with the BOLOS name. Ledger's own client rejects any format other than
  /// `0x01` (`getAppAndVersion.ts` throws `GetAppAndVersionUnsupportedFormat`),
  /// which is exactly how a wallet learns it must ask the user to open an
  /// app — the behaviour we are reproducing.
  ApduResponse _buildGetAppAndVersion() {
    final app = _currentApp;
    return _appAndVersion(
      format: app == null ? 0x00 : 0x01,
      name: app?.ledgerName ?? LedgerApp.dashboardName,
      version: app?.version ?? _firmwareVersion,
      flags: app == null ? 0x00 : 0x02,
    );
  }

  /// Encode a GET_APP_AND_VERSION payload.
  ApduResponse _appAndVersion({
    required int format,
    required String name,
    required String version,
    required int flags,
  }) {
    final nameBytes = utf8.encode(name);
    final verBytes = utf8.encode(version);
    final resp =
        Uint8List(1 + 1 + nameBytes.length + 1 + verBytes.length + 1 + 1 + 2);
    int i = 0;
    resp[i++] = format;
    resp[i++] = nameBytes.length;
    resp.setRange(i, i + nameBytes.length, nameBytes);
    i += nameBytes.length;
    resp[i++] = verBytes.length;
    resp.setRange(i, i + verBytes.length, verBytes);
    i += verBytes.length;
    resp[i++] = 1;
    resp[i++] = flags; // 0x02 = virtual device
    resp[i++] = 0x90;
    resp[i] = 0x00; // SW OK
    return ApduResponse.fromBytes(resp);
  }

  /// Build ETH_GET_APP_CONFIGURATION response (CLA 0xE0, INS 0x06).
  ///
  /// Ledger Ethereum format: flags(1) + major(1) + minor(1) + patch(1).
  /// Flag 0x01 advertises arbitrary-data / EIP-712 signing support so host
  /// wallets proceed past the connection handshake.
  ApduResponse _buildGetAppConfiguration() {
    return ApduResponse(
      data: Uint8List.fromList([
        0x01, // arbitrary data / EIP-712 signing enabled
        0x01, 0x0A, 0x03, // Ethereum app version 1.10.3
      ]),
      sw1: 0x90,
      sw2: 0x00,
    );
  }

  /// Build the Tron app configuration response (CLA 0xE0, INS 0x06).
  ///
  /// hw-app-trx `getAppConfiguration` layout: flags(1) + major(1) + minor(1)
  /// + patch(1). Flag bit 0 (0x01) = blind signing enabled; the version is
  /// reported as 0.5.0, matching the Tron app version this device emulates.
  ApduResponse _buildTronAppConfiguration() {
    return ApduResponse(
      data: Uint8List.fromList([0x01, 0x00, 0x05, 0x00]),
      sw1: 0x90,
      sw2: 0x00,
    );
  }

  /// Build GET_VERSION response (CLA 0xE0, INS 0x01 for non-Solana).
  ///
  /// Format: target_id(4) + se_ver_len(1) + se_ver + flags_len(1) + flags(4)
  ///         + mcu_ver_len(1) + mcu_ver + 0x90 0x00
  ApduResponse _buildGetVersion() {
    final seVer = utf8.encode('1.10.3');
    final flags = Uint8List.fromList([0, 0, 0, 0]);
    final mcuVer = Uint8List.fromList([...utf8.encode('1.13'), 0]);
    final resp = Uint8List(4 + 1 + seVer.length + 1 + 4 + 1 + mcuVer.length + 2);
    int i = 0;
    resp[i++] = 0x33; resp[i++] = 0x00; resp[i++] = 0x00; resp[i++] = 0x04; // target_id
    resp[i++] = seVer.length; resp.setRange(i, i + seVer.length, seVer); i += seVer.length;
    resp[i++] = 4; resp.setRange(i, i + 4, flags); i += 4; // flags
    resp[i++] = mcuVer.length; resp.setRange(i, i + mcuVer.length, mcuVer); i += mcuVer.length;
    resp[i++] = 0x90; resp[i] = 0x00; // SW OK
    return ApduResponse.fromBytes(resp);
  }

  // ─────────────────────────────────────────────────────────────────
  // ETH: get address handler
  // ─────────────────────────────────────────────────────────────────

  /// Build ETH GET_PUBLIC_KEY / GET_ADDRESS response matching the official
  /// Ledger Ethereum app layout (app-ethereum `get_public_key.c:46-58`):
  /// [0x41] [65B uncompressed pubkey] [0x28] [40B ASCII addr hex]
  /// [32B BIP-32 chain code, only when `withChainCode`] [90 00]
  ///
  /// The chain code is a BIP-32 CKDpriv output and can only come from the same
  /// derivation as the private key — it cannot be recomputed from the key
  /// alone. Hosts request it (P2 = 0x01) to rebuild an xpub.
  ApduResponse _buildEthAddressResponse(
    String seedHex,
    String path, {
    bool withChainCode = false,
  }) {
    final extended = _crypto.deriveSecp256k1Extended(seedHex, path);
    if (extended == null || extended.length != 64) {
      return _errorResponse(Sw.unknownError);
    }
    final privKey = extended.sublist(0, 32);
    final chainCode = extended.sublist(32, 64);

    final privKeyHex = _crypto.hexEncode(privKey);
    final addr = _crypto.ethAddressFromPrivateKey(privKeyHex);
    final pubkey = _crypto.ethPublicKeyBytes(privKeyHex);
    if (addr == null || pubkey == null) return _errorResponse(Sw.unknownError);

    // Strip "0x" prefix — Ledger response uses 40 raw hex chars, no prefix.
    final addrStripped = addr.startsWith('0x') ? addr.substring(2) : addr;
    final addrBytes = utf8.encode(addrStripped);
    final chainCodeLen = withChainCode ? 32 : 0;
    final resp = Uint8List(1 + 65 + 1 + addrBytes.length + chainCodeLen + 2);
    int i = 0;
    resp[i++] = 0x41;
    resp.setRange(i, i + 65, pubkey); i += 65;
    resp[i++] = addrBytes.length;
    resp.setRange(i, i + addrBytes.length, addrBytes); i += addrBytes.length;
    if (withChainCode) {
      resp.setRange(i, i + 32, chainCode); i += 32;
    }
    resp[i++] = 0x90; resp[i] = 0x00;

    return ApduResponse.fromBytes(resp);
  }

  /// Derive the Ethereum address for [path] from the current seed context.
  ///
  /// Used by the BLE layer to display the address in the GET_PUBLIC_KEY
  /// P1=0x01 "display and confirm" flow. Returns `null` when no context is
  /// set or derivation fails.
  String? deriveEthAddressForPath(String path) {
    if (!hasContext) return null;
    final extended = _crypto.deriveSecp256k1Extended(_computeSeed(), path);
    if (extended == null || extended.length != 64) return null;
    final privKeyHex = _crypto.hexEncode(extended.sublist(0, 32));
    return _crypto.ethAddressFromPrivateKey(privKeyHex);
  }

  ApduResponse _handleGetPublicKey(ApduCommand command) {
    if (!hasContext) return _errorResponse(Sw.securityStatusNotSatisfied);

    // P1/P2 are validated per the official app-ethereum GET_PUBLIC_KEY table
    // (`cmd_get_public_key.c:20-37`): P1 ∈ {0x00 return, 0x01 display+confirm},
    // P2 ∈ {0x00 no chain code, 0x01 chain code}. Anything else is
    // SWO_WRONG_P1_P2 (0x6A86).
    if (command.p1 != P1.ethNonConfirm && command.p1 != P1.ethConfirm) {
      return _errorResponse(Sw.incorrectP1P2);
    }
    if (command.p2 != P2.ethNoChainCode && command.p2 != P2.ethChainCode) {
      return _errorResponse(Sw.incorrectP1P2);
    }

    // When no path data is provided, use the default derivation path.
    String? path = _parseDerivationPath(command.data);
    if (path == null && (command.data == null || command.data!.isEmpty)) {
      path = "m/44'/60'/0'/0/0";
    }
    if (path == null) return _errorResponse(Sw.wrongData);

    final seedHex = _computeSeed();

    // INS 0x02 in the Ethereum app is always ETH_GET_ADDRESS.
    // (The old `p1 == 0x01 → Solana` branch was wrong: in the real ETH app
    // P1=0x01 means "show address on screen", and Solana get-address is
    // INS 0x05 after OPEN_APP "Solana".)
    //
    // P2=0x01 appends the 32-byte BIP-32 chain code (cmd_get_public_key.c:37).
    final withChainCode = command.p2 == P2.ethChainCode;
    return _buildEthAddressResponse(seedHex, path,
        withChainCode: withChainCode);
  }

  // ─────────────────────────────────────────────────────────────────
  // ETH: sign transaction handler
  // ─────────────────────────────────────────────────────────────────

  /// Handle ETH_SIGN (INS 0x04).
  ///
  /// Official semantics (app-ethereum `doc/apdu.md:101-103`):
  /// - P1=0x00: first transaction data block
  /// - P1=0x80: subsequent transaction data block
  /// - P2=0x00: process & start flow (return the signature)
  /// - P2=0x01: store only (no signature returned)
  /// - P2=0x02: start flow (first block carries no data)
  ///
  /// Multi-block assembly lives in the BLE layer ([EthTxAssembler]); this
  /// handler serves the single-APDU path (direct callers / tests).
  ApduResponse _handleEthSignTx(ApduCommand command) {
    if (!hasContext) return _errorResponse(Sw.securityStatusNotSatisfied);

    if (command.p1 != 0x00 && command.p1 != 0x80) {
      return _errorResponse(Sw.incorrectP1P2);
    }
    if (command.p2 != 0x00 && command.p2 != 0x01 && command.p2 != 0x02) {
      return _errorResponse(Sw.incorrectP1P2);
    }

    // P2=0x02 — start flow, no data: acknowledge and wait for the first block.
    if (command.p2 == 0x02) {
      return ApduResponse(data: null, sw1: 0x90, sw2: 0x00);
    }

    final data = command.data;
    if (data == null || data.length < 5) return _errorResponse(Sw.wrongData);

    final pathResult = _parseDerivationPathFromData(data);
    if (pathResult == null) return _errorResponse(Sw.wrongData);

    final rlpData = pathResult.remainder;
    if (rlpData.isEmpty) return _errorResponse(Sw.wrongData);

    // P2=0x01 — store only: the block is accepted but no signature is
    // returned (the host asked the device to hold the data).
    if (command.p2 == 0x01) {
      return ApduResponse(data: null, sw1: 0x90, sw2: 0x00);
    }

    final seedHex = _computeSeed();
    final privKey = _crypto.deriveSecp256k1PrivateKey(seedHex, pathResult.path);
    if (privKey == null) return _errorResponse(Sw.unknownError);

    final sig = _crypto.signEthTransaction(
      _crypto.hexEncode(privKey),
      _crypto.hexEncode(rlpData),
    );
    if (sig == null) return _errorResponse(Sw.unknownError);

    return _successBytes(sig);
  }

  /// Handle EIP-712 typed data signing.
  ///
  /// The [remainder] from path parsing must be 64 bytes:
  ///   [domain_hash(32B)][struct_hash(32B)]
  /// Both hashes are passed to [ICryptoService.signEthEIP712] which computes
  /// `keccak256(0x19 || 0x01 || domainHash || structHash)` and signs.
  ApduResponse _handleEthSignEip712Data(
      String seedHex, String path, Uint8List remainder) {
    if (remainder.length != 64) {
      return _errorResponse(Sw.wrongData);
    }
    final domainHash = Uint8List.sublistView(remainder, 0, 32);
    final structHash = Uint8List.sublistView(remainder, 32, 64);

    final privKey = _crypto.deriveSecp256k1PrivateKey(seedHex, path);
    if (privKey == null) return _errorResponse(Sw.unknownError);

    final sig = _crypto.signEthEIP712(
      _crypto.hexEncode(privKey),
      _crypto.hexEncode(domainHash),
      _crypto.hexEncode(structHash),
    );
    if (sig == null) return _errorResponse(Sw.unknownError);

    return _successBytes(sig);
  }

  /// Handle EIP-712 typed-data signing (INS 0x0C) — V0 single-step only.
  ///
  /// Official semantics (`app-ethereum/doc/apdu.md:290-305`): P1=0x00 and
  /// P2 selects the encoding — P2=0x00 is the V0 (legacy) form whose data is
  /// `[path][domain_hash(32)][struct_hash(32)]`, while P2=0x01 is the V1
  /// full-streaming form. V1 is reserved and not implemented, so P2=0x01 is
  /// refused with SWO_WRONG_P1_P2 (0x6A86) rather than silently misread.
  ApduResponse _handleEthSignEip712(ApduCommand command) {
    if (!hasContext) return _errorResponse(Sw.securityStatusNotSatisfied);

    // P1=0x00 is the only defined value; P2=0x00 is V0 (implemented),
    // P2=0x01 is V1 streaming (reserved).
    if (command.p1 != 0x00) return _errorResponse(Sw.incorrectP1P2);
    if (command.p2 != 0x00) return _errorResponse(Sw.incorrectP1P2);

    final data = command.data;
    if (data == null || data.length < 5) return _errorResponse(Sw.wrongData);

    final pathResult = _parseDerivationPathFromData(data);
    if (pathResult == null) return _errorResponse(Sw.wrongData);

    // V0 payload: domain_hash(32) + struct_hash(32).
    if (pathResult.remainder.length < 64) {
      return _errorResponse(Sw.wrongData);
    }

    final combined = Uint8List(64)..setRange(0, 64, pathResult.remainder);
    final seedHex = _computeSeed();
    return _handleEthSignEip712Data(seedHex, pathResult.path, combined);
  }

  // ─────────────────────────────────────────────────────────────────
  // ETH: sign personal message handler
  // ─────────────────────────────────────────────────────────────────

  ApduResponse _handleEthSignPersonal(ApduCommand command) {
    if (!hasContext) return _errorResponse(Sw.securityStatusNotSatisfied);

    // P1 ∈ {0x00 first block, 0x80 subsequent}, P2 = 0x00 (app-ethereum
    // doc/apdu.md:174-176). Multi-block streaming is not assembled here, so a
    // continuation block (no path) is rejected as WRONG_DATA below.
    if (command.p1 != 0x00 && command.p1 != 0x80) {
      return _errorResponse(Sw.incorrectP1P2);
    }
    if (command.p2 != 0x00) return _errorResponse(Sw.incorrectP1P2);

    final data = command.data;
    if (data == null || data.length < 5) return _errorResponse(Sw.wrongData);

    final pathResult = _parseDerivationPathFromData(data);
    if (pathResult == null) return _errorResponse(Sw.wrongData);

    final path = pathResult.path;

    // Official first-block layout: [path][Message length (4B BE)][Message chunk]
    // (doc/apdu.md:178-187). The declared length must equal the chunk we
    // received — multi-chunk messages are not assembled here.
    final payload = pathResult.remainder;
    if (payload.length < 4) return _errorResponse(Sw.wrongData);
    final declaredLength = (payload[0] << 24) |
        (payload[1] << 16) |
        (payload[2] << 8) |
        payload[3];
    final messageData = Uint8List.sublistView(payload, 4);
    if (messageData.isEmpty) return _errorResponse(Sw.wrongData);
    if (declaredLength != messageData.length) {
      return _errorResponse(Sw.wrongData);
    }

    final seedHex = _computeSeed();
    final privKey =
        _crypto.deriveSecp256k1PrivateKey(seedHex, path);
    if (privKey == null) return _errorResponse(Sw.unknownError);

    final sig = _crypto.signEthPersonalMessage(
      _crypto.hexEncode(privKey),
      _crypto.hexEncode(messageData),
    );
    if (sig == null) return _errorResponse(Sw.unknownError);

    return _successBytes(sig);
  }

  // ─────────────────────────────────────────────────────────────────
  // SOL: sign message handler
  // ─────────────────────────────────────────────────────────────────

  ApduResponse _handleSolSignMessage(ApduCommand command) {
    if (!hasContext) return _errorResponse(Sw.securityStatusNotSatisfied);

    var data = command.data;
    if (data == null || data.length < 5) return _errorResponse(Sw.wrongData);

    // OKX prefixes Solana signing frames with a `num_signers` byte.
    data = PathParser.stripNumSignersPrefix(data);

    final pathResult = _parseDerivationPathFromData(data);
    if (pathResult == null) return _errorResponse(Sw.wrongData);

    final path = pathResult.path;
    final messageData = pathResult.remainder;

    if (messageData.isEmpty) return _errorResponse(Sw.conditionsNotSatisfied);

    final seedHex = _computeSeed();
    final privKey =
        _crypto.deriveEd25519PrivateKey(seedHex, path);
    if (privKey == null) return _errorResponse(Sw.unknownError);

    final sig = _crypto.signSolanaMessage(
      _crypto.hexEncode(privKey),
      _crypto.hexEncode(messageData),
    );
    if (sig == null) return _errorResponse(Sw.unknownError);

    return _successBytes(sig);
  }

  // ─────────────────────────────────────────────────────────────────
  // Bitcoin handler (CLA 0xe1 / 0xf8)
  // ─────────────────────────────────────────────────────────────────

  ApduResponse _handleBitcoin(ApduCommand command) {
    switch (command.ins) {
      case Ins.btcGetWalletPublicKey:
        return _handleBtcGetAddress(command);

      case Ins.btcSignTx:
        return _handleBtcSignTx(command);

      default:
        return _errorResponse(Sw.insNotSupported);
    }
  }

  ApduResponse _handleBtcGetAddress(ApduCommand command) {
    if (!hasContext) return _errorResponse(Sw.securityStatusNotSatisfied);

    final path = _parseDerivationPath(command.data);
    if (path == null) return _errorResponse(Sw.wrongData);

    final seedHex = _computeSeed();
    final address = _crypto.deriveBtcAddress(seedHex, path);
    if (address == null) return _errorResponse(Sw.unknownError);

    return _successString(address);
  }

  ApduResponse _handleBtcSignTx(ApduCommand command) {
    if (!hasContext) return _errorResponse(Sw.securityStatusNotSatisfied);

    final data = command.data;
    if (data == null || data.length < 5) return _errorResponse(Sw.wrongData);

    final pathResult = _parseDerivationPathFromData(data);
    if (pathResult == null) return _errorResponse(Sw.wrongData);

    final path = pathResult.path;
    final txData = pathResult.remainder;

    // BTC transaction signing uses secp256k1 (same as ETH).
    final seedHex = _computeSeed();
    final privKey =
        _crypto.deriveSecp256k1PrivateKey(seedHex, path);
    if (privKey == null) return _errorResponse(Sw.unknownError);

    // Sign the transaction hash (txData = pre-computed sighash).
    final sig = _crypto.signEthTransaction(
      _crypto.hexEncode(privKey),
      _crypto.hexEncode(txData),
    );
    if (sig == null) return _errorResponse(Sw.unknownError);

    return _successBytes(sig);
  }

  // ─────────────────────────────────────────────────────────────────
  // Tron handler (CLA 0x14)
  // ─────────────────────────────────────────────────────────────────

  ApduResponse _handleTron(ApduCommand command) {
    switch (command.ins) {
      case Ins.tronGetPublicKey:
        return _handleTronGetAddress(command);

      case Ins.tronSignTx:
        return _handleTronSignTx(command);

      default:
        return _errorResponse(Sw.insNotSupported);
    }
  }

  ApduResponse _handleTronGetAddress(ApduCommand command) {
    if (!hasContext) return _errorResponse(Sw.securityStatusNotSatisfied);

    final path = _parseDerivationPath(command.data);
    if (path == null) return _errorResponse(Sw.wrongData);

    return _buildTronAddressResponse(_computeSeed(), path);
  }

  /// Build the Tron GET_ADDRESS response (Ledger Tron app / hw-app-trx):
  /// [pubkey_len(1)] [65B uncompressed pubkey] [addr_len(1)]
  /// [base58 address ASCII] [0x90 0x00].
  ///
  /// hw-app-trx `getAddress` reads the public key length from byte 0 and the
  /// address length from the byte after the key, so the address must carry a
  /// length prefix — a bare ASCII string (the old behavior) is unparseable.
  ApduResponse _buildTronAddressResponse(String seedHex, String path) {
    final privKey = _crypto.deriveSecp256k1PrivateKey(seedHex, path);
    if (privKey == null) return _errorResponse(Sw.unknownError);
    final privKeyHex = _crypto.hexEncode(privKey);

    final pubkey = _crypto.ethPublicKeyBytes(privKeyHex); // 65B uncompressed
    if (pubkey == null) return _errorResponse(Sw.unknownError);
    final address = _crypto.tronAddressFromPubkey(_crypto.hexEncode(pubkey));
    if (address == null) return _errorResponse(Sw.unknownError);

    final addrBytes = Uint8List.fromList(address.codeUnits);
    final resp = Uint8List(1 + pubkey.length + 1 + addrBytes.length + 2);
    int i = 0;
    resp[i++] = pubkey.length;
    resp.setRange(i, i + pubkey.length, pubkey); i += pubkey.length;
    resp[i++] = addrBytes.length;
    resp.setRange(i, i + addrBytes.length, addrBytes); i += addrBytes.length;
    resp[i++] = 0x90; resp[i] = 0x00;
    return ApduResponse.fromBytes(resp);
  }

  ApduResponse _handleTronSignTx(ApduCommand command) {
    if (!hasContext) return _errorResponse(Sw.securityStatusNotSatisfied);

    final data = command.data;
    if (data == null || data.length < 5) return _errorResponse(Sw.wrongData);

    final pathResult = _parseDerivationPathFromData(data);
    if (pathResult == null) return _errorResponse(Sw.wrongData);

    final path = pathResult.path;
    final txData = pathResult.remainder;

    // Tron uses secp256k1 signing.
    final seedHex = _computeSeed();
    final privKey =
        _crypto.deriveSecp256k1PrivateKey(seedHex, path);
    if (privKey == null) return _errorResponse(Sw.unknownError);

    final sig = _crypto.signEthTransaction(
      _crypto.hexEncode(privKey),
      _crypto.hexEncode(txData),
    );
    if (sig == null) return _errorResponse(Sw.unknownError);

    return _successBytes(sig);
  }

  // ─────────────────────────────────────────────────────────────────
  // Sui handler (CLA 0x07)
  // ─────────────────────────────────────────────────────────────────

  ApduResponse _handleSui(ApduCommand command) {
    switch (command.ins) {
      case Ins.suiGetPublicKey:
        return _handleSuiGetAddress(command);

      case Ins.suiSignTx:
        return _handleSuiSignTx(command);

      default:
        return _errorResponse(Sw.insNotSupported);
    }
  }

  ApduResponse _handleSuiGetAddress(ApduCommand command) {
    if (!hasContext) return _errorResponse(Sw.securityStatusNotSatisfied);

    final path = _parseDerivationPath(command.data);
    if (path == null) return _errorResponse(Sw.wrongData);

    final seedHex = _computeSeed();
    final address = _crypto.deriveSuiAddress(seedHex, path);
    if (address == null) return _errorResponse(Sw.unknownError);

    return _successString(address);
  }

  ApduResponse _handleSuiSignTx(ApduCommand command) {
    if (!hasContext) return _errorResponse(Sw.securityStatusNotSatisfied);

    final data = command.data;
    if (data == null || data.length < 5) return _errorResponse(Sw.wrongData);

    final pathResult = _parseDerivationPathFromData(data);
    if (pathResult == null) return _errorResponse(Sw.wrongData);

    final path = pathResult.path;
    final txData = pathResult.remainder;

    // Sui uses Ed25519 signing.
    final seedHex = _computeSeed();
    final privKey =
        _crypto.deriveEd25519PrivateKey(seedHex, path);
    if (privKey == null) return _errorResponse(Sw.unknownError);

    final sig = _crypto.signSolanaMessage(
      _crypto.hexEncode(privKey),
      _crypto.hexEncode(txData),
    );
    if (sig == null) return _errorResponse(Sw.unknownError);

    return _successBytes(sig);
  }

  // ─────────────────────────────────────────────────────────────────
  // Helpers — Derivation path parsing
  // ─────────────────────────────────────────────────────────────────

  /// Parse a BIP-32 derivation path from APDU data.
  ///
  /// APDU encoding (Ledger protocol):
  /// - Byte 0: depth as uint8 (number of derivation components)
  /// - Remaining bytes: depth × 4 bytes per component (big-endian uint32)
  ///   - Bit 31 (`0x80000000`) indicates hardened derivation
  ///
  /// Returns the BIP-32 path string (e.g. `"m/44'/60'/0'/0/0"`)
  /// or `null` if the data is invalid or too short.
  String? _parseDerivationPath(Uint8List? data) {
    if (data == null || data.isEmpty) return null;

    final depth = data[0];
    if (depth > 10) return null; // sanity check
    final expectedLen = 1 + depth * 4;

    if (data.length < expectedLen) return null;

    final components = <String>['m'];
    for (int i = 0; i < depth; i++) {
      final offset = 1 + i * 4;
      final value = _readUint32BE(data, offset);
      final isHardened = (value & 0x80000000) != 0;
      final index = value & 0x7FFFFFFF;
      components.add(isHardened ? "$index'" : '$index');
    }

    return components.join('/');
  }

  /// Parse a derivation path from the beginning of [data], returning
  /// both the path string and the remaining bytes (e.g. transaction data).
  ///
  /// Returns `null` if the path data is invalid.
  _PathParseResult? _parseDerivationPathFromData(Uint8List data) {
    if (data.isEmpty) return null;

    final depth = data[0];
    if (depth > 10) return null; // sanity check
    final pathBytesLen = 1 + depth * 4;

    if (data.length < pathBytesLen) return null;

    final pathBytes = Uint8List.sublistView(data, 0, pathBytesLen);
    final remainder = Uint8List.sublistView(data, pathBytesLen);

    final path = _parseDerivationPath(pathBytes);
    if (path == null) return null;

    return _PathParseResult(path, remainder);
  }

  /// Read a big-endian 32-bit unsigned integer from [data] at [offset].
  static int _readUint32BE(Uint8List data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  // ─────────────────────────────────────────────────────────────────
  // Helpers — Seed derivation
  // ─────────────────────────────────────────────────────────────────

  /// Return the seed hex for key derivation.
  ///
  /// Returns the pre-computed seed set via [setContext].
  ///
  /// Throws [StateError] if no context has been set.
  String _computeSeed() {
    if (_seedHex != null) return _seedHex!;
    throw StateError('Wallet context not set. Call setContext() first.');
  }

  // ─────────────────────────────────────────────────────────────────
  // Helpers — Response builders
  // ─────────────────────────────────────────────────────────────────

  /// Creates a success response with binary data.
  ApduResponse _successBytes(Uint8List data) {
    return ApduResponse(data: data, sw1: 0x90, sw2: 0x00);
  }

  /// Creates a success response with an ASCII string as data.
  ApduResponse _successString(String s) {
    return ApduResponse(data: Uint8List.fromList(s.codeUnits), sw1: 0x90, sw2: 0x00);
  }

  /// Creates an error response with the given 16-bit status word.
  ///
  /// The status word is split into [ApduResponse.sw1] (high byte) and
  /// [ApduResponse.sw2] (low byte).
  ApduResponse _errorResponse(int sw) {
    return ApduResponse(
      data: null,
      sw1: (sw >> 8) & 0xFF,
      sw2: sw & 0xFF,
    );
  }
}

/// Result of parsing a derivation path from APDU data with a remainder.
class _PathParseResult {
  final String path;
  final Uint8List remainder;

  const _PathParseResult(this.path, this.remainder);
}
