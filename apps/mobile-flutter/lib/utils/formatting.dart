import '../core/models/chain.dart';
import '../generated/l10n/app_localizations.dart';

/// Shared formatting utilities used across multiple screens.
///
/// Consolidates duplicated chain labels/icons and Ethereum unit
/// conversions that were previously copy-pasted across 4 screens.

/// Localized display label for a chain id.
///
/// Chain identity (icons, derivation paths, Ledger app names) lives in the
/// [Chain] registry; only the human-readable name is language-dependent, so
/// it is resolved here from l10n. Pseudo-chains that appear in signing
/// history (`'personal_msg'`, `'eip712'`) have their own labels; anything
/// unrecognized falls back to the raw id.
extension ChainLabelL10n on AppLocalizations {
  String chainLabel(String chainId) {
    final chain = Chain.fromId(chainId);
    if (chain != null) {
      return switch (chain) {
        Chain.ethereum => chainEthereum,
        Chain.solana => chainSolana,
        Chain.bitcoin => chainBitcoin,
        Chain.tron => chainTron,
        Chain.sui => chainSui,
      };
    }
    return switch (chainId) {
      'personal_msg' => chainPersonalMessage,
      'eip712' => chainEip712,
      _ => chainId,
    };
  }
}

/// SVG asset path for a chain id.
///
/// Unknown or pseudo ids fall back to the Ethereum icon, matching the
/// previous behaviour for ids the app does not recognize.
String chainIconAssetPath(String chainId) =>
    Chain.fromId(chainId)?.iconAssetPath ?? Chain.ethereum.iconAssetPath;

/// The account number encoded in a BIP-32 / SLIP-10 [path].
///
/// Reads the **last** path component, not a list position: a list of
/// `[eth#0, eth#1, sol#0]` must label its rows 0/1/0, not 0/1/2.
int accountIndexInPath(String path) {
  final match = RegExp(r"(\d+)'?$").firstMatch(path);
  return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
}

/// Convert a wei decimal string to an ETH display string.
///
/// Example: "1000000000000000000" → "1"
///          "1234567890123456789" → "1.234567890123456789"
String weiToEth(String wei) {
  if (wei == '0' || wei.isEmpty) return '0';
  // Pad to at least 19 chars (1 ETH = 10^18 wei)
  final padded = wei.padLeft(19, '0');
  final intPart = padded.substring(0, padded.length - 18);
  final decPart = padded.substring(padded.length - 18);
  // Trim trailing zeros
  final trimmed = decPart.replaceAll(RegExp(r'0+$'), '');
  final dec = trimmed.isEmpty ? '' : '.$trimmed';
  return '$intPart$dec';
}

/// Convert a wei decimal string to a Gwei display string.
///
/// Example: "1000000000" → "1"
String weiToGwei(String wei) {
  if (wei == '0' || wei.isEmpty) return '0';
  final padded = wei.padLeft(10, '0');
  final intPart = padded.substring(0, padded.length - 9);
  final decPart = padded.substring(padded.length - 9);
  // Trim trailing zeros
  final trimmed = decPart.replaceAll(RegExp(r'0+$'), '');
  final dec = trimmed.isEmpty ? '' : '.$trimmed';
  return '$intPart$dec';
}
