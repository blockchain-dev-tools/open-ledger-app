/// OS / app-level APDU dispatcher.
///
/// Every chain command (ETH / BTC / SOL / Tron / Sui) is served by the Rust
/// chain-app host. What is left in Dart is the device shell a host talks to
/// before and around signing:
///
///   * BOLOS dashboard commands (GET_APP_AND_VERSION, GET_APP_NAME),
///   * OPEN_APP / QUIT_APP, which select the CLA-0xE0 INS table,
///   * the app-level probes that never reach the chain modules
///     (ETH GET_VERSION / GET_APP_CONFIGURATION / ERC-20 ACK,
///     Solana GET_VERSION, Tron GET_APP_CONFIGURATION).
///
/// Signing, address derivation and review construction live in the Rust
/// modules; this table answers 6D00 for any chain INS it does not own.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/models/apdu_message.dart';
import '../core/models/ble_types.dart';
import '../core/models/chain.dart';
import '../protocols/apdu/apdu_constants.dart';

/// Dispatches OS / app-level APDU commands.
///
/// CLA 0xE0 belongs to the app the host opened via OPEN_APP; while no app is
/// open (dashboard) there is no table to dispatch through and a real device
/// answers INS_NOT_SUPPORTED.
class ApduHandler {
  // ── Ledger app state (CLA 0xE0 routing table selection) ─────────────

  /// App currently opened via BOLOS OPEN_APP (INS 0xD8), or `null` while the
  /// device sits on the dashboard.
  ///
  /// CLA 0xE0 is shared by the OS, the Ethereum app, the Solana app and the
  /// Tron app, and their INS tables OVERLAP (0x04 = ETH_SIGN in the Ethereum
  /// app but GET_VERSION in the Solana app; 0x06 = GET_APP_CONFIGURATION in
  /// Ethereum but SIGN in Solana). The only correct way to disambiguate is
  /// the app the host explicitly opened — same as a real Ledger device.
  ///
  /// Bitcoin (`0xE1`/`0xF8`) and Sui (`0x07`) carry their own CLA and never
  /// depend on this.
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

  // ── Main dispatch ───────────────────────────────────────────────────

  /// Route an APDU command to the OS / app table.
  ///
  /// Returns an [ApduResponse] with the result or an error status word.
  ApduResponse handle(ApduCommand command) {
    switch (command.cla) {
      case Cla.os:
      case Cla.global:
        return _handleOs(command);
      // Chain CLAs are owned by the Rust modules; nothing in this table
      // serves them.
      case Cla.bitcoin:
      case Cla.bitcoinExt:
      case Cla.sui:
        return _errorResponse(Sw.insNotSupported);
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
      final nameBytes = Uint8List.fromList(defaultBleDeviceName.codeUnits);
      return ApduResponse(data: nameBytes, sw1: 0x90, sw2: 0x00);
    }

    // E0 D8 — OPEN_APP. Client selects which app to use; data is the app
    // name in ASCII. This drives the CLA-0xE0 INS routing table.
    if (command.cla == Cla.os && command.ins == Ins.openApp) {
      _setCurrentApp(command.data);
      return ApduResponse(data: null, sw1: 0x90, sw2: 0x00);
    }

    // E0 A7 — QUIT_APP. Back to the dashboard: no app table is loaded.
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
  ///
  /// Only the frame-level probes stay here. GET_PUBLIC_KEY (0x02), SIGN
  /// (0x04), SIGN_PERSONAL (0x08) and EIP-712 (0x0C) are served by the Rust
  /// Ethereum module.
  ApduResponse _handleEthereumApp(ApduCommand command) {
    switch (command.ins) {
      case Ins.getVersion: // CLA E0 → Ethereum app GET_VERSION
        return _buildGetVersion();

      // Standard Ledger ETH_GET_APP_CONFIGURATION = INS 0x06. Host wallets
      // probe this before sign requests; it must not be treated as signing.
      case Ins.getAppConfiguration:
        return _buildGetAppConfiguration();

      // ── ERC-20 token metadata provisioning (INS 0x0A) ─────────────
      // Sent before token transfers so the device can show ticker/amount.
      // No confirmation, no data to persist — just acknowledge.
      case Ins.ethProvideErc20TokenInfo:
        return ApduResponse(data: null, sw1: 0x90, sw2: 0x00);

      default:
        return _errorResponse(Sw.insNotSupported);
    }
  }

  /// INS 0xE0 dispatch while the Solana app is open.
  ///
  /// Real Ledger Solana app INS table (hw-app-solana):
  ///   0x04 GET_VERSION · 0x05 GET_ADDR · 0x06 SIGN · 0x07 SIGN_OFFCHAIN
  /// Everything but the version probe is served by the Rust Solana module.
  ApduResponse _handleSolanaApp(ApduCommand command) {
    switch (command.ins) {
      case Ins.solGetVersion: // 0x04
        return _buildSolVersion();
      default:
        return _errorResponse(Sw.insNotSupported);
    }
  }

  /// INS 0xE0 dispatch while the Tron app is open.
  ///
  /// Real Ledger Tron app INS table (`@ledgerhq/hw-app-trx`, CLA 0xE0):
  ///   0x02 GET_ADDRESS · 0x04 SIGN · 0x05 SIGN_HASH · 0x06 VERSION
  ///   0x08 SIGN_MESSAGE
  /// Only the version probe stays here; the rest is served by the Rust Tron
  /// module.
  ApduResponse _handleTronApp(ApduCommand command) {
    switch (command.ins) {
      case Ins.tronGetAppConfiguration: // 0x06 — VERSION / app configuration
        return _buildTronAppConfiguration();
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

  /// Solana GET_VERSION response: [flags(1)] [major] [minor] [patch] + 9000.
  ApduResponse _buildSolVersion() {
    return ApduResponse(
      data: Uint8List.fromList([0x00, 0x01, 0x00, 0x00]),
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
