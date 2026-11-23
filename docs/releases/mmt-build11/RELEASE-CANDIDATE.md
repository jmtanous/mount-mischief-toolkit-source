# MMT 0.1.0-rc.2 (build 11) — experimental release candidate

This is a production-signed experimental release candidate. The bundled Alpaca Pilot port is 0.1.0-rc.2. Build 11 reads the installed
version/build number in About and Licenses instead of using a hard-coded label.
RELEASE-VALIDATION.json records exact artifacts and test scope. Earlier build
history below is retained for context.

## Final build 11 acceptance

The exact signed APK and rc.2 runtime passed an attended existing-SD upgrade,
Toolkit helper update, all 4,600 installed-file checks, saved observing-site
retention, startup/controller connection, live Pilot webpage, Stop, and reconnect.
Pilot was left stopped. Bluetooth wake passed; Wi-Fi association was selected with
ADB during this acceptance session, not automatic joining by MMT. No firmware,
boot, alignment, slew or tracking actions were performed.

The signing backup is verified. The signed APK, runtime and corresponding source
companion hashes are frozen in RELEASE-VALIDATION.json and the release checksums.
Notices, artwork provenance and signed-APK asset coverage have been reviewed.
The owner authorized experimental GitHub prerelease publication after these tests.

Fresh-SD and standalone-launcher physical acceptance remain open; a complete clean
cross-build of every port dependency is not claimed. These limits are explicit in
the experimental download notes. Earlier preparation entries below are historical;
this section and RELEASE-VALIDATION.json describe the final candidate.

Known UI limitations: an unavailable old-version Reinstall ends the session; use
Catalog → Change version with a verified package for upgrades. After Stop, the
previous connected banner can remain, although the project card correctly shows
Stopped; reconnecting clears it.

## Changes since build 2

- Removed GitHub authentication. Catalog refresh and downloads are anonymous;
  migration clears only retired GitHub credentials and preserves SSH pairing,
  settings and packages. The public catalog is staged locally, not published.
  Bundled/cached installation remains available offline or before publication.
- Distribution target is signed APK downloads through GitHub Releases, not Play.

- A dedicated Pilot browser keeps the page/session through rotation, preserves
  screen-awake and safe-area behavior, routes public map/lookups over validated
  internet, and supplies phone location through Android permission handling.
  Location requests time out/cancel cleanly; IP-based fallback is disabled.
  Mount traffic remains bound to Wi-Fi. No mount runtime or firmware changes.

- Pilot browser content now stays above Android navigation controls and clear of
  display cutouts and the keyboard. The Multi Point Alignment row was verified
  fully visible at the bottom of the Connection page on the connected Pixel.

- Keep screen awake now also applies to the embedded Pilot browser and releases
  when that window goes into the background. Android lifecycle regression tests
  and the settings-screen tests pass.

- Fresh SD cards show “Connected · setup needed,” explain automatic Toolkit setup,
  and link directly to Catalog. Catalog explains that Install sets up Toolkit first.

- Toolkit setup and package installation show a checklist, transfer bytes,
  unpacking and verification counts, and completion or failure states.
- Known compatible older helpers keep installed projects and Stop available.
  Update Toolkit tools becomes available after Pilot stops and other controllers
  disconnect. Missing, mixed or unknown helper sets still require repair.
- The approved clay icon and “It worked before I touched it.” motto remain.

## Validation

Build 9: static analysis is clean; all 110 Flutter tests and 16 Android tests
passed. Coverage includes fresh anonymous refresh, removal of retired credentials
without deleting pairing/package data, unavailable/rate-limited catalogs,
credential-free redirects, checksum failures, interrupted downloads and real
bundled Pilot extraction/verification without network access. Debug APK installed
on the connected Pixel with application data preserved. Public catalog content
is staged locally; no catalog or release publication was performed. The live
Pixel Catalog shows Refresh without sign-in and retains the verified offline
package after the expected unpublished-catalog response. A final message-only
cleanup passed all 3 widget tests.


