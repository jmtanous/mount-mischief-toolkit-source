# Public release checklist

This repository is a local source candidate with fresh history. It contains no
remote configuration and has not been published. No signed download is promised.

- [x] MIT for original contributions; upstream notices retained unchanged.
- [x] Exclude private lab history, physical-session evidence and personal device/network identifiers.
- [x] Exclude firmware/sysroot captures, VM images, credentials and generated binaries.
- [ ] Complete the component-level binary license/source compliance review.
- [ ] Freeze versioned release packages and their hashes together.
- [ ] Complete attended Pixel/Polaris acceptance of those exact packages.
- [ ] Review the final source and downloads, then explicitly authorize publication.

Default device addresses, disconnected loopback targets and fictional test
coordinates are intentional. They are not private network configuration.

## MMT remaining work

- Configure protected release signing; current Gradle release config still uses debug signing.
- Choose public versus invitation-only catalog access and corresponding OAuth behavior.
- Supply the exact ignored runtime or deliberately update all pins and license notices.
- Confirm redistribution provenance of the Stitch-derived logo and mount artwork.
- Test wake, Wi-Fi association, pairing, install, start, webpage, stop and reconnect.
