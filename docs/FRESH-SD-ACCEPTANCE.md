# Fresh-SD acceptance checklist

Prepared for MMT rc.3/build 12 and Pilot 2.2.0 port rc.1. Existing-SD upgrade,
rollback and stationary lifecycle checks passed after connection recovery. A
clean Toolkit directory on that same filesystem also passed standalone runtime
installation and a monitored post-stop connection repeat. See
[the attended record](ATTENDED-ACCEPTANCE.md). A newly formatted or replacement
card was not used. Published build 11 evidence is historical and remains under
docs/releases/mmt-build11.

The signed candidate has no bundled projects. Automated host/ARM checks pass,
including standalone setup repair and full Beta 8 → 2.2.0 → Beta 8 settings
rollback. Physical phone networking, SD behavior and controller timing remain
attended checks. Exact APK/package hashes are in the release validation records.

## Preparation

- Use a spare, compatible SD card with no Toolkit installation. Preserve the
  current working card and its settings; do not erase it to create this fixture.
- Record the card, mount firmware, phone model, Android version, app version,
  APK SHA-256, Toolkit runtime SHA-256 and selected Pilot package version before testing.
- Use an unlocked phone and an attended Polaris. Close other controllers.
- Prepare both verified project archives and the Toolkit runtime before joining
  Polaris Wi-Fi. The unpublished catalog draft has no new release asset IDs.
  A local cache staging method or explicitly authorized draft assets must be
  arranged before this test; no public catalog change is implied.

## Attended checks

1. Wake Polaris Wi-Fi, join its network and use Pair and inspect. Confirm the
   app shows “Connected · setup needed” and offers project installation.
2. Open Catalog and install Pilot. Confirm setup, transfer, unpacking and
   verification progress complete, followed by the installed project card.
3. Disconnect and pair again. Confirm the installation remains visible and no
   setup or repair request appears.
4. Review and explicitly confirm the observing site, then Start. Confirm startup
   completes and Open Pilot loads live status. Do not use alignment, slew or
   tracking controls during this acceptance pass.
5. Return to Installed, confirm Stop and check both the service card and banner
   report stopped. Disconnect and pair again to verify the stopped state.
6. With Pilot stopped, upgrade from Beta 8 to 2.2.0 and confirm saved settings
   carry forward. Keep test changes clearly distinguishable. Roll back to Beta 8
   and verify its previous settings return; confirm 2.2.0 retains its own snapshot.
   Review the observing site before every Start.
7. Record results and errors per step, including the final Pilot state. Leave
   Pilot stopped when finished.

## UI regression checks on the next candidate

- After successful Start, cancel Stop once: Pilot should remain running and the
  connected banner should remain. Then confirm Stop: the banner should change
  to “Alpaca Pilot stopped.”
- On an existing-SD fixture containing a version whose archive is absent from
  the phone and not bundled in the app, choose Reinstall and Keep settings.
  Confirm the package notice explains offline recovery, the session stays paired,
  the project remains unchanged, and Refresh device and Stop remain usable.
- Do not remove app data or downgrade a working mount solely to manufacture
  that fixture. The isolated regression tests cover it until one is available.

Local automated checks cannot establish fresh-SD, Wi-Fi or physical controller
acceptance. Record a new candidate's results separately from the published build
11 record. A new release is not part of this checklist.