Build 8: 16 Android tests and 28 Flutter project-workflow tests passed; Flutter
analysis is clean. Debug APK installed preserving data. Live Pixel checks confirmed
map rendering, a fresh native location fix, HTTP 200 and valid payloads from both
Nominatim and Open-Meteo. Location-service testing was explicitly approved and did
not update observing-site settings. Landscape retained the same document time
origin and JavaScript marker; the original automatic rotation mode was restored.
No remote Pilot restart, alignment action, movement, or firmware write was used.


Build 7: all 11 Android tests passed, including browser viewport sizing across
resume, navigation inset changes and keyboard visibility. Debug APK built and
installed preserving app data. Attended visual check confirmed the entire Multi
Point Alignment label and ALIGN button above the navigation bar. No alignment
or movement actions were invoked.

Build 5: Flutter analysis and 108 Flutter tests passed. The helper suite has 37
passing tests. The APK release-input check passes against the pinned FAT runtime,
4,363 manifest files and 113 retained runtime notices. The compatibility tests
cover the exact prior helper set, altered/missing sets and Stop followed by update.

Attended testing of build 3 passed SD helper setup, reinstall with saved settings,
transfer/unpacking/verification cues, Pilot startup, webpage loading, reconnect
and Stop. Pilot was left stopped. The build 4 compatibility fix was tested through
automated regression tests and installed on the Pixel; its old-helper upgrade
sequence has not been repeated on physical hardware. The runtime is unchanged.

Owner confirmed build 8 LOCATE, rotation, screen-awake and Installed controls.
Fresh-SD installation testing is in progress with the owner. It is not yet
accepted. Firmware changes, boot hooks, alignment, tracking and mount motion are
outside these checks. Standalone port hardware acceptance remains separate.

## Before an installable public release

- Complete the fresh-SD test and freeze the exact accepted APK and runtime hashes.
- Select and securely back up an owner-controlled production signer; verify the
  exact final APK certificate. Plan the debug-to-release migration before any
  uninstall or data clearing. See RELEASE-SIGNING.md.
- Resolve compiled web and transitive Rust/native redistribution coverage and
  publish the matching source companion with tested replacement/build guidance.
- Confirm the source and redistribution provenance of the Stitch chooser image.
- Decide public versus invitation-only catalog access, then coordinate its
  manifest and uploaded package hashes. The existing private catalog is unchanged.

Local source commits do not publish binaries, change catalog access or authorize
final release upload. No production APK or public installable release is claimed.

## Build 10 / runtime rc.2 notice update

Build 10 includes all 237 recovered web/font/Rust notices in runtime rc.2 and
MMT's license screen, plus explicit Android artifact notices and complete Flutter
SDK/engine license text. Only two existing runtime notice documents changed;
4,361 existing runtime files are byte-identical and 237 notice files were added.
The manifest, catalog and bootstrap pins were updated together.

Validation: static analysis clean, 110 Flutter tests pass, exact debug APK asset
verification passes, and two independent runtime repacks produce identical bytes.
The source companion includes pinned GCC source and its applied patch; altered
patch input is rejected. Public Debian SDK inputs, a clean GCC rebuild, actual
replacement-library loading and numeric/cryptography operations pass under ARM
QEMU. Modified certifi and pure-Python zeroconf checks also pass on ARM. A clean
cross-build of the entire port and physical testing of newly rebuilt dependencies
remain separate; those experimental libraries are not included in this runtime.

The Stitch provenance receipt matches the shipped chooser image; ARTWORK.md now
records that evidence. The owner authorized production-key creation and migration
of the Pixel from the debug signer. The signed build was installed and its installed
APK hash matched the verified candidate. No mount SD/firmware changes or publication
occurred. Secure key backup and final mount workflow acceptance remain pending.
Public account-free catalog
access is already selected; no GitHub sign-in is required.
