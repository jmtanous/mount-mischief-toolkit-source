# Building MMT

Development baseline: Flutter 3.50.1 / Dart 3.14, Android SDK 36, JDK 17,
NDK 28.2.13676358. Install Flutter/Android tooling and accept the SDK licenses.
Use `flutter` on PATH or set `FLUTTER_ROOT`; set your Android/JDK environment normally.

## Required local runtime

The source tree intentionally excludes `assets/runtime/pilot.tar.gz`.
Supply the matching runtime from an authorized source and verify its SHA-256:

```
a0e8911e1f40694dbcd79055f9b8d84f714dad503f1eaf4039c2a9f8f13ca734
```

This is the current development runtime, not a promise of a public download.
The port repository contains source recipes, but its latest license-added archive
has a different hash. Do not rename a different archive to bypass this check.
Changing runtime versions requires updating `assets/catalog.json`, `bundleHash`
in `lib/benro.dart`, the manifest digest/sizes, and regenerated license notices as
one reviewed change. Preserve archive safety and integrity checks.

With the matching archive present:

```sh
./scripts/flutter.sh pub get
python3 scripts/collect-runtime-licenses.py
./scripts/flutter.sh analyze
./scripts/flutter.sh test
python3 -B -m unittest discover -s test -p 'test_*.py'
./scripts/flutter.sh build apk --debug
./scripts/test-android.sh
```

`flutter build` generates the Android Gradle wrapper if needed. The debug APK is
for local development. The current release configuration still selects a debug
signing key; configure a dedicated release keystore and verify the signer before
publishing any APK. Keep keys and signing properties out of Git.

## Catalog and OAuth configuration

Use `--dart-define=CATALOG_OWNER=...`, `--dart-define=CATALOG_REPO=...`, and
`--dart-define=GITHUB_CLIENT_ID=...` with a registered GitHub OAuth app supporting
device flow. A client ID is public configuration; never embed a client secret.
The existing private-catalog flow requests the GitHub `repo` scope. Tokens are
stored using Android secure storage. Public-catalog access needs a separate design
review rather than silently reusing broad private-repository authorization.
