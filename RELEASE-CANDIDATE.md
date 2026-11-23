# MMT 0.1.0-rc.4 — build 14

Build 14 fixes a confirmed Android input-dispatch timeout during package
installation. The main-thread trace identified SSH AES-GCM upload encryption;
the card operation completed, but the app's progress screen became unresponsive.

Uploads now use SSH stdin.addStream with backpressure, at most 16 KiB per write,
and an event-queue yield between writes. The app retains command timeouts,
archive checksums and remote completion checks without flushing the shared
socket. No runtime, Pilot package, helper or catalog change is required.

All 124 Flutter tests and static analysis pass. New tests cover event scheduling,
bounded input consumption, exact bytes, and real SSH channel receive-window
pause/resume and timeout cleanup. The same production certificate signs the APK;
it contains no bundled project. See docs/SSH-UPLOAD-ANR.md and the build 14 receipt.

The catalog continues to list Pilot 2.2.0 first and retain Beta 8. Explicit version
choices survive refresh. Prior releases and their immutable assets are retained.
Earlier stationary lifecycle/rollback checks remain documented separately; this
fix does not establish motion, alignment, tracking or observing accuracy.

The attended retest passed full runtime/project installation from an empty
Toolkit directory, all 4,605 file checks, touch interactions during transfer,
post-install refresh, and independent stopped-state readback. The same app
process recorded zero new ANRs. The prior installation was preserved as an SD
backup, and temporary phone settings were restored.
