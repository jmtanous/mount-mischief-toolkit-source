# Public release checklist

This repository is an experimental source preview with fresh history.
Installable releases are still being prepared; no signed download is available.

- [x] MIT for original contributions; upstream notices retained unchanged.
- [x] Exclude private lab history, physical-session evidence and personal device/network identifiers.
- [x] Exclude firmware/sysroot captures, VM images, credentials and generated binaries.
- [ ] Complete the component-level binary license/source compliance review.
- [ ] Freeze versioned release packages and their hashes together.
- [ ] Complete attended Pixel/Polaris acceptance of those exact packages.
- [x] Review the source snapshot and authorize public source-preview publication.
- [ ] Review and authorize the final installable downloads before release.

Default device addresses, disconnected loopback targets and fictional test
coordinates are intentional. They are not private network configuration.

## MMT remaining work

- Supply and back up an owner-controlled release key; missing credentials now fail release builds.
- [x] Public, anonymous catalog chosen; OAuth removed in build 9.
- [ ] Publish reviewed root catalog and release assets; private catalog remains private.
- [x] Distribution chosen: signed APK downloads on GitHub Releases, no Play submission.
- [x] Align the exact bundled runtime, manifest and license notices; build 4 APK inputs verified.
- Confirm redistribution provenance of the remaining Stitch mount illustration; the logo has been replaced with recorded original generated artwork.
- [x] Attended existing-SD flow: helper setup, reinstall preserving settings, startup, webpage, stop and reconnect on build 3.
- [x] Build 4 helper-upgrade regression tested automatically and APK installed.
- [ ] Fresh-SD installation acceptance (owner testing in progress).
- [x] Owner confirmed build 8 LOCATE, rotation, screen-awake and Installed controls.
- [ ] Repeat prior-helper upgrade on physical hardware with build 4.

## Build 9 dependency audit

`DEPENDENCY-NOTICE-REVIEW.json` binds this review to the debug APK SHA-256.
The conservative inventory contains 91 Dart packages and 101 Android dependency
coordinates. Full normalized license texts for 88 Dart entries appear in the APK's
Flutter notices. Flutter SDK subpackages and sky_engine need separate segmented
notice verification; a whole-file mismatch is not evidence of an absent license.
Android POM declarations are recorded, but packaged AAR/JAR notice coverage remains
open. Repeat the audit against the final signed release APK, which has different
debug/runtime contents.

- [ ] Integrate the port's recovered web/font/Rust notices into the runtime and app.
- [ ] Include corresponding source coverage for shipped GCC runtime libraries.
- [ ] Verify Android transitive notices and Flutter SDK aggregated notices.
- [ ] Close the remaining Stitch Polaris artwork provenance/redistribution review.
- [ ] Rebuild and verify the exact final release artifacts after these changes.

No APK or runtime was changed or published by this audit. The port's
`BINARY-DISTRIBUTION.md` records the source-companion gap and pinned inputs.
