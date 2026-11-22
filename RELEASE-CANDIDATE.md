# MMT 0.1.0-rc.1 (build 7) — local candidate

This is a debug-signed test candidate, not a production release.
The bundled Alpaca Pilot port remains 0.1.0-rc.1.

## Changes since build 2

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
