import 'package:material_ui/material_ui.dart';

class InstallationEvent {
  final String stage;
  final int? done, total;
  final String? detail;
  const InstallationEvent(this.stage, {this.done, this.total, this.detail});
}

class InstallationProgress extends ChangeNotifier {
  final String title;
  final List<String> stages;
  String stage = 'toolkit';
  int? done, total;
  String? detail;
  final completed = <String>{};
  bool active = true;
  String? failure;
  InstallationProgress(this.title, {bool toolkitOnly = false})
    : stages = toolkitOnly
          ? ['toolkit', 'finish']
          : [
              'toolkit',
              'upload',
              'checksum',
              'scan',
              'extract',
              'verify',
              'activate',
              'finish',
            ];
  void update(InstallationEvent event) {
    if (!active || !stages.contains(event.stage)) return;
    if (stage != event.stage) completed.add(stage);
    stage = event.stage;
    detail = event.detail;
    done = event.done;
    total = event.total;
    notifyListeners();
  }

  void finish({Object? error}) {
    if (!active) return;
    failure = error?.toString();
    active = false;
    if (error == null) completed.add(stage);
    notifyListeners();
  }
}

class InstallationProgressCard extends StatelessWidget {
  final InstallationProgress progress;
  const InstallationProgressCard({super.key, required this.progress});
  static const labels = {
    'toolkit': 'Prepare Toolkit on the SD card',
    'upload': 'Transfer package to the mount',
    'checksum': 'Check package checksum',
    'scan': 'Check archive contents',
    'extract': 'Unpack package',
    'verify': 'Verify installed files',
    'activate': 'Save settings and activate package',
    'finish': 'Refresh installed projects',
  };
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: progress,
    builder: (context, _) {
      final p = progress;
      final measured = p.total != null && p.total! > 0 && p.done != null;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .4,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.active
                        ? p.title
                        : p.failure != null
                        ? 'Installation stopped'
                        : 'Installation complete',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final stage in p.stages)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          if (p.active &&
                              stage == p.stage &&
                              !MediaQuery.disableAnimationsOf(context))
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              p.completed.contains(stage)
                                  ? Icons.check_circle_outline
                                  : stage == p.stage && p.failure != null
                                  ? Icons.error_outline
                                  : Icons.radio_button_unchecked,
                              size: 16,
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              labels[stage]!,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (p.active && p.detail != null)
                    Text(p.detail!, style: const TextStyle(fontSize: 12)),
                  if (p.active && measured) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (p.done! / p.total!).clamp(0, 1),
                    ),
                    Text(
                      p.stage == 'upload' || p.stage == 'toolkit'
                          ? '${(p.done! / 1048576).toStringAsFixed(1)} / ${(p.total! / 1048576).toStringAsFixed(1)} MB sent'
                          : '${p.done} / ${p.total} files',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                  if (p.active)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'This can take several minutes. Keep Toolkit open and stay connected to the mount.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (p.failure != null)
                    const Text(
                      'See the error details below before retrying.',
                      style: TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
