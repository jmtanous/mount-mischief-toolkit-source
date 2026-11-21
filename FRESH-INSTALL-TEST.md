# Fresh SD installation check

Use the local MMT build 4 test APK. This procedure does not require firmware or
boot changes. Keep MMT open, leave the phone unlocked, and keep the mount nearby.
Start with the SD card recognized by Polaris. Card formatting and recovery are
performed by the owner; MMT does not format the card.

1. Open MMT, accept the experimental notice, and choose Polaris.
2. If needed, use Wake Wi-Fi, join Polaris Wi-Fi in Android settings, then return
   to MMT. Confirm the green connected-network indicator. No internet is expected.
3. Pair and inspect. Verify the SSH identity as prompted. A fresh card should have
   no MMT-managed projects; an empty card is not a broken Toolkit installation.
4. In Catalog, use the bundled Alpaca Pilot candidate and select Install. This
   prepares the Toolkit runtime and helpers on the SD card before the package.
5. Observe Toolkit setup, transfer bytes, archive checks, unpacking, file
   verification, activation and status refresh. Several minutes is normal.
6. Confirm Installation complete and Pilot Stopped. Installation must not start it.
7. Tap Start, review the observing site, and confirm. Allow up to three minutes.
8. Confirm Pilot ready, then Open Pilot. Verify the dashboard loads. Do not use
   alignment, tracking, mode changes or motion controls for this acceptance check.
9. Return to MMT, pair again if prompted, then Stop and confirm. Verify Stopped
   and Disconnected. A subsequent pair should still show the installed project.

If a step fails, record its checklist stage and expanded error details before
retrying. Do not format again or delete settings as a troubleshooting shortcut.
A reset card will not retain settings that existed only on that card.

The debug APK is for local testing. The production signer and final public
artifacts remain pending; see RELEASE-CANDIDATE.md and RELEASE-SIGNING.md.
