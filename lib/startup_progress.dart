import 'package:material_ui/material_ui.dart';

enum StartupStage { checking, launching, waiting, handover, verifying }

enum StartupCleanup { stopping, confirmed, uncertain }

class StartupEvent {
  final StartupStage stage;
  final bool responseReceived;
  final bool alreadyRunning;
  final StartupCleanup? cleanup;
  const StartupEvent(
    this.stage, {
    this.responseReceived = false,
    this.alreadyRunning = false,
    this.cleanup,
  });
}

class StartupProgress extends ChangeNotifier {
  StartupStage stage = StartupStage.checking;
  final completed = <StartupStage>{};
  StartupCleanup? cleanup;
  bool active = true, ready = false, alreadyRunning = false;
  String? failure;
  void update(StartupEvent event) {
    if (!active) return;
    if (stage != event.stage) completed.add(stage);
    stage = event.stage;
    cleanup = event.cleanup ?? cleanup;
    alreadyRunning = alreadyRunning || event.alreadyRunning;
    notifyListeners();
  }

  void finish({Object? error}) {
    active = false;
    failure = error?.toString();
    ready = error == null && !alreadyRunning;
    if (error == null) completed.add(stage);
    notifyListeners();
  }
}

class StartupProgressCard extends StatelessWidget {
  final StartupProgress progress;
  const StartupProgressCard({super.key, required this.progress});
  static const labels = [
    'Check mount and controllers',
    'Start Pilot',
    'Wait for Pilot to respond',
    'Hand connection to Pilot',
    'Verify connection and refresh status',
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: progress,
    builder: (context, _) {
      final p = progress;
      final failed = p.failure != null || p.cleanup != null;
      final title = p.failure != null
          ? 'Pilot startup failed'
          : p.cleanup != null
          ? 'Pilot startup cleanup'
          : p.active
          ? 'Starting Alpaca Pilot'
          : p.alreadyRunning
          ? 'Pilot was already running'
          : 'Pilot ready';
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
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final stage in StartupStage.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          if (p.active && stage == p.stage && !failed)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: MediaQuery.disableAnimationsOf(context)
                                  ? const Icon(Icons.more_horiz, size: 16)
                                  : const CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                            )
                          else
                            Icon(
                              p.completed.contains(stage)
                                  ? Icons.check_circle_outline
                                  : failed && stage == p.stage
                                  ? Icons.error_outline
                                  : Icons.radio_button_unchecked,
                              size: 16,
                              color: p.completed.contains(stage)
                                  ? const Color(0xff44e2cd)
                                  : failed && stage == p.stage
                                  ? const Color(0xffffb4ab)
                                  : const Color(0xff938ea1),
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              labels[stage.index],
                              style: TextStyle(
                                fontSize: 12,
                                color: stage == p.stage
                                    ? const Color(0xffe6e0ee)
                                    : const Color(0xff938ea1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (p.active && p.cleanup == null && !p.alreadyRunning) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Alpaca Pilot startup can take up to 3 minutes.',
                      style: TextStyle(fontSize: 12, color: Color(0xffc9c4d8)),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (p.cleanup != null)
                    Text(switch (p.cleanup!) {
                      StartupCleanup.stopping =>
                        'Stopping Pilot after startup failed…',
                      StartupCleanup.confirmed =>
                        'Cleanup confirmed: Pilot stopped.',
                      StartupCleanup.uncertain => 'Cleanup unconfirmed. Reconnect and inspect before retrying.',
                    }, style: const TextStyle(fontSize: 12)),
                  if (p.failure != null)
                    Text(
                      p.failure!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xffffb4ab),
                      ),
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
