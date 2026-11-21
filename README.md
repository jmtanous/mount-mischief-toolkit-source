# Mount Mischief Toolkit

An independent Android app for managing projects on compatible field hardware.
The initial target is Benro Polaris, with Alpaca Pilot 2.2 Beta 8 support.
Not affiliated with or endorsed by Benro or oGecko Solutions.

**Experimental source preview.** Signed public downloads are not available in this
snapshot. Review the [release checklist](RELEASE-CHECKLIST.md) before distribution.

## What it does

- Discovers Polaris over Bluetooth and attempts to wake its Wi-Fi.
- Shows the phone's Wi-Fi association and verifies mount identity through SSH pairing.
- Installs, inspects, starts, stops and removes supported projects on the SD card.
- Shows Pilot startup stages and opens its interface inside the app.
- Offers a foreground-only Keep screen awake setting.

The app does not flash firmware or change boot configuration. Install does not
start Pilot. Starting Pilot applies the confirmed observing site and phone time,
then connects the driver to the mount. Alignment and observing controls remain
in Pilot. Experimental software can fail or damage equipment; keep operations
attended and have a recovery path.

## Basic workflow

1. Accept the experimental-use notice and select Polaris.
2. Obtain the project package while internet access is available.
3. Power on Polaris, wake its Wi-Fi if needed, and join its Wi-Fi in Android settings.
4. Return to MMT and choose Pair and inspect. Review the SSH identity prompt.
5. Install Pilot, then select Start and confirm the observing site.
6. Wait for startup verification, then choose Open Pilot.

“No internet” on Polaris Wi-Fi is normal. Android may switch to another network;
check the association indicator if pairing fails. Wi-Fi wake requires the mount
to be powered on. Keep MMT open during operations. An SSH timeout does not prove
remote work stopped: reconnect and inspect before retrying. Reinstall/uninstall
asks whether to preserve settings. Existing unmanaged installations are not adopted.

## Build and test

See [BUILDING.md](BUILDING.md). The upstream runtime is not committed; an exact
hash-matching archive must be supplied before Flutter asset builds/tests.
The current GitHub catalog defaults are invitation-only. Public source access does
not grant access to that catalog. Configure your own catalog using the documented
Dart defines, or await a separately prepared public release.

## License and credits

Original contributions are copyright (c) 2026 Jose Mtanous, under [MIT](LICENSE).
Upstream Pilot, libraries, fonts and other third-party assets retain their own
licenses. About & support → Open-source licenses displays the corresponding notices.
See [third-party notices](assets/legal/THIRD-PARTY-NOTICES.md) and the unchanged
[upstream license](assets/legal/alpaca-UPSTREAM-LICENSE.txt).

Support is optional: [Buy me a beer](https://buymeacoffee.com/jmtanousk).

## Installation progress

Toolkit setup names its runtime and helper steps. Package installation shows a checklist, transfer bytes, unpacking and verification file counts, activation, and status refresh. Counts apply to the current step, not the whole operation. Keep MMT open and connected; SD installation can take several minutes. Failures retain the last stage with error details below. Installation does not start the project.

Known compatible older Toolkit helpers retain installed-project and Stop controls. MMT offers a tools update once managed projects are stopped and other controllers disconnect. Missing, mixed, or unknown helper sets still require setup repair.
