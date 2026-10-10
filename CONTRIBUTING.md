# Contributing

Read the [product contract](docs/product/contract.md), [architecture rules](AGENTS.md) and [build instructions](BUILDING.md) before changing behavior.

Use issues for ordinary bugs and proposals. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md). Never include a real seed, PIN, passphrase, signing key, wallet storage dump, personal device identifier or credential in an issue, patch, screenshot or log.

## Development

Keep Rust as the device cryptography source of truth. Maintain the Flutter layer boundaries in `AGENTS.md`. Use existing color/radius tokens, localization strings, and stable `ValueKey`s for interactive widgets. Preserve wallet derivation and Enigma output bytes when refactoring.

For a behavior change, update the public contract, add meaningful unit coverage using core interfaces, and add or extend a real-device E2E case. Do not make unit tests depend on an Android device or Rust shared library. The APDU corpus at `spec/apdu/` distinguishes implementation regression snapshots from independently captured firmware conformance evidence.

Run the checks appropriate to the change: Rust tests, Flutter analysis/unit tests, a gallery web build for UI mock changes, and device tests for BLE/APDU or user-visible flows. State which checks ran, their environment, and any skipped native/device coverage in the PR. Existing security gaps must not be described as verified guarantees.

## Pull requests and publication

Describe the concrete behavior changed and its validation. Keep dependency updates and security fixes reviewable separately from unrelated layout or migration work. Include upstream notices when adding fonts, icons or code.

Before each commit, review both staged filenames and staged content. Before publishing, review every reachable commit and its author/committer identity, messages, tags and attached artifacts. This repository requires GitHub noreply author/committer/tagger emails (`...@users.noreply.github.com` or `noreply@github.com`); local global Git configuration may otherwise expose a personal email. Configure the public identity locally before committing. Ignore rules do not remove already-tracked content. Removing a credential in a later commit does not remove it from history: revoke it and replace the unpublished history before pushing.

Do not publish debug/release logs, generated native libraries, build caches, local SDK paths, signing material or internal planning documents. Public test seeds must be clearly identified as known test vectors and must never receive real funds.

Run the publication guard after staging and again across the complete history before pushing:

```bash
python3 -m unittest discover -s scripts/tests
python3 scripts/check-publication.py
python3 scripts/check-publication.py --history
```

The index guard checks exactly staged files. `--history` inspects every reachable commit and annotated tag, including identity metadata. CI also runs a redacted all-history secret scan. Automated scans supplement manual review; they cannot distinguish every real wallet secret from legitimate vectors.
