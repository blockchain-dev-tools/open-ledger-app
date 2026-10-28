import 'dart:typed_data';

import '../models/chain_host_reply.dart';

/// One locally derived account: display address plus the chain's real public
/// key (uncompressed 65B for ETH/Tron, compressed 33B for BTC, Ed25519 32B for
/// Solana/Sui).
class ChainAccountMaterial {
  const ChainAccountMaterial({required this.address, required this.publicKeyHex});

  final String address;
  final String publicKeyHex;
}

/// Host bridge for the Rust chain-app runtime (stage 2b).
///
/// Only commands already migrated are routed here; the caller keeps using the
/// legacy Dart implementation whenever a call returns `null` (binding missing,
/// module error, or a reply shape the adapter does not handle). That fallback
/// is what makes the migration incremental instead of a flag day.
abstract class IChainHostService {
  /// Whether the native binding is usable. `false` on platforms or builds
  /// where the symbol was not linked.
  bool get isAvailable;

  /// Hands the seed to the Rust side (it never comes back). Passing `null` or
  /// an empty string locks the host and clears the key material.
  void setSeed(String? seedHex);

  /// Switches the active module (Ledger "open app"). No-op when the requested
  /// module is already open.
  void openApp(String moduleId);

  /// Submits one complete APDU. Returns `null` to request the legacy path.
  ChainHostReply? submit(Uint8List apdu);

  /// Resolves a parked review. Returns the bytes to send to the wallet, or
  /// `null` when the host could not produce a terminal response.
  Uint8List? resolve(int reviewId, {required bool approved});

  /// Derives the local account `addressIndex` of the module's first account
  /// profile (`LocalCommand::DeriveAccount`). Returns `null` to fall back to
  /// the legacy Dart derivation.
  ChainAccountMaterial? deriveAccount(
    String moduleId, {
    int accountProfileIndex = 0,
    required int addressIndex,
  });

  /// Drops the seed and invalidates every pending approval.
  void lock();
}
