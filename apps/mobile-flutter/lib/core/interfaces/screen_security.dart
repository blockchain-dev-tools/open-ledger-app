/// OS-level screen-capture control for the secret-display envelope
/// (ADR-011 §6).
///
/// Abstract so the screens depend on the contract rather than on an Android
/// method channel; targets without the flag (web, iOS) implement it as a
/// no-op.
abstract class IScreenSecurity {
  /// Block screenshots, screen recording and the recents thumbnail.
  Future<void> enable();

  /// Lift the block once the secret has left the screen.
  Future<void> disable();
}
