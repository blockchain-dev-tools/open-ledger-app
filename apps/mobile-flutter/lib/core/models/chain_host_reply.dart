import 'dart:typed_data';

/// Host-side result of submitting one frame to a Rust chain app (stage 2b).
///
/// The Rust side answers every call with one of these three shapes; anything
/// it cannot turn into an [ChainHostEmit] or [ChainHostReview] is reported as
/// [ChainHostStatus] so the adapter can fall back to the legacy Dart path.
sealed class ChainHostReply {
  const ChainHostReply();
}

/// Bytes that must be written back to the external wallet verbatim, including
/// the two status-word bytes.
class ChainHostEmit extends ChainHostReply {
  final Uint8List payload;

  const ChainHostEmit(this.payload);
}

/// A review the host must render and park until the user decides.
///
/// `address` is already normalised for display (leading `0x` restored, which
/// the wire protocol strips); `path` is the BIP-32 string form.
class ChainHostReview extends ChainHostReply {
  final int reviewId;
  final String address;
  final String path;
  final String network;

  /// `display_address` or `sign`; decides which confirmation screen the
  /// adapter opens.
  final String actionType;

  /// Raw protocol payload the module attached to the signing operation
  /// (`public_parameters.payload_hex`): the full RLP for a transaction, the
  /// `0x19 0x01 || domain || struct` preimage for EIP-712, empty for messages.
  final String payloadHex;

  /// The full review document as sent by the module. Only `account`,
  /// `sections` and `risks` are populated today.
  final Map<String, dynamic> document;

  const ChainHostReview({
    required this.reviewId,
    required this.address,
    required this.path,
    required this.network,
    required this.actionType,
    required this.payloadHex,
    required this.document,
  });

  bool get isSign => actionType == 'sign';

  /// Content class, taken from the first section's title key.
  String get sectionKind {
    final sections = document['sections'];
    if (sections is List && sections.isNotEmpty) {
      final first = sections.first;
      if (first is Map && first['title_key'] is String) {
        return first['title_key'] as String;
      }
    }
    return '';
  }
}

/// A non-terminal or bookkeeping reply (`locked`, `seed_set`, `opened`,
/// `finished`, `await_input`).
class ChainHostStatus extends ChainHostReply {
  final String kind;
  final String? status;

  const ChainHostStatus(this.kind, {this.status});
}
