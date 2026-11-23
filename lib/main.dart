import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'benro.dart';
import 'bluetooth_wake.dart';
import 'entry_flow.dart';
import 'catalog.dart';
import 'models.dart';
import 'startup_progress.dart';
import 'installation_progress.dart';

part 'integrations/pilot_ui.dart';

const independence = communityNotice;
const platform = MethodChannel('org.mountmischief/toolkit');
typedef DeviceFactory = Benro Function(
  String host,
  void Function(String) progress,
  Future<bool> Function(String, String) confirmKey,
);
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final entry in {
      'Mount Mischief Toolkit': 'LICENSE',
      'Alpaca Pilot port contributions': 'assets/legal/alpaca-port-LICENSE.txt',
      'Alpaca Benro Polaris / Alpaca Pilot (upstream)':
          'assets/legal/alpaca-UPSTREAM-LICENSE.txt',
      'Third-party notices': 'assets/legal/THIRD-PARTY-NOTICES.md',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString(entry.value));
    }
    for (final registry in {
      'Android and Flutter': 'assets/legal/platform-licenses.json',
      'Toolkit runtime': 'assets/legal/runtime-licenses.json',
    }.entries) {
      final notices = jsonDecode(
        await rootBundle.loadString(registry.value),
      ) as Map;
      for (final entry in (notices['files'] as Map).entries) {
        yield LicenseEntryWithLineBreaks([
          '${registry.key}: ${entry.key}',
        ], entry.value as String);
      }
    }
    for (final family in ['RedHatDisplay', 'RadioCanadaBig']) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$family-OFL.txt'));
    }
  });
  runApp(const ToolkitApp());
}

