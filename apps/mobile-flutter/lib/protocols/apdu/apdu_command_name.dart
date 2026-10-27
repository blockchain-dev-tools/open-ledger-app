/// Human-readable names for APDU commands and status words.
///
/// Reuses the `Cla`, `Ins`, and `Sw` constants from [apdu_constants] so the
/// mapping stays in sync with the protocol definitions. Used by the BLE log
/// viewer to translate raw APDU bytes into a readable command name.
library;

import 'dart:typed_data';

import 'apdu_constants.dart';

/// Maps the first bytes of an APDU command (CLA + INS) to a readable name.
///
/// Returns a fallback like `UNKNOWN (CLA 0xE0 INS 0x42)` for unmapped codes.
String apduCommandName(Uint8List apdu) {
  if (apdu.length < 2) {
    return 'UNKNOWN (too short: ${apdu.length} bytes)';
  }

  final cla = apdu[0];
  final ins = apdu[1];

  // CLA 0xb0 — global / OS-level commands.
  if (cla == Cla.global) {
    if (ins == Ins.getVersion) return 'GET_APP_AND_VERSION';
    return _unknown(cla, ins);
  }

  // CLA 0xe0 — OS commands + Ethereum app + Solana app.
  // NOTE: INS names here assume the active app (set by OPEN_APP); bytes
  // 0x04/0x06 overlap between the two apps. The log layer has no app
  // context, so Ethereum names are used by default.
  if (cla == Cla.os) {
    switch (ins) {
      case Ins.openApp:
        return 'OPEN_APP';
      case Ins.quitApp:
        return 'QUIT_APP';
      case Ins.getVersion:
        return 'GET_VERSION'; // (Solana app: no 0x01; ETH app only)
      case Ins.getPublicKey:
        return 'GET_PUBKEY';
      case Ins.ethSign:
        // P1=0x02/0x42 carry an inline EIP-712 payload (path + domain hash +
        // struct hash); everything else is a legacy/typed RLP transaction.
        if (apdu.length >= 3 && (apdu[2] == 0x02 || apdu[2] == 0x42)) {
          return 'ETH_SIGN_EIP712'; // (Solana app: GET_VERSION)
        }
        return 'ETH_SIGN_TX'; // (Solana app: GET_VERSION)
      case Ins.getAppConfiguration:
        return 'GET_APP_CONFIGURATION'; // (Solana app: SIGN)
      case Ins.signEthPersonalMessage:
        return 'ETH_SIGN_PERSONAL_MESSAGE';
      case Ins.ethProvideErc20TokenInfo:
        return 'ETH_PROVIDE_ERC20_TOKEN_INFO'; // (was wrongly SOL_SIGN_MESSAGE)
      case Ins.solGetAddress:
        return 'SOL_GET_ADDR';
      case Ins.ethSignEip712:
        return 'ETH_SIGN_EIP712';
    }
    return _unknown(cla, ins);
  }

  // CLA 0xe1 / 0xf8 — Bitcoin.
  if (cla == Cla.bitcoin || cla == Cla.bitcoinExt) {
    switch (ins) {
      case Ins.btcGetWalletPublicKey:
        return 'BTC_GET_WALLET_PUBKEY';
      case Ins.btcSignTx:
        return 'BTC_SIGN_TX';
    }
    return _unknown(cla, ins);
  }

  // CLA 0x14 — Tron.
  if (cla == Cla.tron) {
    switch (ins) {
      case Ins.tronGetPublicKey:
        return 'TRON_GET_PUBKEY';
      case Ins.tronSignTx:
        return 'TRON_SIGN_TX';
    }
    return _unknown(cla, ins);
  }

  // CLA 0x07 — Sui.
  if (cla == Cla.sui) {
    switch (ins) {
      case Ins.suiGetPublicKey:
        return 'SUI_GET_PUBKEY';
      case Ins.suiSignTx:
        return 'SUI_SIGN_TX';
    }
    return _unknown(cla, ins);
  }

  return _unknown(cla, ins);
}

/// Maps a 16-bit status word (SW1 << 8 | SW2) to a readable name.
///
/// Returns `SW 0xXXXX` for unmapped codes.
String swName(int sw) {
  switch (sw) {
    case Sw.success:
      return 'SUCCESS';
    case Sw.conditionsNotSatisfied:
      return 'REJECTED';
    case Sw.executionError:
      return 'TIMEOUT';
    case Sw.securityStatusNotSatisfied:
      return 'PIN_NOT_VERIFIED';
    case Sw.wrongData:
      return 'WRONG_DATA';
    case Sw.fileNotFound:
      return 'FILE_NOT_FOUND';
    case Sw.incorrectP1P2:
      return 'WRONG_P1P2';
    case Sw.wrongDataLength:
      return 'WRONG_LC';
    case Sw.insNotSupported:
      return 'INS_NOT_SUPPORTED';
    case Sw.claNotSupported:
      return 'CLA_NOT_SUPPORTED';
    case Sw.unknownError:
      return 'UNKNOWN_ERROR';
    default:
      return 'SW 0x${sw.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }
}

String _unknown(int cla, int ins) {
  final claHex = cla.toRadixString(16).toUpperCase().padLeft(2, '0');
  final insHex = ins.toRadixString(16).toUpperCase().padLeft(2, '0');
  return 'UNKNOWN (CLA 0x$claHex INS 0x$insHex)';
}
