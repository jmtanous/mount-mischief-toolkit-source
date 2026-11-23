# Mount Mischief Toolkit

Independent Android project manager for compatible field hardware.
**Not affiliated with or endorsed by Benro.** The initial hardware profile is
Benro Polaris; Alpaca Pilot has a dedicated compiled integration. The catalog
selects compatible Beta 8 and 2.2.0 packages independently of MMT.

## Development status

MMT rc.3/build 13 supports verified offline caching, per-address SSH pairing,
SD package management, operation journals and a dedicated Pilot integration.
The APK ships without project archives; catalog-v2 supplies the separate Toolkit
runtime and compatible project versions. Pilot 2.2.0 appears first and is selected
by default. Beta 8 remains available for rollback; both are prerelease packages.

Build 13 passed 120 Flutter tests, 41 helper tests on host and ARM, and
attended stationary installation/start/browser/Stop/rollback checks on Polaris.
Clean installation into an empty Toolkit directory also passed on the existing
SD filesystem. One connection interruption recovered through re-pairing; it did
not recur during a 134-second monitored post-stop repeat, but its cause remains
unresolved. A subsequent installation on an empty 32 GB FAT card also passed
using build 12. No alignment, tracking or observing-accuracy claim is made. See [attended acceptance](docs/ATTENDED-ACCEPTANCE.md) and
[release details](RELEASE-CANDIDATE.md). Historical build 11 evidence is separate.

Firmware modification/restoration, boot integration, automatic updates and
unmanaged-controller takeover are outside this version.

## Downloads and related repositories

