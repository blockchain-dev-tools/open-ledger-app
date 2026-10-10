import 'package:open_ledger_app/services/mnemonic_service.dart';

import 'fake_crypto_service.dart';
import 'sample_enigma.dart';

/// Gallery [MnemonicService] — no FFI, no Rust.
///
/// Delegates to [FakeCryptoService] for the onboarding screens, and overrides
/// Enigma derivation with the fixed 24-word sample so the stand-in wizard's
/// Enigma path walks through on web (where the Rust SDK is unavailable).
MnemonicService createFakeMnemonicService() => _GalleryMnemonicService();

class _GalleryMnemonicService extends MnemonicService {
  _GalleryMnemonicService() : super(crypto: FakeCryptoService());

  @override
  List<String> generateEnigmaMnemonic(
    String riddle,
    String secret, {
    int language = 0,
  }) =>
      sampleEnigmaWords;
}
