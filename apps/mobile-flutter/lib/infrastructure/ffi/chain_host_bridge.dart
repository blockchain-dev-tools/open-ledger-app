import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../core/interfaces/chain_host_service.dart';
import '../../core/models/chain_host_reply.dart';
import 'crypto_bridge.dart';

// ── C signatures (see crates/open-ledger-ffi/src/chain_host.rs) ───────────

typedef _NewHostC = Pointer<Void> Function();
typedef _NewHostDart = Pointer<Void> Function();

typedef _FreeHostC = Void Function(Pointer<Void>);
typedef _FreeHostDart = void Function(Pointer<Void>);

typedef _HostStringC = Pointer<FfiResult> Function(Pointer<Void>, Pointer<Utf8>);
typedef _HostStringDart = Pointer<FfiResult> Function(Pointer<Void>, Pointer<Utf8>);

typedef _HostResolveC = Pointer<FfiResult> Function(Pointer<Void>, Uint64, Uint8);
typedef _HostResolveDart = Pointer<FfiResult> Function(Pointer<Void>, int, int);

typedef _HostVoidC = Pointer<FfiResult> Function(Pointer<Void>);
typedef _HostVoidDart = Pointer<FfiResult> Function(Pointer<Void>);

typedef _DeriveAccountC = Pointer<FfiResult> Function(
    Pointer<Void>, Pointer<Utf8>, Uint32, Uint32);
typedef _DeriveAccountDart = Pointer<FfiResult> Function(
    Pointer<Void>, Pointer<Utf8>, int, int);

typedef _FreeResultC = Void Function(Pointer<FfiResult>);
typedef _FreeResultDart = void Function(Pointer<FfiResult>);

/// FFI implementation of [IChainHostService] over the Rust chain-app runtime.
///
/// Every method degrades to `null`/no-op instead of throwing: a missing symbol
/// or a module error must leave the caller free to use the legacy Dart path.
class ChainHostBridge implements IChainHostService {
  ChainHostBridge() {
    try {
      final lib = CryptoBridge.nativeLibrary;
      _newHost = lib.lookupFunction<_NewHostC, _NewHostDart>('chain_host_new');
      _freeHost = lib.lookupFunction<_FreeHostC, _FreeHostDart>('chain_host_free');
      _setSeed = lib.lookupFunction<_HostStringC, _HostStringDart>('chain_host_set_seed');
      _submit = lib.lookupFunction<_HostStringC, _HostStringDart>('chain_host_submit');
      _resolve = lib.lookupFunction<_HostResolveC, _HostResolveDart>('chain_host_resolve');
      _lock = lib.lookupFunction<_HostVoidC, _HostVoidDart>('chain_host_lock');
      _openAppBridge =
          lib.lookupFunction<_HostStringC, _HostStringDart>('chain_host_open_app');
      _deriveAccountBridge = lib.lookupFunction<_DeriveAccountC, _DeriveAccountDart>(
          'chain_host_derive_account');
      _freeResult = lib.lookupFunction<_FreeResultC, _FreeResultDart>('free_ffi_result');
      _available = true;
    } catch (_) {
      // Older native builds do not export the chain-host symbols; the app then
      // behaves exactly as before the migration.
      _available = false;
    }
  }

  late final _NewHostDart _newHost;
  late final _FreeHostDart _freeHost;
  late final _HostStringDart _setSeed;
  late final _HostStringDart _submit;
  late final _HostResolveDart _resolve;
  late final _HostVoidDart _lock;
  late final _HostStringDart _openAppBridge;
  late final _DeriveAccountDart _deriveAccountBridge;
  late final _FreeResultDart _freeResult;

  bool _available = false;
  Pointer<Void>? _host;
  String? _installedSeed;
  String? _installedModule;

  /// Module the Rust host opens on creation.
  static const defaultModule = 'openledger.ethereum';

  @override
  bool get isAvailable => _available;

  @override
  void setSeed(String? seedHex) {
    if (!_available) return;
    final normalized = (seedHex == null || seedHex.isEmpty) ? '' : seedHex;
    if (normalized == _installedSeed) return;
    // Nothing to clear before the first seed ever reached the host.
    if (normalized.isEmpty && _installedSeed == null) return;
    final host = _ensureHost();
    if (host == null) return;
    final text = normalized.toNativeUtf8();
    try {
      if (_invoke(() => _setSeed(host, text)) != null) {
        _installedSeed = normalized;
      }
    } finally {
      malloc.free(text);
    }
  }

  @override
  void openApp(String moduleId) {
    if (!_available) return;
    if (_installedModule == moduleId) return;
    final host = _ensureHost();
    if (host == null) return;
    final text = moduleId.toNativeUtf8();
    try {
      if (_invoke(() => _openAppBridge(host, text)) != null) {
        _installedModule = moduleId;
      }
    } finally {
      malloc.free(text);
    }
  }

  @override
  ChainHostReply? submit(Uint8List apdu) {
    if (!_available) return null;
    final host = _ensureHost();
    if (host == null) return null;
    final text = CryptoBridge.hexEncode(apdu).toNativeUtf8();
    try {
      final json = _invoke(() => _submit(host, text));
      return json == null ? null : parseReply(json);
    } finally {
      malloc.free(text);
    }
  }

  @override
  Uint8List? resolve(int reviewId, {required bool approved}) {
    if (!_available) return null;
    final host = _ensureHost();
    if (host == null) return null;
    final json = _invoke(() => _resolve(host, reviewId, approved ? 1 : 0));
    if (json == null) return null;
    final reply = parseReply(json);
    return reply is ChainHostEmit ? reply.payload : null;
  }

