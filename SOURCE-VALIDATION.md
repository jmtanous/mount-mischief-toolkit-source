# Source validation — build 12

An isolated checkout based on the existing public repository builds a debug APK
without any project or Toolkit runtime archive. Its APK and the production-signed
candidate both pass verify-release-inputs.py with zero bundled projects. The
production signer matches build 11. All 118 Flutter tests and analysis pass.

The optional ARM lab also passed standalone setup/recovery and actual Beta 8 →
2.2.0 → Beta 8 install/settings rollback. See docs/integration-validation.json.
These checks do not constitute attended phone/mount acceptance. Published build
11 evidence is preserved under docs/releases/mmt-build11.
