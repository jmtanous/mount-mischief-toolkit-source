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

State at the end of that test: Pilot 2.2.0 installed and stopped, MMT disconnected, zero controller
connections. The confirmed site matches the original. The old installation and
settings remained in the SD backup at that time; Android's temporary USB stay-awake setting was
restored. Private identifiers, coordinates, screenshots and logs are not published.

## Scope and release gates

This proves clean Toolkit installation on the existing filesystem, not behavior
of a newly formatted/replacement card. It does not establish alignment, tracking,
celestial accuracy or motor behavior. The recovered network interruption remains
an explicit known observation, not a claimed fix. Optional upstream offline docs
could not download on Polaris Wi-Fi; the dashboard and status still worked.

## Follow-up: genuinely empty card and public catalog

After reporting a download/catalog failure, the owner supplied a card whose FAT
filesystem had no Toolkit tree and only 416 KiB used out of approximately 30 GB.
Production build 12 installed the standalone runtime and Pilot 2.2.0 from its
verified phone cache. All 4,605 project files passed verification; MMT reported
installation complete. An independent readback confirmed version
2.2.0-port.0.2.0-rc.1 stopped. No Pilot startup was requested during this test.

This is additional empty-card evidence; it does not establish how the card was
formatted. The earlier on-card backup was absent on this card. Private local
backups from the earlier test were preserved.

The catalog endpoint returned HTTP 404 while publication was paused, preventing
new clients from downloading packages. After the owner confirmed the failure was
in download/catalog, the approved catalog was published. Anonymous retrieval now
returns HTTP 200 and the exact verified catalog. Runtime and project release
assets passed complete anonymous downloads and SHA-256 verification. The current
catalog lists Pilot 2.2.0 first; build 13 selects the newest compatible version by
default while preserving an explicit user choice. Beta 8 remains available.

## Build 13 public download acceptance

The exact production-signed build 13 was installed over the existing app. App
data was backed up privately and only the four reproducible catalog/package
cache files were cleared; pairing and other settings were retained. With internet
available, the app automatically fetched the public catalog and selected Pilot
2.2.0. It displayed 70.6 MiB for the missing standalone runtime plus project.
Downloading completed successfully, and both archives passed the app's size and
SHA-256 checks before it reported “Verified offline package.” No GitHub sign-in
or private catalog staging was used. The released APK is not debuggable.

Beta 8 also downloaded and verified through the public catalog. Its explicit
selection survived refresh, and the picker listed 2.2.0 before Beta 8. The phone
was left on production build 13 with both versions cached and 2.2.0 selected.
Wi-Fi and the original USB stay-awake setting were restored. Pilot remained
stopped after the empty-card install; MMT was disconnected.