  @override
  ChainAccountMaterial? deriveAccount(
    String moduleId, {
    int accountProfileIndex = 0,
    required int addressIndex,
  }) {
    if (!_available) return null;
    final host = _ensureHost();
    if (host == null) return null;
    final text = moduleId.toNativeUtf8();
    try {
      final json = _invoke(() =>
          _deriveAccountBridge(host, text, accountProfileIndex, addressIndex));
      if (json == null) {
        // The Rust side may have switched modules before failing; force the
        // next APDU to re-open explicitly.
        _installedModule = null;
        return null;
      }
      _installedModule = moduleId;
      final material = parseAccountMaterial(json);
      debugPrint('[CHAIN HOST] derive $moduleId#$addressIndex → '
          '${material?.address ?? 'fallback'}');
      return material;
    } finally {
      malloc.free(text);
    }
  }

  @override
  void lock() {
    if (!_available) return;
    final host = _host;
    if (host == null) return;
    _invoke(() => _lock(host));
    _installedSeed = '';
  }

  /// Releases the native handle. Seed material is cleared inside Rust.
  void dispose() {
    final host = _host;
    _host = null;
    _installedSeed = null;
    _installedModule = null;
    if (host != null && _available) {
      _freeHost(host);
    }
  }

  Pointer<Void>? _ensureHost() {
    final existing = _host;
    if (existing != null) return existing;
    final created = _newHost();
    if (created == nullptr) return null;
    _host = created;
    // `chain_host_new` opens the ETH module; keep the mirror in sync.
    _installedModule = defaultModule;
    return created;
  }

  /// Runs one exported call and returns its JSON payload, or `null` on error.
  String? _invoke(Pointer<FfiResult> Function() call) {
    Pointer<FfiResult> result;
    try {
      result = call();
    } catch (_) {
      return null;
    }
    if (result == nullptr) return null;
    final view = result.ref;
    final failed = view.errorCode != 0;
    final String? data;
    if (failed) {
      data = null;
    } else if (view.data == nullptr) {
      data = '';
    } else {
      data = view.data.toDartString();
    }
    _freeResult(result);
    return data;
  }

  /// Maps one host reply (single-line JSON) onto the Dart reply types.
  ///
  /// Exposed so the mapping can be unit-tested without loading native code.
  /// Returns `null` for malformed input or a review without an address, which
  /// the caller treats as "fall back to the legacy path".
  static ChainHostReply? parseReply(String json) {
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    switch (map['kind']) {
      case 'emit':
        final payload = map['payload'];
        if (payload is! String) return null;
        return ChainHostEmit(CryptoBridge.hexToBytes(payload));
      case 'review':
        final document = map['document'];
        final action = map['action'];
        final reviewId = map['review_id'];
        if (document is! Map<String, dynamic> || reviewId is! int) return null;
        final address = _displayAddress(document);
        if (address.isEmpty) return null;
        final path = action is Map && action['path'] is String
            ? action['path'] as String
            : "m/44'/60'/0'/0/0";
        final actionType =
            action is Map && action['type'] is String ? action['type'] as String : '';
        final network = document['network'];
        return ChainHostReview(
          reviewId: reviewId,
          address: address,
          path: path,
          network: network is Map && network['name'] is String
              ? network['name'] as String
              : 'Ethereum',
          actionType: actionType,
          payloadHex: _payloadHex(action),
          document: document,
        );
      default:
        return ChainHostStatus(
          map['kind'] is String ? map['kind'] as String : 'unknown',
          status: map['status'] is String ? map['status'] as String : null,
        );
    }
  }

  /// `public_parameters.payload_hex` of the first signing operation.
  static String _payloadHex(Object? action) {
    if (action is! Map) return '';
    final operations = action['operations'];
    if (operations is! List || operations.isEmpty) return '';
    final first = operations.first;
    final parameters = first is Map ? first['public_parameters'] : null;
    if (parameters is Map && parameters['payload_hex'] is String) {
      return parameters['payload_hex'] as String;
    }
    return '';
  }

  /// Maps the `local` reply of `chain_host_derive_account` onto the account
  /// material. Returns `null` when the module refused (empty payload).
  ///
  /// Exposed for unit tests, like [parseReply].
  static ChainAccountMaterial? parseAccountMaterial(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      if (map['kind'] != 'local') return null;
      final payload = map['payload'];
      if (payload is! String || payload.isEmpty) return null;
      final inner = jsonDecode(utf8.decode(CryptoBridge.hexToBytes(payload)))
          as Map<String, dynamic>;
      final address = inner['address'];
      final publicKey = inner['public_key'];
      if (address is! String || address.isEmpty) return null;
      if (publicKey is! String) return null;
      return ChainAccountMaterial(address: address, publicKeyHex: publicKey);
    } catch (_) {
      return null;
    }
  }

  /// The wire form carries 40 hex characters for ETH; other chains already use
  /// their own encoding (base58, bech32, `0x`-hex) and must pass through.
  static String _displayAddress(Map<String, dynamic> document) {
    final account = document['account'];
    if (account is String && account.isNotEmpty) {
      return _normalizeAddress(account);
    }
    final sections = document['sections'];
    if (sections is List) {
      for (final section in sections) {
        final fields = section is Map ? section['fields'] : null;
        if (fields is! List) continue;
        for (final field in fields) {
          final value = field is Map ? field['value'] : null;
          if (value is Map && value['type'] == 'address') {
            final raw = value['value'];
            if (raw is String && raw.isNotEmpty) {
              return _normalizeAddress(raw);
            }
          }
        }
      }
    }
    return '';
  }

  static String _normalizeAddress(String raw) {
    final isWireHex = RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(raw);
    return isWireHex ? '0x$raw' : raw;
  }
}
