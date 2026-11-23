# Building MMT

Use Flutter 3.50.1 / Dart 3.14, Android SDK 36, JDK 17 and NDK 28.2.13676358.
Install Flutter on PATH or set FLUTTER_ROOT. A shared local tool installation can
also be selected with MMT_TOOLS_DIR. Configure Android/JDK normally.

No project archive or downloaded runtime is required to build the APK:

```sh
./scripts/flutter.sh pub get
./scripts/flutter.sh analyze
./scripts/flutter.sh test
python3 -B -m unittest discover -s test -p 'test_*.py'
./scripts/flutter.sh build apk --debug
python3 scripts/verify-release-inputs.py --apk build/app/outputs/flutter-apk/app-debug.apk
```

Release builds use the existing owner-controlled key and fail if credentials are
missing. See RELEASE-SIGNING.md. Keep keys and generated binaries out of Git.

The app ships the pinned Toolkit runtime metadata and compiled integrations.
Project packages and the runtime are downloaded independently from catalog-v2.json.
A new application needs an MMT integration/release. Compatible later application
versions need only an immutable package and a catalog entry. Legacy catalog.json
continues to serve published build 11. The v2 candidate remains unpublished until
its runtime and new Pilot asset IDs are verified.

To regenerate runtime notices, supply the hash-matching standalone runtime with
`python3 scripts/collect-runtime-licenses.py --archive /path/to/toolkit-runtime-1.0.0.tar.gz`.
The generated notice registry is committed, so normal source builds do not need
that archive. scripts/package-toolkit-runtime.py creates the runtime from the
verified Beta 8 rc.2 package; scripts/package-runtime-sources.py adds its extraction
recipe to the port's verified source companion. These are packaging inputs only.

Optional tests under test_lab require the separate local ARM environment and
real archives. scripts/test-setup-vm.sh tests standalone setup/recovery;
scripts/test-versions-vm.sh tests full Beta 8/2.2.0 installation and settings rollback.
They never target a physical device. Guest tests do not certify hardware timing,
Wi-Fi behavior or observing accuracy. No public upload or installation is implied.