- [MMT rc.3/build 13 prerelease](https://github.com/jmtanous/mount-mischief-toolkit-source/releases/tag/v0.1.0-rc.3)
- [Standalone Toolkit runtime](https://github.com/jmtanous/mount-mischief-toolkit-source/releases/tag/toolkit-runtime-v1.0.0)
- [Pilot 2.2.0 port prerelease](https://github.com/jmtanous/alpaca-pilot-polaris-port/releases/tag/v0.2.0-rc.1)
- [Shared Benro development environment](https://github.com/jmtanous/benro-dev-env)

The catalog downloads the required archives; ordinary users do not need to unpack
the runtime manually. Existing build 11 and its legacy catalog remain available.

## User workflow

On each cold launch, review the experimental-use warning, acknowledge the risk,
and choose **Benro Polaris**. The Polaris workspace then guides power-on,
Bluetooth wake, Wi-Fi joining and pairing. Returning from Android settings or
Pilot does not repeat the welcome screen. **Change mount** returns to the chooser
and releases MMT pairing without stopping a running Pilot project.

The optional **Buy me a beer** action appears on Welcome and About. It opens
https://buymeacoffee.com/jmtanousk in the external browser. The destination can
be overridden with `--dart-define=SUPPORT_URL`.
See `docs/APP-DESIGN.md` for configuration and UI verification.

1. Open Catalog. No GitHub account or sign-in is required.
2. Select and download a project version while internet access is available.
   MMT ships without projects. The first download also prepares the separate
   Toolkit runtime; the displayed total includes both uncached archives.
3. If Polaris Wi-Fi is asleep, use **Wake Wi-Fi**, select your mount, then
   join its Wi-Fi through Android settings and pair and inspect it. Bluetooth
   wake and subsequent pairing have passed an attended Pixel check; further
   recovery scenarios remain pending.
   See `docs/BLUETOOTH-WAKE.md` for the flow and attended checklist.
   Confirm its SSH fingerprint on first pairing; later changes are blocked.
   While paired in the foreground, Toolkit keeps idle device Wi-Fi and the phone
   screen awake. **Disconnect** releases this heartbeat. Existing controllers
   keep their own connection; Toolkit does not take them over.
   If setup was interrupted or helpers no longer match this app, use **Repair
   Toolkit setup**. Repair preserves project files/settings and retains a
   replaced runtime for inspection.
4. Install the selected project. Installation does not start it.
5. Start Pilot after reviewing the observing location. Toolkit synchronizes the
   device clock and transfers its temporary heartbeat to Pilot.
6. Tap **Open Pilot** to use its interface inside Toolkit. Press Android Back
   to return to Installed; controls become available after the status refresh.
   Once startup succeeds, Pilot continues running when Toolkit closes.
   Alignment and observing controls remain in Pilot.

The Pilot browser preserves its page when the phone rotates. Mount traffic stays
on Polaris Wi-Fi; public map and site lookup requests use a validated internet
connection, usually mobile data. Maps and name/weather lookups need internet.
**LOCATE** requests the phone's Android location permission and a fresh fix (up to
20 seconds), then uses Nominatim and Open-Meteo for the place name, elevation and
pressure. Those services receive the coordinates. IP-based location fallback is
disabled because it can identify the wrong observing site. If location or internet
is unavailable, a message explains the problem; coordinates can still be entered
manually. User-selected external links open in the phone's normal browser.

Keep Toolkit in the foreground and stay on the device network during operations.
If Toolkit is holding the temporary heartbeat, backgrounding releases it and
requires **Pair and inspect** on return. While Pilot holds its own connection,
Toolkit retains the session and refreshes it on return. A connection error still
requires fresh pairing to reconcile recorded operations before retrying.
An SSH timeout does not prove that remote work stopped.

Toolkit setup and package installation show a stage checklist. Setup names the
runtime and helper steps; transfers show bytes sent. Package installation reports
archive checks, unpacking counts, file verification counts, activation, and the
final status refresh. Counts apply to the current step, not the whole operation.
Keep MMT open and stay connected while installation runs; SD work can take several
minutes. On failure, the checklist retains the failed step and error details stay
available below it. Installation never starts the project automatically.

Reinstall and uninstall always ask whether to keep or delete saved settings.
Reinstall uses the installed version. Other installed projects remain separate;
exclusive resources prevent conflicting projects from starting together.
Existing unmanaged installations are not adopted, overwritten, or removed.

If saved catalog metadata is damaged, Toolkit shows an offline-recovery notice.
Refresh when internet access returns. Existing verified package files are
preserved. Failed transfers discard their incomplete download so a retry can
start cleanly. A fresh offline installation has an empty catalog.

## Build and test

The current development SDK is Flutter 3.50.1 (Dart 3.14), Android SDK 36, JDK 17,
and NDK 28.2.13676358. `scripts/flutter.sh` uses the isolated SDK/cache directory
`../.benro-android-tools`. On another machine, use your own Flutter installation.

```sh
./scripts/flutter.sh pub get
./scripts/flutter.sh analyze
./scripts/flutter.sh test
python -B -m unittest discover -s test -p 'test_*.py'
./scripts/flutter.sh build apk --debug
```

When the existing private ARM lab is available, `scripts/test-arm-vm.sh` runs
the Python suite in its captured userspace. `scripts/test-setup-vm.sh` exercises
the app's actual setup commands, interrupted activation and runtime repair in
a disposable directory in that VM. Neither script contacts physical hardware.

`docs/ANDROID-VALIDATION.md` describes the dedicated Android emulator, verified
offline restart and native settings/browser handoff checks.

To override the public catalog host:

```sh
./scripts/flutter.sh build apk --debug \
  --dart-define=CATALOG_OWNER=jmtanous \
  --dart-define=CATALOG_REPO=mount-mischief-toolkit-source
```

Catalog refresh and release downloads are anonymous. The app fetches
`catalog-v2.json` from the existing public MMT source repository and caches
verified packages for offline installation. The public v2 catalog references
anonymously verified runtime and Pilot release assets and lists newest versions
first. Legacy `catalog.json` remains available for published build 11.

Distribution is through production-signed APKs on GitHub Releases after review.
Google Play submission is not planned. Build source and APKs contain no project
archive. Local archive fixtures are ignored and are only needed for packaging
or integration tests. Do not commit captures, credentials or generated binaries.

## Catalog and package contract

Catalog schema 2 contains `projects` and a separate `runtime` descriptor. Downloads
use immutable GitHub release `asset_id` values with optional `asset_owner` and
`asset_repo`. Requests never include credentials, including redirects. Compatible
project versions share one card with a version selector. New applications need a
dedicated compiled integration and an MMT release; subsequent compatible versions
only need package and catalog updates. See [integration contract](docs/PROJECT-INTEGRATIONS.md).

Packages are gzip tar archives with a pinned `BUNDLE-MANIFEST.json`, containing
regular files/directories only. Every file must appear in the manifest with its
size and SHA-256. Project manifests declare archive size/hash, expanded size,
manifest hash, supported devices, minimum manager schema, adapter, and exclusive
resources. Unknown adapters require a manager update; there are no arbitrary
installation scripts supplied by a catalog entry.

Managed device files live under `/app/sd/mount-mischief-toolkit`. A separate
bootstrap runtime keeps package-management Python available after uninstalling a
project. Each project has independent releases, settings and process identity.
Settings are saved per archive checksum before switching versions. A first-time
upgrade carries settings forward; returning to an installed version restores its
prior settings. Explicitly deleting settings clears all version snapshots.
Old releases are retained until uninstall; abandoned staging directories are
retained for diagnosis rather than guessed at and deleted automatically.

The helper accepts one JSON request on stdin and emits one JSON result. Common
fields are `op`, `project`, and `operation`; reinstall/uninstall require an explicit
boolean `keep_settings`. Supported operations are `list`, `inspect`, `operation`,
`stage`, `install`, `reinstall`, `uninstall`, `start`, `connect`, `stop`, and `logs`.

## Validation boundaries

Local unit tests and full-archive extraction do not establish hardware safety,
physical controller timing, Android network behavior, or observing accuracy.
Attended phone/device validation remains required. Pilot service readiness,
controller connectivity and alignment are reported separately.

## License

Original contributions by Jose Mtanous are licensed under the [MIT License](LICENSE).
Third-party code, dependencies, fonts, and other assets retain their own licenses.
This license does not grant rights to third-party trademarks or imply endorsement.

Downloaded Pilot packages retain their upstream oGecko copyright and license
notices. About & support → Open-source licenses displays MMT, integration, font,
Flutter dependency and Toolkit runtime notices. Runtime notices are collected
from the pinned standalone archive with `python3 scripts/collect-runtime-licenses.py`.

Known compatible older Toolkit helpers keep installed projects and Stop controls available. MMT offers “Update Toolkit tools” after managed projects are stopped and other controllers disconnect. Compatibility requires the complete audited helper set to match; missing, mixed, or unknown helpers still require setup repair.