ThemeData toolkitTheme() => ThemeData(
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: const Color(0xff603ce2),
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xffcabeff),
        onPrimary: const Color(0xff31009a),
        secondary: const Color(0xff44e2cd),
        primaryContainer: const Color(0xff4816cb),
        secondaryContainer: const Color(0xff005047),
        surfaceContainer: const Color(0xff201e28),
        surfaceContainerHigh: const Color(0xff2b2933),
        surface: const Color(0xff14121b),
        onSurface: const Color(0xffe6e0ee),
        onSurfaceVariant: const Color(0xffc9c4d8),
        outline: const Color(0xff938ea1),
        outlineVariant: const Color(0xff484555),
      ),
  scaffoldBackgroundColor: const Color(0xff14121b),
  fontFamily: 'RadioCanadaBig',
  textTheme: ThemeData.dark().textTheme
      .apply(fontFamily: 'RadioCanadaBig')
      .copyWith(
        headlineLarge: const TextStyle(
          fontFamily: 'RedHatDisplay',
          fontSize: 28,
          height: 1.22,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: const TextStyle(
          fontFamily: 'RedHatDisplay',
          fontSize: 26,
          height: 1.23,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: const TextStyle(
          fontFamily: 'RedHatDisplay',
          fontSize: 22,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
      ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  cardTheme: const CardThemeData(
    color: Color(0xff201e28),
    elevation: 0,
    margin: EdgeInsets.symmetric(vertical: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      side: BorderSide(color: Color(0xff484555)),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xff14121b),
    surfaceTintColor: Colors.transparent,
    titleTextStyle: TextStyle(
      fontFamily: 'RedHatDisplay',
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xff1c1a24),
    indicatorColor: Color(0xff4816cb),
    indicatorShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
  ),
  dialogTheme: const DialogThemeData(
    backgroundColor: Color(0xff201e28),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  useMaterial3: true,
);

class ToolkitApp extends StatelessWidget {
  final Catalog? catalog;
  final DeviceFactory? deviceFactory;
  const ToolkitApp({super.key, this.catalog, this.deviceFactory});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mount Mischief Toolkit',
    debugShowCheckedModeBanner: false,
    theme: toolkitTheme(),
    home: EntryFlow(
      workspace: (changeMount) => ToolkitHome(
        catalog: catalog,
        deviceFactory: deviceFactory,
        onChangeMount: changeMount,
      ),
    ),
  );
}

class ToolkitHome extends StatefulWidget {
  final Catalog? catalog;
  final DeviceFactory? deviceFactory;
  final VoidCallback? onChangeMount;
  const ToolkitHome({
    super.key,
    this.catalog,
    this.deviceFactory,
    this.onChangeMount,
  });
  @override
  State<ToolkitHome> createState() => _ToolkitHomeState();
}

enum ConnectionStep { wake, wifi, pair }

class _ToolkitHomeState extends State<ToolkitHome> with WidgetsBindingObserver {
  late final catalog = widget.catalog ?? Catalog();
  final host = TextEditingController(text: deviceHost);
  List<ProjectManifest> projects = [];
  List<InstalledProject> installed = [];
  List<OperationStatus> operations = [];
  Set<String> cached = {};
  Benro? device;
  int tab = 0, controllerCount = 0;
  bool busy = false, inspected = false;
  bool setupIncomplete = false;
  bool setupRequired = false;
  bool setupUpdateRequired = false;
  StartupProgress? startup;
  InstallationProgress? installation;
  StreamSubscription<dynamic>? wifiSubscription;
  Map<String, dynamic>? wifiConnection;
  static const wifiEvents = EventChannel('org.mountmischief/wifi-status');

  void updateWifiConnection(dynamic value) {
    if (!mounted || value is! Map) return;
    setState(() => wifiConnection = Map<String, dynamic>.from(value));
  }

  Future<void> readWifiConnection() async {
    try {
      updateWifiConnection(
        await platform.invokeMapMethod<String, dynamic>('wifiStatus'),
      );
    } catch (_) {
      updateWifiConnection({'state': 'unknown'});
    }
  }

  String? get wifiConnectionLabel => switch (wifiConnection?['state']) {
    'polaris' => 'Connected to ${wifiConnection!['ssid']}',
    'other' => 'Connected to another Wi-Fi network',
    'disconnected' => 'Not connected to Wi-Fi',
    'unknown' => 'Wi-Fi name unavailable — verify by pairing',
    _ => null,
  };

  ConnectionStep nextConnectionStep = ConnectionStep.wake;
  bool wakeCompleted = false, pairing = false;
  BluetoothWakeProgress? wakeProgress;
  String? pairingFailure, wifiFailure;
  bool settingsPending = false,
      settingsLaunched = false,
      settingsDeparted = false;
  int guideGeneration = 0;

  void finishSettingsReturn() {
    if (!settingsPending ||
        !settingsLaunched ||
        !settingsDeparted ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    setState(() {
      settingsPending = false;
      nextConnectionStep = ConnectionStep.pair;
      wifiFailure = null;
    });
  }

  Future<void> openWifiSettings() async {
    final generation = guideGeneration;
    setState(() {
      settingsPending = true;
      settingsLaunched = false;
      settingsDeparted = false;
      wifiFailure = null;
    });
    try {
      await platform.invokeMethod<void>('wifiSettings');
      if (!mounted || generation != guideGeneration) return;
      settingsLaunched = true;
      finishSettingsReturn();
    } catch (e) {
      if (!mounted || generation != guideGeneration) return;
      setState(() {
        settingsPending = false;
        wifiFailure = 'Could not open Wi-Fi settings';
        nextConnectionStep = ConnectionStep.wifi;
      });
      rethrow;
    }
  }

  String message = 'Download a project, then connect to your device Wi-Fi.';
  String? error;
  String? catalogNotice;
  Map<String, int> downloadSizes = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
    unawaited(readWifiConnection());
    wifiSubscription = wifiEvents.receiveBroadcastStream().listen(
      updateWifiConnection,
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(wifiSubscription?.cancel());
    startup?.dispose();
    installation?.dispose();
    catalog.close();
    device?.close();
    host.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (settingsPending &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused)) {
      settingsDeparted = true;
    }
    if (state == AppLifecycleState.resumed) {
      finishSettingsReturn();
      unawaited(readWifiConnection());
    } else {
      wifiConnection = null;
    }
    if (state == AppLifecycleState.paused &&
        device?.holdingHeartbeat == true &&
        !busy) {
      setState(clearDeviceSession);
      unawaited(
        platform.invokeMethod<void>('keepAwake', false).catchError((_) {}),
      );
    }
    if (state == AppLifecycleState.resumed &&
        device != null &&
        !busy &&
        error == null) {
      unawaited(run(refreshDevice));
    }
  }

  void clearDeviceSession({bool preserveStartup = false}) {
    if (!preserveStartup) {
      startup?.dispose();
      startup = null;
    }
    guideGeneration++;
    nextConnectionStep = ConnectionStep.wake;
    wakeCompleted = false;
    wakeProgress = null;
    pairing = false;
    pairingFailure = null;
    wifiFailure = null;
    settingsPending = false;
    settingsLaunched = false;
    settingsDeparted = false;
    device?.close();
    device = null;
    inspected = false;
    setupIncomplete = false;
    setupRequired = false;
    setupUpdateRequired = false;
    installed = [];
    operations = [];
    controllerCount = 0;
    message = 'Device session ended. Join its Wi-Fi and use Pair and inspect to reconnect.';
  }

  void updateUi(VoidCallback callback) {
    if (mounted) setState(callback);
  }

  void progress(String value) {
    if (mounted) setState(() => message = value);
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var list = await catalog.cached();
      if (list.isEmpty && widget.catalog == null) {
        try {
          list = await catalog.refresh();
        } catch (_) {
          catalog.cacheNotice = 'Catalog could not be loaded. Connect to the internet and tap Refresh catalog.';
        }
      }
      final ready = <String>{};
      final sizes = <String, int>{};
      for (final p in list.where((p) => p.supported)) {
        if (await catalog.ready(p)) {
          ready.add(p.hash);
          sizes[p.hash] = 0;
        } else {
          sizes[p.hash] = await catalog.requiredDownloadBytes(p);
        }
      }
      if (mounted) {
        setState(() {
          projects = list;
          cached = ready;
          downloadSizes = sizes;
          catalogNotice = catalog.cacheNotice;
          host.text = prefs.getString('device_host') ?? deviceHost;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      if (startup?.active == false) {
        startup?.dispose();
        startup = null;
      }
      installation?.dispose();
      installation = null;
      busy = true;
      error = null;
    });
    try {
      await platform.invokeMethod<void>('keepAwake', true);
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = device == null
              ? (e is HttpException ? e.message : e.toString())
              : '${device!.describeError(e)}\nLast step: $message';
          if (device != null) {
            clearDeviceSession(preserveStartup: startup?.failure != null);
          }
        });
      }
    } finally {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused &&
          device?.holdingHeartbeat == true) {
        setState(clearDeviceSession);
      }
      try {
        await platform.invokeMethod<void>(
          'keepAwake',
          device?.holdingHeartbeat == true,
        );
      } catch (_) {}
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirmKey(String address, String fingerprint) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pair this device?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Confirm that $address is your Benro Polaris. Compare this fingerprint with a trusted record if available. Toolkit will remember it and block changes.',
                ),
                const SizedBox(height: 16),
                SelectableText(fingerprint),
                const SizedBox(height: 16),
                const Text(independence),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Pair device'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> connect() async {
    device?.close();
    device =
        widget.deviceFactory?.call(host.text.trim(), progress, confirmKey) ??
        Benro(
          host: host.text.trim(),
          progress: progress,
          confirmKey: confirmKey,
        );
    setState(() {
      inspected = false;
      setupIncomplete = false;
      setupRequired = false;
      setupUpdateRequired = false;
      installed = [];
      operations = [];
    });
    final connectingDevice = device!;
    final generation = guideGeneration;
    await platform.invokeMethod<void>('bindWifi');
    if (!mounted || generation != guideGeneration) return;
    await connectingDevice.open();
    if (!mounted || generation != guideGeneration) {
      connectingDevice.close();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || generation != guideGeneration) return;
    await prefs.setString('device_host', host.text.trim());
    if (!mounted || generation != guideGeneration) return;
    await refreshDevice();
  }

  Future<void> wakeWifi() async {
    final previousStep = nextConnectionStep;
    final previousWake = wakeCompleted;
    final generation = guideGeneration;
    setState(() {
      wakeProgress = BluetoothWakeProgress.scanning;
      wakeCompleted = false;
      pairingFailure = null;
    });
    final woke = await showBluetoothWake(
      context,
      onProgress: (value) {
        if (mounted && generation == guideGeneration) {
          setState(() => wakeProgress = value);
        }
      },
    );
    if (!mounted || generation != guideGeneration) return;
    if (!woke) {
      setState(() {
        if (wakeProgress == BluetoothWakeProgress.failed) {
          wakeCompleted = false;
          nextConnectionStep = ConnectionStep.wake;
        } else {
          wakeProgress = null;
          wakeCompleted = previousWake;
          nextConnectionStep = previousStep;
        }
      });
      return;
    }
    setState(() {
      wakeProgress = null;
      wakeCompleted = true;
      nextConnectionStep = ConnectionStep.wifi;
    });
    progress(
      'Bluetooth wake completed. Join Polaris Wi-Fi, then pair to verify connectivity.',
    );
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Polaris Wi-Fi'),
        content: const Text(
          'Select your Polaris network in Wi-Fi settings. “No internet” is normal. Then return to the Device screen and tap Pair and inspect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Wi-Fi settings'),
          ),
        ],
      ),
    );
    if (openSettings == true && mounted) await openWifiSettings();
  }

  Future<void> pairWithWakeRecovery() async {
    setState(() {
      pairing = true;
      pairingFailure = null;
      nextConnectionStep = ConnectionStep.pair;
    });
    try {
      await connect();
      if (mounted) setState(() => pairing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        clearDeviceSession();
        pairingFailure = 'Pairing failed';
        nextConnectionStep = ConnectionStep.pair;
      });
      final unreachable =
          e is SocketException ||
          e is TimeoutException ||
          (e is PlatformException && e.code == 'NO_WIFI') ||
          e.toString().startsWith('SSHSocketError');
      if (!unreachable || !mounted) rethrow;
      final wake = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot reach Polaris'),
          content: Text(
            'Its Wi-Fi may be asleep. You can wake it over Bluetooth and retry pairing.\n\n$e',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Wake Wi-Fi and retry'),
            ),
          ],
        ),
      );
      if (wake == true && mounted) {
        await wakeWifi();
      } else {
        rethrow;
      }
    }
  }

  Future<void> refreshDevice() async {
    await platform.invokeMethod<void>('bindWifi');
    final state = await device!.inspect();
    if (mounted) {
      setState(() {
        installed = (state['projects'] as List)
            .map((e) => InstalledProject(Map<String, dynamic>.from(e as Map)))
            .toList();
        operations = (state['operations'] as List)
            .map((e) => OperationStatus(Map<String, dynamic>.from(e as Map)))
            .toList();
        controllerCount = state['controller_clients'] as int? ?? 0;
        setupIncomplete = state['setup_incomplete'] == true;
        setupRequired = state['setup_required'] == true;
        setupUpdateRequired = state['setup_update_required'] == true;
        inspected = !setupIncomplete;
      });
    }
  }

  Future<void> trackInstallation(
    String title,
    Future<void> Function() action, {
    bool toolkitOnly = false,
  }) async {
    final tracker = InstallationProgress(title, toolkitOnly: toolkitOnly);
    final target = device!;
    if (mounted) setState(() => installation = tracker);
    target.onInstallationProgress = tracker.update;
    try {
      await action();
      tracker.update(const InstallationEvent('finish'));
      await refreshDevice();
      tracker.finish();
    } catch (error) {
      tracker.finish(error: error);
      rethrow;
    } finally {
      target.onInstallationProgress = null;
    }
  }

  Future<void> repairSetup() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          setupUpdateRequired
              ? 'Update Toolkit tools?'
              : 'Repair Toolkit setup?',
        ),
        content: const Text(
          'This restores Toolkit’s SD runtime and helpers. Project files and settings are preserved. A replaced runtime is retained for inspection. Disconnect other controllers and keep Toolkit open until repair finishes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(setupUpdateRequired ? 'Update tools' : 'Repair setup'),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    final bootstrap = await catalog.bootstrap();
    await platform.invokeMethod<void>('bindWifi');
    await trackInstallation(
      'Setting up Toolkit',
      () => device!.repairSetup(bootstrap),
      toolkitOnly: true,
    );
  }

  Future<void> download(ProjectManifest p) async {
    await platform.invokeMethod<void>('releaseNetwork');
    await catalog.prepare(
      p,
      (count, total) =>
          progress('Downloading ${p.name}: ${(count * 100 / total).floor()}%'),
    );
    if (mounted) {
      setState(() {
        cached.add(p.hash);
        downloadSizes[p.hash] = 0;
      });
    }
    progress('${p.name} is ready for offline installation.');
  }

  Future<bool?> settingsChoice(
    String action,
    String name, {
    bool running = false,
  }) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$action $name?'),
      content: Text(
        '${running ? 'This will stop the managed project first. ' : ''}Choose what to do with saved settings. Other projects are unaffected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Delete settings'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Keep settings'),
        ),
      ],
    ),
  );
  Future<void> install(ProjectManifest p, {InstalledProject? current}) async {
    if (!p.supported) throw StateError('Update MMT required');
    if (device == null || !inspected) {
      throw StateError('Pair and inspect the device first');
    }
    bool keep = true;
    if (current != null) {
      final choice = await settingsChoice(
        current.manifest.hash == p.hash
            ? 'Reinstall'
            : 'Change version to ${p.version} for',
        p.name,
        running: current.running,
      );
      if (choice == null) return;
      keep = choice;
    }
    final File archive;
    final File bootstrap;
    try {
      archive = await catalog.bundled(p);
      // Bootstrap stays pinned to the app, independent of catalog updates.
      bootstrap = await catalog.bootstrap();
    } catch (e) {
      // Local preparation has not touched the device. Keep its session and
      // running project available so the user can recover or choose a version.
      if (mounted) {
        setState(() {
          error = 'Installation package is not ready.\n${e is StateError ? e.message : e}';
          message = 'Installation not started. Device remains paired.';
        });
      }
      return;
    }
    await platform.invokeMethod<void>('bindWifi');
    if (current == null && await device!.hasToolchain()) {
      final state = await device!.call('inspect', project: p.id);
      if (state['retained_settings'] == true) {
        final choice = await settingsChoice(
          'Install with retained settings for',
          p.name,
        );
        if (choice == null) return;
        keep = choice;
      }
    }
    if (current?.running == true) await device!.stop(p.id);
    await trackInstallation(
      'Installing ${p.name}',
      () => device!.install(
        p,
        archive,
        bootstrap,
        reinstall: current != null,
        keepSettings: keep,
      ),
    );
    if (mounted) setState(() => tab = 2);
  }

  Future<void> remove(InstalledProject p) async {
    final keep = await settingsChoice(
      'Uninstall',
      p.manifest.name,
      running: p.running,
    );
    if (keep == null) return;
    await platform.invokeMethod<void>('bindWifi');
    if (p.running) await device!.stop(p.id);
    await device!.uninstall(p.id, keep);
    await refreshDevice();
    progress('Project uninstalled.');
  }

  Future<void> logs(InstalledProject p) async {
    await platform.invokeMethod<void>('bindWifi');
    final data = await device!.call('logs', project: p.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${p.manifest.name} diagnostics'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(data['text']?.toString() ?? 'No logs'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget action(
    String label,
    VoidCallback callback, {
    IconData? icon,
    bool enabled = true,
    bool? primary,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8, bottom: 8),
    child: FilledButton.tonalIcon(
      onPressed: busy || !enabled ? null : callback,
      style: FilledButton.styleFrom(
        backgroundColor:
            (primary ??
                ['Start', 'Open Pilot', 'Install', 'Download'].contains(label))
            ? const Color(0xffcabeff)
            : label == 'Stop'
            ? const Color(0xff93000a)
            : const Color(0xff2b2933),
        foregroundColor:
            (primary ??
                ['Start', 'Open Pilot', 'Install', 'Download'].contains(label))
            ? const Color(0xff31009a)
            : const Color(0xffe6e0ee),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon ?? Icons.chevron_right, size: 18),
      label: Text(label),
    ),
  );
  Future<void> changeMount() async {
    final confirmed =
        device == null ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Change mount?'),
                content: const Text(
                  'Disconnect MMT and choose another mount. Pilot will keep running.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Change mount'),
                  ),
                ],
              ),
            ) ==
            true;
    if (!confirmed || !mounted) return;
    setState(clearDeviceSession);
    await platform.invokeMethod<void>('releaseNetwork');
    if (mounted) widget.onChangeMount?.call();
  }

  Widget connectionStep(
    String number,
    String title,
    String description, {
    Widget? control,
    String? status,
    bool active = false,
    bool complete = false,
    bool working = false,
    bool failed = false,
  }) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: active ? const Color(0xffcabeff) : const Color(0xff484555),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$number. $title',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (status != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (working)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    complete
                        ? Icons.check_circle_outline
                        : failed
                        ? Icons.error_outline
                        : Icons.arrow_forward,
                    size: 16,
                    color: complete
                        ? const Color(0xff44e2cd)
                        : failed
                        ? const Color(0xffffb4ab)
                        : const Color(0xffcabeff),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      color: complete
                          ? const Color(0xff44e2cd)
                          : failed
                          ? const Color(0xffffb4ab)
                          : const Color(0xffcabeff),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Color(0xffc9c4d8),
            ),
          ),
          if (control != null) ...[const SizedBox(height: 12), control],
        ],
      ),
    ),
  );

  Widget devicePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mount status',
                style: TextStyle(fontSize: 12, color: Color(0xff938ea1)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    inspected ? Icons.check_circle_outline : Icons.link_off,
                    color: inspected
                        ? const Color(0xff44e2cd)
                        : const Color(0xffc9c4d8),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      inspected
                          ? (setupRequired
                                ? 'Connected · setup needed'
                                : 'Connected and ready')
                          : setupIncomplete
                          ? 'Setup needs repair'
                          : 'Not connected',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              if (inspected) ...[
                const SizedBox(height: 12),
                Text(
                  host.text,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xffc9c4d8),
                  ),
                ),
                const Divider(height: 24),
                Text(
                  '${installed.length} managed projects • $controllerCount other controller connections',
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (setupRequired)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Install Toolkit on this SD card',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Toolkit is not installed on this card yet. Choose a project in Catalog and tap Install. MMT installs Toolkit first, then your project—there is no separate setup step.',
                ),
                const SizedBox(height: 12),
                action(
                  'Choose a project to install',
                  () => setState(() => tab = 1),
                  primary: true,
                  icon: Icons.add,
                ),
              ],
            ),
          ),
        ),
      if (!inspected && !setupIncomplete) ...[
        const Text(
          'Connect to Polaris',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        connectionStep(
          '1',
          'Power on your mount',
          'Turn on Polaris and keep it nearby.',
        ),
        connectionStep(
          '2',
          'Wake its Wi-Fi',
          'Wake Wi-Fi through Bluetooth. Polaris may turn Wi-Fi off after 60 seconds of inactivity.',
          active: nextConnectionStep == ConnectionStep.wake,
          complete: wakeCompleted && wakeProgress == null,
          working:
              wakeProgress == BluetoothWakeProgress.scanning ||
              wakeProgress == BluetoothWakeProgress.waking,
          failed: wakeProgress == BluetoothWakeProgress.failed,
          status: switch (wakeProgress) {
            BluetoothWakeProgress.scanning => 'Scanning for Polaris…',
            BluetoothWakeProgress.selecting => 'Select your mount',
            BluetoothWakeProgress.waking => 'Waking Wi-Fi…',
            BluetoothWakeProgress.failed => 'Wake failed',
            null =>
              wakeCompleted
                  ? 'Wake request completed'
                  : nextConnectionStep == ConnectionStep.wake
                  ? 'Next step'
                  : 'Optional if Wi-Fi is already on',
          },
          control: action(
            'Wake Wi-Fi',
            () => run(wakeWifi),
            icon: Icons.bluetooth,
            primary: nextConnectionStep == ConnectionStep.wake,
            enabled: device == null,
          ),
        ),
        connectionStep(
          '3',
          'Join the Polaris network',
          'Select Polaris Wi-Fi in Android settings. “No internet” is normal.',
          active: nextConnectionStep == ConnectionStep.wifi,
          complete: wifiConnection?['state'] == 'polaris',
          failed: wifiFailure != null,
          status:
              wifiFailure ??
              wifiConnectionLabel ??
              (settingsPending
                  ? 'Choose Polaris in settings'
                  : nextConnectionStep == ConnectionStep.pair
                  ? 'Verify by pairing'
                  : nextConnectionStep == ConnectionStep.wifi
                  ? 'Next step'
                  : 'Not checked'),
          control: action(
            'Wi-Fi settings',
            () => run(openWifiSettings),
            primary: nextConnectionStep == ConnectionStep.wifi,
            icon: Icons.wifi,
          ),
        ),
        connectionStep(
          '4',
          'Pair and verify',
          'Once Wi-Fi connects, return here and pair.',
          active: nextConnectionStep == ConnectionStep.pair,
          working: pairing,
          failed: pairingFailure != null,
          status: pairing
              ? 'Pairing and inspecting…'
              : pairingFailure ??
                    (nextConnectionStep == ConnectionStep.pair
                        ? 'Ready to check'
                        : 'Not checked'),
          control: action(
            'Pair and inspect',
            () => run(pairWithWakeRecovery),
            primary: nextConnectionStep == ConnectionStep.pair,
            icon: Icons.link,
          ),
        ),
      ],
      if (device?.holdingHeartbeat == true)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.wifi, color: Color(0xff85daca)),
                    SizedBox(width: 10),
                    Text(
                      'Keeping Wi-Fi awake',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Leave MMT open to maintain this connection. Disconnect releases its heartbeat.',
                ),
              ],
            ),
          ),
        ),
      if (device != null)
        Wrap(
          children: [
            if (inspected)
              action(
                'Refresh device',
                () => run(refreshDevice),
                icon: Icons.refresh,
              ),
            action(
              'Disconnect',
              () => run(() async {
                setState(clearDeviceSession);
              }),
              icon: Icons.link_off,
            ),
          ],
        ),
      if (setupUpdateRequired) toolkitUpdateNotice(),
      if (setupIncomplete) ...[
        const Text(
          'Restore MMT’s supporting tools on the mount’s SD card. Installed projects and saved settings are preserved.',
        ),
        action(
          'Repair Toolkit setup',
          () => run(repairSetup),
          icon: Icons.build,
        ),
      ],
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Advanced connection'),
        children: [
          TextField(
            controller: host,
            enabled: !busy && device == null,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Device IP address'),
          ),
          const SizedBox(height: 12),
          const Text(
            'First pairing verifies the SSH fingerprint. Unexpected identity changes are blocked.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        independence,
        style: TextStyle(fontSize: 11, color: Color(0xffb9b4c9)),
      ),
      const SizedBox(height: 8),
      const Text(
        'Toolkit installs software on the SD card. Firmware and automatic boot changes are outside this version.',
        style: TextStyle(fontSize: 11, color: Color(0xffb9b4c9)),
      ),
    ],
  );
  final Map<String, String> selectedVersions = {};
  // Catalog publishers list each project's releases newest first. Version names
  // are project-defined; preserve that order rather than guessing their syntax.
  // Keep an explicit choice across refreshes, otherwise select the newest usable release.
  Iterable<ProjectManifest> get selectedProjects => projects.map((p) => p.id).toSet().map((id) {
    final versions = projects.where((p) => p.id == id).toList();
    return versions.firstWhere((p) => p.hash == selectedVersions[id],
      orElse: () => versions.firstWhere((p) => p.supported, orElse: () => versions.first));
  });

  Widget catalogPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Project catalog',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
      const Text('Download with internet. Connect to Polaris to install.'),
      if (projects.isEmpty) const Text('No projects downloaded. Refresh the catalog with internet access.'),
      if (catalogNotice != null) ...[
        const SizedBox(height: 12),
        Text(catalogNotice!),
      ],
      const SizedBox(height: 12),
      action(
        'Refresh catalog',
        () => run(() async {
          await platform.invokeMethod<void>('releaseNetwork');
          final list = await catalog.refresh();
          if (!mounted) return;
          setState(() => projects = list);
          await load();
          progress('Public catalog refreshed.');
        }),
        icon: Icons.refresh,
      ),
      for (final p in selectedProjects)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: Theme.of(context).textTheme.titleLarge),
                if (!p.supported) const Text('Update MMT required'),
                DropdownButton<String>(
                  value: p.hash,
                  isExpanded: true,
                  items: projects.where((v) => v.id == p.id).map((v) => DropdownMenuItem(
                    value: v.hash, child: Text(v.version),
                  )).toList(),
                  onChanged: busy ? null : (value) => setState(() => selectedVersions[p.id] = value!),
                ),
                const SizedBox(height: 8),
                if (p.id == 'alpaca-pilot')
                  const Text(
                    'ASCOM Alpaca driver and Pilot controls for Polaris.',
                    style: TextStyle(color: Color(0xffb9b4c9)),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Compatible with Polaris',
                  style: TextStyle(fontSize: 12, color: Color(0xff85daca)),
                ),
                Text(
                  '${p.version} · ${(p.bytes / 1048576).toStringAsFixed(1)} MiB project',
                ),
                Text(
                  cached.contains(p.hash)
                      ? 'Verified offline package'
                      : 'Download before connecting to device Wi-Fi',
                ),
                if (downloadSizes[p.hash] != null && downloadSizes[p.hash]! > 0)
                  Text('${(downloadSizes[p.hash]! / 1048576).toStringAsFixed(1)} MiB remaining, including required Toolkit setup'),
                if (setupRequired)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Install sets up Toolkit on the SD card first, then installs this project. Keep MMT open until both finish.',
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  children: [
                    action(
                      'Download',
                      () => run(() => download(p)),
                      enabled: p.supported,
                      icon: Icons.download,
                    ),
                    if (!installed.any((x) => x.id == p.id))
                      action(
                        'Install',
                        () => run(() => install(p)),
                        enabled: p.supported,
                        icon: Icons.add,
                      ),
                    if (installed.any(
                      (x) => x.id == p.id && x.manifest.hash != p.hash,
                    ))
                      action(
                        'Change version',
                        () => run(
                          () => install(
                            p,
                            current: installed.firstWhere((x) => x.id == p.id),
                          ),
                        ),
                        enabled: p.supported,
                        icon: Icons.swap_horiz,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
  Widget toolkitUpdateNotice() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Toolkit tools update available',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            installed.any((p) => p.running)
                ? 'Stop Pilot in Installed, then update the tools on the SD card. Your projects and settings are kept.'
                : controllerCount != 0
                ? 'Disconnect other controllers before updating the tools on the SD card.'
                : 'Update the tools on the SD card. Your projects and settings are kept.',
          ),
          action(
            'Update Toolkit tools',
            () => run(repairSetup),
            enabled: controllerCount == 0 && !installed.any((p) => p.running),
            icon: Icons.system_update_alt,
          ),
        ],
      ),
    ),
  );

  Widget errorNotice() {
    final lines = error!.split('\n');
    return Card(
      color: const Color(0xff33252b),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xffffb4ab)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Couldn’t complete this action',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: () => setState(() => error = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(lines.first),
            if (lines.length > 1)
              ExpansionTile(
                key: ValueKey(error),
                tilePadding: EdgeInsets.zero,
                title: const Text('Details'),
                children: [SelectableText(lines.skip(1).join('\n'))],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          const SizedBox(width: 38, child: MountIllustration(height: 38)),
          const SizedBox(width: 10),
          const Expanded(child: Text('Polaris')),
        ],
      ),
      actions: [
        Tooltip(
          message: 'Change mount',
          child: TextButton(
            onPressed: busy ? null : () => run(changeMount),
            child: const Text('Change mount'),
          ),
        ),
        IconButton(
          tooltip: 'About Mount Mischief Toolkit',
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const ToolkitAbout())),
          icon: const Icon(Icons.info_outline),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (startup != null) StartupProgressCard(progress: startup!),
          if (installation != null)
            InstallationProgressCard(progress: installation!),
          if (busy && startup?.active != true && installation?.active != true)
            const LinearProgressIndicator(),
          if (busy && startup?.active != true && installation?.active != true)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Keep Toolkit open and stay on this network until the operation finishes.',
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (installation?.active != true &&
                      message !=
                          'Download a project, then connect to your device Wi-Fi.')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        message,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xffc9c4d8),
                        ),
                      ),
                    ),
                  if (error != null) errorNotice(),
                  [devicePage, catalogPage, installedPage][tab](),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (value) => setState(() => tab = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.router_outlined),
          label: 'Device',
        ),
        NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          label: 'Catalog',
        ),
        NavigationDestination(icon: Icon(Icons.apps), label: 'Installed'),
      ],
    ),
  );
}
