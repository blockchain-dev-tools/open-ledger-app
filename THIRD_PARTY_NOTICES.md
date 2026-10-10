# Third-party notices

The root MIT license covers project-authored code, subject to the original notices. It does not replace third-party licenses or grant rights to trademarks.

## Bundled fonts

`apps/mobile-flutter/assets/fonts/NotoSansCJK-Subset-{Regular,Medium,Bold}.ttf` are subset derivatives of Noto Sans CJK SC 2.004. Embedded font metadata identifies Copyright © 2014–2021 Adobe and the SIL Open Font License 1.1. Noto is a Google trademark; these subsets are not endorsed by the upstream authors.

The full upstream license is retained in [OFL.txt](apps/mobile-flutter/assets/fonts/OFL.txt), obtained from the [official Noto CJK source](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE). Keep this license and the embedded copyright notices with redistributed fonts. The subsetting script is `apps/mobile-flutter/tool/gallery/fonts/subset_cjk.py`.

## Runtime and development dependencies

Flutter/Dart dependencies and versions are recorded in `apps/mobile-flutter/pubspec.lock`; Rust crates in `crates/Cargo.lock`; independent E2E dependencies in root `pnpm-lock.yaml`. Their upstream license files remain part of installed distributions. Before distributing an APK, generate and inspect the license inventory for the resolved dependency graph and retain any notices required by those packages. Lockfiles are reproducibility inputs, not a complete notice inventory.

The host verifier uses `@noble/curves`, `@noble/hashes`, `@scure/bip32`, `@scure/bip39`, and transitive `@scure/base`. Their exact upstream MIT notices are retained in [LICENSES/](LICENSES/).

## Icons and names

Chain and product marks identify the supported protocols and application. The snapshot retains existing SVG/image resources; their original provenance and redistribution terms still require verification before an official asset or APK release. The project MIT license should not be interpreted as a license to third-party logos. Replace any asset whose provenance cannot be established.

Ledger, Ledger Nano X, chain names and host-wallet names are used for identification and compatibility discussion only. Their owners retain their rights; there is no implied sponsorship or security certification.
