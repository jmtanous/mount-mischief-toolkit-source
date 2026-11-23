# Experimental rc.2 release checklist

- [x] MIT original contributions and retained upstream/dependency notices.
- [x] Public source reviewed; private history, SDK captures and credentials excluded.
- [x] Runtime web/font/Rust notices, Android notices and Flutter licenses packaged.
- [x] Chooser artwork provenance matched to the shipped asset.
- [x] Signed build 11, runtime and source companion frozen with SHA-256 checksums.
- [x] Production signer independently backed up; installed APK and signer verified.
- [x] Existing-SD Toolkit helper update and rc.2 upgrade with saved settings.
- [x] Startup/controller connection, webpage, Stop and reconnect on Pixel/Polaris.
- [x] Anonymous catalog and GitHub prerelease distribution selected and authorized.
- [ ] Fresh-SD hardware acceptance (not claimed for this candidate).
- [ ] Standalone port launcher hardware acceptance (separate path).

RELEASE-VALIDATION.json records exact hashes, test scope and known UI limitations.
The full clean port cross-build remains separate from passed public-SDK GCC and
Python component replacement tests. Release assets include their matching source
companion. No Play Store submission, firmware changes or mount-motion testing.
