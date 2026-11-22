# Building MMT

Development baseline: Flutter 3.50.1 / Dart 3.14, Android SDK 36, JDK 17,
NDK 28.2.13676358. Install Flutter/Android tooling and accept the SDK licenses.
Use `flutter` on PATH or set `FLUTTER_ROOT`; set your Android/JDK environment normally.

## Required local runtime

The source tree intentionally excludes `assets/runtime/pilot.tar.gz`.
Supply the matching runtime from an authorized source and verify its SHA-256:

```
dae7501b5a97ff3bcf0840496a724fc3e75c1c8b3747832651938373989a2b2d
```

This is the current development runtime, not a promise of a public download.
This pin matches port candidate 0.1.0-rc.1, including the standalone native
bootstrap and source-availability notice. Do not rename a different archive to bypass this check.
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
for local development. Release builds require explicit owner signing credentials and fail if they are
missing. See [release signing](RELEASE-SIGNING.md). Keep keys out of Git.

## Public catalog configuration

The default public repository is `jmtanous/mount-mischief-toolkit-source`.
Override it with `--dart-define=CATALOG_OWNER=...` and
`--dart-define=CATALOG_REPO=...`. No OAuth registration, client ID or token is used.
Catalog and release-asset requests are anonymous; the repository must be public.

The root `catalog.json` is staged for publication and currently matches the
bundled Pilot entry, without a remote asset ID. Once reviewed runtime packages
are uploaded as public release assets in this repository, add their actual
`asset_id` values while preserving the pinned hashes and sizes. Never substitute
private-repository asset IDs. Until publication, bundled/cached packages work
and refresh reports an unavailable public catalog without requiring sign-in.

Updates delete only the retired `github_session` and `github_token` keys.
Secure storage remains required for SSH pairing identities. The GitHub OAuth
registration itself is not revoked or changed by this migration.

Release distribution is signed APKs plus checksums on GitHub Releases, not
Google Play. Production signing, key backup, license review and final artifact
acceptance remain prerequisites; see RELEASE-CHECKLIST.md.

Verify the runtime, catalog, notices and final APK together with:

```sh
python3 scripts/verify-release-inputs.py --apk build/app/outputs/flutter-apk/app-debug.apk
```
