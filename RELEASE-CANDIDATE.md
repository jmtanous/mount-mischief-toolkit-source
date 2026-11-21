# MMT 0.1.0-rc.1 (build 2) — local candidate

Includes the approved clay-mount icon and “It worked before I touched it.” motto,
plus the aligned port 0.1.0-rc.1 FAT runtime, catalog metadata and 113 runtime notices.
The unused old Stitch emblem is removed. The separate Polaris chooser artwork is
unchanged and still needs redistribution-provenance review.

`python3 scripts/verify-release-inputs.py --apk <debug-apk>` checks the bootstrap pin,
catalog archive/manifest hashes and sizes, complete manifest, port version, FAT-safe
archive shape, notice content and the exact runtime/catalog/artwork in the built APK.

Release Gradle tasks require the owner's keystore environment variables and never
fall back to debug signing. See RELEASE-SIGNING.md. The current local APK is a debug
build; it is not a signed production release. The release key is not generated.

The private online catalog is unchanged. Its contents may differ from the bundled
candidate; the prepared local catalog must be coordinated with any future uploaded
runtime before distribution. No access policy or OAuth scope is changed here.

## When the owner returns

Use the exact APK/runtime recorded in the preparation checksums. Verify Bluetooth
wake after Wi-Fi sleeps, join-network indication, SSH identity and pairing, install,
settings preservation, startup checklist (allow three minutes), Pilot webpage, stop
and reconnect. Do not mix standalone and MMT controller ownership. A future release
signer differs from the installed debug signer; plan settings migration before any
uninstall. No automatic app-data clearing is authorized by these notes.

Physical acceptance, signer setup, chooser-artwork provenance, remaining dependency
redistribution review and coordinated binary/catalog publication remain separate.
No physical device test or binary publication is claimed for unattended preparation.
