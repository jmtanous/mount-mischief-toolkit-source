# Source validation — build 13

An isolated checkout based on the existing public repository builds a debug APK
without any project or Toolkit runtime archive. Its APK and the production-signed
candidate both pass verify-release-inputs.py with zero bundled projects. The
production signer matches build 11. All 120 Flutter tests and analysis pass for build 13. Its functional source
matches the reviewed public checkout byte for byte. The earlier isolated
archive-free build check was performed on build 12; build 13 changes version
selection only and retains the same archive-free build inputs.

The optional ARM lab also passed standalone setup/recovery and actual Beta 8 →
2.2.0 → Beta 8 install/settings rollback. See docs/integration-validation.json.
These checks do not constitute attended phone/mount acceptance. Published build
11 evidence is preserved under docs/releases/mmt-build11.
