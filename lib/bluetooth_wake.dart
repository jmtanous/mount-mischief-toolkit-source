import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BluetoothWakeProgress { scanning, selecting, waking, failed }

const wakeChannel = MethodChannel('org.mountmischief/toolkit');

/// Returns true only after a selected, freshly discovered mount connected.
/// Wi-Fi availability and SSH identity must still be checked by normal pairing.
Future<bool> showBluetoothWake(
  BuildContext context, {
  ValueChanged<BluetoothWakeProgress>? onProgress,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BluetoothWakeDialog(onProgress: onProgress),
    ) ==
    true;

class BluetoothWakeDialog extends StatefulWidget {
  final ValueChanged<BluetoothWakeProgress>? onProgress;
  const BluetoothWakeDialog({super.key, this.onProgress});
  @override
  State<BluetoothWakeDialog> createState() => _BluetoothWakeDialogState();
}

class _BluetoothWakeDialogState extends State<BluetoothWakeDialog> {
  List<Map<String, String>> devices = [];
  String? remembered;
  String? failure;
  String status = 'Scanning for nearby Polaris mounts…';
  bool working = true;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(scan());
  }

  @override
  void dispose() {
    generation++;
    unawaited(
      wakeChannel.invokeMethod<void>('bluetoothCancel').catchError((_) {}),
    );
    super.dispose();
  }

  Future<void> scan() async {
    final attempt = ++generation;
    setState(() {
      working = true;
      failure = null;
      devices = [];
      status = 'Scanning for nearby Polaris mounts…';
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || attempt != generation) return;
      widget.onProgress?.call(BluetoothWakeProgress.scanning);
      remembered = prefs.getString('bluetooth_mount');
      final rows =
          await wakeChannel.invokeListMethod<dynamic>('bluetoothScan') ?? [];
      if (!mounted || attempt != generation) return;
      setState(() {
        devices = rows.map((r) => Map<String, String>.from(r as Map)).toList();
        devices.sort(
          (a, b) => a['address'] == remembered
              ? -1
              : b['address'] == remembered
              ? 1
              : a['name']!.compareTo(b['name']!),
        );
        working = false;
        status = devices.isEmpty
            ? 'No Polaris found. Check that it is powered on and nearby. On older Android, also enable Location.'
            : 'Select your mount. Bluetooth names are not proof of device identity; SSH pairing still verifies its fingerprint.';
      });
      widget.onProgress?.call(
        devices.isEmpty
            ? BluetoothWakeProgress.failed
            : BluetoothWakeProgress.selecting,
      );
    } catch (e) {
      failed(e, attempt);
    }
  }

  void failed(Object e, int attempt) {
    if (!mounted || attempt != generation) return;
    widget.onProgress?.call(BluetoothWakeProgress.failed);
    setState(() {
      working = false;
      failure = e is PlatformException ? e.message ?? e.code : e.toString();
    });
  }

  Future<void> wake(Map<String, String> device) async {
    widget.onProgress?.call(BluetoothWakeProgress.waking);
    final attempt = ++generation;
    setState(() {
      working = true;
      failure = null;
      status = 'Waking Wi-Fi on ${device['name']}…';
    });
    try {
      await wakeChannel.invokeMethod<dynamic>('bluetoothWake', {
        'address': device['address'],
      });
      if (!mounted || attempt != generation) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bluetooth_mount', device['address']!);
      if (mounted && attempt == generation) Navigator.pop(context, true);
    } catch (e) {
      failed(e, attempt);
    }
  }

  Future<void> settings(String method) async {
    try {
      await wakeChannel.invokeMethod<void>(method);
    } catch (e) {
      failed(e, generation);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Wake Polaris Wi-Fi'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(failure ?? status),
            if (working)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
            if (!working && failure == null)
              for (final device in devices)
                ListTile(
                  title: Text(device['name']!),
                  subtitle: Text(
                    '${device['address']}${device['address'] == remembered ? ' • Previous selection' : ''}',
                  ),
                  onTap: () => wake(device),
                ),
            if (!working) ...[
              TextButton(
                onPressed: () => settings('bluetoothSettings'),
                child: const Text('Bluetooth settings'),
              ),
              TextButton(
                onPressed: () => settings('appSettings'),
                child: const Text('App permissions'),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      if (!working)
        TextButton(onPressed: scan, child: const Text('Scan again')),
    ],
  );
}
