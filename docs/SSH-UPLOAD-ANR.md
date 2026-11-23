# SSH upload responsiveness — build 14

The owner reported an unresponsive MMT screen during a clean-card install on
production build 13. Android recorded an input-dispatch timeout while MMT was
foregrounded. Symbolizing the main-thread trace against its exact matching AOT
build identified SSHChannelController._uploadLoop, SSHTransport._sendAeadPacket
and AES-GCM encryption. The remote install journal subsequently reached complete;
an independent readback confirmed Pilot 2.2.0 installed and stopped. The frozen
progress screen did not mean the card operation had failed.

The upload loop used session.write without backpressure. A paused SSH sink could
consume the entire source into its queue. Draining buffered data runs encryption
on Flutter's UI isolate and could starve input and timer handling. Two regressions
reproduced the missing event-loop yield and unbounded source consumption before
the fix.

Build 14 streams through SSH stdin.addStream, preserving channel backpressure.
It splits input into at most 16 KiB writes and yields to the event queue between
writes. It retains command timeouts, checksum verification, EOF/remote-exit
completion and avoids flushing the shared transport socket. Package contents,
Toolkit helpers and the catalog are unchanged.

Validation: 124 Flutter tests and static analysis pass. Transport checks include
UI-event scheduling, exact transferred bytes, a paused input sink, the actual SSH
session/channel with a closed then reopened remote receive window, and timeout
cleanup while that real channel is backpressured. The APK uses the existing
production certificate and contains no bundled projects.

Raw Android traces, screenshots, device identifiers and private card state are
kept outside the public source repository. Attended retest results are recorded
in the build 14 validation receipt.

Attended retest passed on the same Pixel and Polaris. With the prior stopped
installation preserved in an SD backup, the active Toolkit directory was absent.
Build 14 installed the standalone runtime and Pilot, verified all 4,605 files,
and displayed installation complete. Device rendered during the 56.9 MiB upload;
Catalog and Installed rendered during archive validation. The same app process
survived the entire operation with zero new Android ANR events. A subsequent
status refresh succeeded. Independent readback confirmed Pilot stopped, followed
by MMT disconnect and zero controller connections. Temporary phone settings were
restored. No formatting, Pilot startup or motion was performed in this retest.
