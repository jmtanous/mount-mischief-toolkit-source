# Local candidate validation

2026-11-21, MMT 0.1.0-rc.1 (build 2):

- Flutter analysis: no issues; full suite: 98 passed.
- Python helper suite: 34 passed; Android unit suite: 8 passed.
- Clean debug APK build passed; APK signature verifies as Android Debug.
- Missing release credentials fail release builds, with no debug fallback.
- Runtime/catalog/archive/manifest/version/notice checks passed, including exact
  runtime, catalog, license registry and artwork bytes inside the APK.
- New icon/welcome motto were previously inspected on the Pixel. The subsequent
  runtime candidate has not been installed or physically tested unattended.
- Runtime binaries and test outputs remain ignored. The public checkout contains
  source, recipes and notices only. Changes are local and have not been pushed.

See RELEASE-CANDIDATE.md and RELEASE-SIGNING.md for handoff requirements.
