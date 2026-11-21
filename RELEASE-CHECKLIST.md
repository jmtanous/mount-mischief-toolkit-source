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
- Choose public versus invitation-only catalog access and corresponding OAuth behavior.
- Supply the exact ignored runtime or deliberately update all pins and license notices.
- Confirm redistribution provenance of the remaining Stitch mount illustration; the logo has been replaced with recorded original generated artwork.
- Test wake, Wi-Fi association, pairing, install, start, webpage, stop and reconnect.
