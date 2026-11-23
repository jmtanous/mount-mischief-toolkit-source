# MMT 0.1.0-rc.3 — build 13

MMT ships without projects. Its separately downloaded Toolkit runtime remains
available after a project is removed. The public catalog offers Pilot 2.2.0 first
and selects the newest compatible release by default. Beta 8 remains available
for rollback. An explicit version choice survives catalog refresh.

Pilot has dedicated compiled UI and lifecycle behavior. Adding another project
requires an MMT release; compatible future project versions require only package
and catalog updates. Settings snapshots follow each archive checksum. First-time
upgrades carry settings forward; returning to a prior version restores that
version's settings. Explicit settings deletion clears snapshots.

The reported fresh-card problem occurred in download/catalog. The public v2
catalog was unavailable while publication was paused. It is now published with
verified immutable release asset IDs. The exact signed build 13 fetched that
catalog and downloaded the standalone runtime plus Pilot 2.2.0 from an empty
phone cache, then verified both archives. No GitHub account was needed.

Build 13 passed 120 Flutter tests and static analysis. Its APK contains zero
bundled projects and uses the existing release certificate. See
[build 13 validation](docs/build13-release-validation.json).

Build 12's installation/lifecycle code is unchanged in build 13. Earlier attended
checks passed for existing-card upgrade/rollback, owner-confirmed startup, the
phone dashboard, cancellation and completion of Stop, and clean-directory setup.
A subsequent installation on an empty FAT card passed all 4,605 Pilot file checks
and left Pilot stopped. A monitored repeat retained the MMT heartbeat for 134
seconds after Stop. See [attended acceptance](docs/ATTENDED-ACCEPTANCE.md).

One earlier connection interruption during helper preparation recovered through
Bluetooth/Wi-Fi re-pairing. Its cause remains unresolved. These stationary checks
do not establish alignment, tracking, motor behavior or observing accuracy.
Existing build 11, its legacy catalog and immutable Beta 8 assets are retained.
