part of '../main.dart';

// Compiled Pilot UI: other projects may have entirely different controls.
extension _PilotUi on _ToolkitHomeState {
  Future<Site?> siteDialog(InstalledProject project) async {
    final saved = project.json['settings'] as Map? ?? {};
    final name = TextEditingController(
      text: saved['location']?.toString() ?? '',
    );
    final lat = TextEditingController(
      text: saved['site_latitude']?.toString() ?? '',
    );
    final lon = TextEditingController(
      text: saved['site_longitude']?.toString() ?? '',
    );
    final elevation = TextEditingController(
      text: saved['site_elevation']?.toString() ?? '',
    );
    String? validation;
    bool locating = false;
    final result = await showDialog<Site>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Confirm observing site'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Starting synchronizes device time with this phone and applies this location. Alignment remains in Pilot.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Site name'),
                ),
                for (final item in [
                  (lat, 'Latitude (degrees)'),
                  (lon, 'Longitude (degrees)'),
                  (elevation, 'Elevation (metres)'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TextField(
                      controller: item.$1,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(labelText: item.$2),
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: locating
                      ? null
                      : () async {
                          update(() => locating = true);
                          try {
                            var permission = await Geolocator.checkPermission();
                            if (permission == LocationPermission.denied) {
                              permission = await Geolocator.requestPermission();
                            }
                            if (permission == LocationPermission.denied ||
                                permission ==
                                    LocationPermission.deniedForever) {
                              throw StateError(
                                'Location permission denied. Enter coordinates manually.',
                              );
                            }
                            final position =
                                await Geolocator.getCurrentPosition(
                                  locationSettings: const LocationSettings(
                                    accuracy: LocationAccuracy.high,
                                    timeLimit: Duration(seconds: 30),
                                  ),
                                );
                            if (!context.mounted) return;
                            lat.text = position.latitude.toStringAsFixed(6);
                            lon.text = position.longitude.toStringAsFixed(6);
                            elevation.text = position.altitude.toStringAsFixed(
                              0,
                            );
                            update(
                              () => validation =
                                  'GPS accuracy: ${position.accuracy.round()} m. Review all values before starting.',
                            );
                          } catch (e) {
                            if (context.mounted) {
                              update(() => validation = e.toString());
                            }
                          } finally {
                            if (context.mounted) update(() => locating = false);
                          }
                        },
                  icon: const Icon(Icons.my_location),
                  label: Text(locating ? 'Locating…' : 'Use phone location'),
                ),
                if (validation != null) Text(validation!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: locating
                  ? null
                  : () {
                      try {
                        final site = Site(
                          name.text.trim(),
                          double.parse(lat.text),
                          double.parse(lon.text),
                          double.parse(elevation.text),
                        );
                        site.validate();
                        Navigator.pop(context, site);
                      } catch (_) {
                        update(
                          () => validation = 'Enter a site name and valid numeric coordinates.',
                        );
                      }
                    },
              child: const Text('Confirm and start'),
            ),
          ],
        ),
      ),
    );
    // Dialog animations may still reference controllers; dispose after route transition.
    Future<void>.delayed(const Duration(seconds: 1), () {
      name.dispose();
      lat.dispose();
      lon.dispose();
      elevation.dispose();
    });
    return result;
  }

  Future<void> start(InstalledProject p) async {
    final site = await siteDialog(p);
    if (site == null) return;
    startup?.dispose();
    final attempt = StartupProgress();
    updateUi(() => startup = attempt);
    try {
      await platform.invokeMethod<void>('bindWifi');
      await device!.start(
        p.id,
        site,
        onProgress: (event) {
          if (mounted && identical(startup, attempt)) attempt.update(event);
        },
      );
      await refreshDevice();
      if (mounted && identical(startup, attempt)) {
        if (!installed.any(
          (item) => item.manifest.id == p.manifest.id && item.running,
        )) {
          throw StateError(
            'Pilot is not running after the status refresh. Reconnect and inspect before retrying.',
          );
        }
        attempt.update(
          StartupEvent(StartupStage.verifying, responseReceived: true),
        );
        attempt.finish();
      }
    } catch (e) {
      if (mounted && identical(startup, attempt)) attempt.finish(error: e);
      rethrow;
    }
  }

  Future<void> openPilot() async {
    final paired = device;
    if (paired == null) throw StateError('Pair and inspect a device first.');
    await platform.invokeMethod<void>('bindWifi');
    await platform.invokeMethod<void>('openPilot', {
      'url': Uri(scheme: 'http', host: paired.host, port: 8081).toString(),
    });
  }

  Widget projectStatus(
    String label,
    String value,
    IconData icon,
    bool positive,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 6,
      children: [
        Text(label, style: const TextStyle(color: Color(0xffc9c4d8))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: positive ? const Color(0xff005047) : const Color(0xff2b2933),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: positive
                    ? const Color(0xff44e2cd)
                    : const Color(0xffc9c4d8),
              ),
              const SizedBox(width: 5),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  color: positive
                      ? const Color(0xff44e2cd)
                      : const Color(0xffc9c4d8),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget installedPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Installed projects',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
      if (device != null)
        action('Refresh device', () => run(refreshDevice), icon: Icons.refresh),
      if (setupUpdateRequired) toolkitUpdateNotice(),
      if (!inspected)
        const Text('Pair and inspect a device to see its projects.'),
      if (inspected && installed.isEmpty)
        Text(
          setupRequired
              ? 'Toolkit is not installed on this SD card yet. Open Catalog and install a project to set up both.'
              : 'No projects installed with MMT.',
        ),
      for (final p in installed)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  p.manifest.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(p.manifest.version),
                const SizedBox(height: 16),
                projectStatus(
                  'Service',
                  p.running ? 'Running' : 'Stopped',
                  p.running
                      ? Icons.play_circle_outline
                      : Icons.stop_circle_outlined,
                  p.running,
                ),
                projectStatus(
                  'Controller',
                  p.pilot?['connected'] == true ? 'Connected' : 'Disconnected',
                  Icons.link,
                  p.pilot?['connected'] == true,
                ),
                projectStatus(
                  'Alignment',
                  p.pilot?['aligned'] == true ? 'Aligned' : 'Not confirmed',
                  Icons.explore_outlined,
                  p.pilot?['aligned'] == true,
                ),
                if (p.json['external_pilot'] != null)
                  const Text('An unmanaged Pilot service is present.'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: action(
                    'Open Pilot',
                    () => run(openPilot),
                    enabled: p.running,
                    icon: Icons.open_in_browser,
                  ),
                ),
                Wrap(
                  children: [
                    if (!p.running)
                      action(
                        'Start',
                        () => run(() => start(p)),
                        icon: Icons.play_arrow,
                      ),
                    if (p.running)
                      action(
                        'Stop',
                        () => run(() async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Stop ${p.manifest.name}?'),
                              content: const Text(
                                'This disconnects and stops the managed Pilot process.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Stop'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await platform.invokeMethod<void>('bindWifi');
                            await device!.stop(p.id);
                            await refreshDevice();
                            progress('${p.manifest.name} stopped.');
                          }
                        }),
                        icon: Icons.stop,
                      ),
                    const SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Divider(),
                            Text(
                              'Maintenance',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xffb9b4c9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    action(
                      'Reinstall',
                      () => run(() => install(p.manifest, current: p)),
                    ),
                    action(
                      'Uninstall',
                      () => run(() => remove(p)),
                      icon: Icons.delete_outline,
                    ),
                    action(
                      'Diagnostics',
                      () => run(() => logs(p)),
                      icon: Icons.receipt_long,
                    ),
                  ],
                ),
                if (!p.running)
                  const Text('Start Pilot before opening its interface.'),
              ],
            ),
          ),
        ),
      for (final op in operations.where((o) => o.phase != 'complete'))
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text('${op.project}: ${op.action} — ${op.phase}'),
          subtitle: Text(
            op.json['error']?.toString() ??
                op.json['detail']?.toString() ??
                'Inspect project state before retrying.',
          ),
        ),
    ],
  );
}
