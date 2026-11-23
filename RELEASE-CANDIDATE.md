# MMT 0.1.0-rc.3 — build 12 candidate

MMT now ships without projects. Its separately downloaded Toolkit runtime remains
available after a project is removed. Catalog version selection supports immutable
Beta 8 and Pilot 2.2.0 packages, with total uncached download sizes and explicit
MMT/integration compatibility requirements. Pilot has dedicated compiled UI and
lifecycle behavior. Adding another application requires an MMT release; compatible
future versions only require package/catalog changes.

Settings snapshots follow each archive checksum. First-time upgrades carry settings
forward; returning to a prior version restores that version's settings. Explicit
settings deletion clears snapshots. An unavailable old package no longer ends the
paired session, and Stop clears the stale connection banner.

The production-signed local APK contains zero bundled projects. 118 Flutter tests,
41 helper tests on host and ARM, and standalone ARM setup/recovery pass. Exact
artifact and signer evidence is in docs/build12-release-validation.json. These
results do not replace attended testing of this candidate.

The v2 catalog now references published runtime and Pilot assets verified by
anonymous full downloads. Existing public build 11, its legacy catalog and Beta 8
package remain unchanged. See docs/catalog-release-validation.json. Attended existing-SD startup, browser, Stop and settings rollback passed after
connection recovery. Clean-directory standalone runtime installation and a 134-second monitored
post-stop repeat also passed. The earlier recovered drop remains unexplained;
no formatted-card or observing-accuracy claim is made. See docs/ATTENDED-ACCEPTANCE.md.
Prior release evidence is retained under docs/releases/mmt-build11.
