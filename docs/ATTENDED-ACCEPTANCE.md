# Attended acceptance — MMT build 12 and Pilot 2.2.0

Stationary acceptance passed on the owner's Pixel 11 Pro (Android 17) and Benro
Polaris (vendor Linux 4.9.37, ARMv7), using the exact production-signed build 12
APK and verified, privately cached project/runtime archives. No alignment,
tracking, motion, mode, firmware or boot changes were requested.

## Existing installation and version rollback

Toolkit helper update, Beta 8 → 2.2.0 installation, managed startup, fresh 517
telemetry and the phone's live Pilot dashboard passed. Cancel Stop preserved
running status; confirmed Stop shut down Pilot and replaced the connected banner.
Rollback restored immutable Beta 8 and its original settings, while retaining
2.2.0's settings snapshot. Disconnect/re-pair preserved the stopped state.

The first rollback attempt lost its session during helper preparation, before
package staging. The active installation was unchanged. Bluetooth wake, explicit
Wi-Fi joining and re-pairing recovered the session; rollback then completed.
[Existing-card receipt](existing-sd-build12-acceptance.json) records the incident.

## Clean installation and monitored Stop

The owner authorized using/formatting the current card because no spare was
available. Instead of formatting, the stopped Toolkit tree was moved to a unique
backup directory. MMT verified an absent active Toolkit tree, setup needed and
zero projects. It installed the standalone runtime and then Pilot 2.2.0.

All 915 installed runtime files match the pinned standalone archive. That runtime
contains no Pilot project or project site-packages. All 4,605 Pilot files verified;
its initial settings were empty. Disconnect/re-pair reported ready without repair.
After the owner confirmed the site, startup, fresh telemetry, the actual phone
dashboard and clean Stop passed again. A read-only monitor recorded 134 seconds
of uninterrupted MMT keepalive after Pilot exited; a delayed device refresh also
succeeded. The earlier connection drop did not recur, but its cause is unresolved.
[Clean-install receipt](clean-install-build12-acceptance.json) contains exact results.

Final state: Pilot 2.2.0 installed and stopped, MMT disconnected, zero controller
connections. The confirmed site matches the original. The old installation and
settings remain in the SD backup; Android's temporary USB stay-awake setting was
restored. Private identifiers, coordinates, screenshots and logs are not published.

## Scope and release gates

This proves clean Toolkit installation on the existing filesystem, not behavior
of a newly formatted/replacement card. It does not establish alignment, tracking,
celestial accuracy or motor behavior. The recovered network interruption remains
an explicit known observation, not a claimed fix. Optional upstream offline docs
could not download on Polaris Wi-Fi; the dashboard and status still worked.

Public release-asset downloads remain untested because publication is not yet
authorized and the new catalog lacks asset IDs. Source/package review artifacts
are prepared locally; existing published releases and the legacy catalog are
unchanged. Before catalog publication, upload the approved assets, verify their
anonymous bytes/hashes and use their actual IDs. Beta 8 remains recommended.
