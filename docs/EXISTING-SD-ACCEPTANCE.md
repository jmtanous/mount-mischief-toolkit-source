# Existing-SD acceptance — build 12 / Pilot 2.2.0

On 2026-11-23, production-signed MMT build 12 completed an owner-attended,
stationary test on an existing working SD. It updated Toolkit helpers, installed
Pilot 2.2.0, started and connected the managed driver, and rendered the Pilot
interface on a Pixel 11 Pro running Android 17. Fresh 517 telemetry was observed;
tracking and alignment remained false, and no motion or mode-change controls
were used. The owner explicitly confirmed the saved observing site.

Cancel Stop preserved the running status and connected banner. Confirmed Stop
shut down Pilot and changed the banner to “Alpaca Pilot stopped.” Rollback to
immutable Beta 8 passed after connection recovery. Its restored settings match
the original backup; the 2.2.0 snapshot matches its last running settings.
Disconnecting and re-pairing preserved the stopped state. Final readback shows
Beta 8 stopped, no managed Pilot process and zero controller connections. MMT
was disconnected, and the temporary Android USB stay-awake setting was restored.

## Connection interruption and follow-up

The first rollback attempt failed during Toolkit helper preparation (`mv`, exit
not reported), before a new package operation was staged. The active 2.2.0
installation remained unchanged. Re-pairing later timed out. MMT Bluetooth wake,
explicit Android Wi-Fi joining and re-pairing recovered the connection; the retry
completed. The root cause is not established. A later clean-directory run recorded 134 seconds of stable post-stop keepalive
and a successful delayed refresh; the drop did not recur. Its cause remains
unresolved. See [the complete attended record](ATTENDED-ACCEPTANCE.md).

The packages and catalog were privately staged in the phone cache, followed by
restoring the exact production APK before testing. This does not validate public
asset downloads. An existing working interpreter may have been reused, so this
does not validate a fresh-card standalone Toolkit installation. No working card
was erased. The later clean-directory runtime and network repeat passed; newly formatted-card
behavior was not tested, and publication/download gates remain open. Optional upstream offline documentation could not download on the
mount's network; the application dashboard and status worked.

Exact hashes and structured results: [acceptance receipt](existing-sd-build12-acceptance.json).
Private coordinates, USB/Bluetooth identifiers, logs and screenshots are excluded.
