/// A single parsed BLE log entry.
///
/// The heavy parsing lives in `ApduLogDecoder` (protocols/apdu); this is the
/// plain data model consumed by the BLE log viewer.
library;

/// Severity inferred from the log message text.
enum BleLogLevel { info, warn, error }

/// Lifecycle status of a response row. `sending` becomes a [pending]
/// placeholder that gets replaced in-place when the matching `sent`
/// ([success]) or `send error` ([error]) line arrives.
enum BleLogStatus { idle, pending, success, error }

/// One row in the BLE log viewer.
class BleLogEntry {
  /// Short translated label shown on the collapsed row (e.g.
  /// `APDU command received: GET_PUBKEY path=44'/60'/0'/0/0`).
  final String summary;

  /// Raw line revealed when the row is expanded, or `null` if the line is
  /// not expandable (plain status messages / pending placeholder).
  final String? detail;

  /// Inferred severity, used for row coloring.
  final BleLogLevel level;

  /// Lifecycle status — tells the viewer whether to append, hold as
  /// pending, or replace the pending row.
  final BleLogStatus status;

  /// The original raw log line.
  final String raw;

  const BleLogEntry({
    required this.summary,
    required this.detail,
    required this.level,
    required this.status,
    required this.raw,
  });

  BleLogEntry copyWith({
    String? summary,
    String? detail,
    BleLogLevel? level,
    BleLogStatus? status,
    String? raw,
  }) =>
      BleLogEntry(
        summary: summary ?? this.summary,
        detail: detail ?? this.detail,
        level: level ?? this.level,
        status: status ?? this.status,
        raw: raw ?? this.raw,
      );
}
