import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const communityNotice =
    'Independent community project. Not affiliated with or endorsed by Benro.';
const supportUrl = String.fromEnvironment(
  'SUPPORT_URL',
  defaultValue: 'https://buymeacoffee.com/jmtanousk',
);

Uri? supportDestination(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
          uri.scheme == 'https' &&
          ['buymeacoffee.com', 'www.buymeacoffee.com'].contains(uri.host) &&
          uri.pathSegments.where((s) => s.isNotEmpty).isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

class SupportButton extends StatelessWidget {
  final String url;
  const SupportButton({super.key, this.url = supportUrl});
  @override
  Widget build(BuildContext context) {
    final destination = supportDestination(url);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(148, 44),
            side: const BorderSide(color: Color(0xff484555)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: destination == null
              ? null
              : () async {
                  try {
                    if (!await launchUrl(
                      destination,
                      mode: LaunchMode.externalApplication,
                    )) {
                      throw StateError('Browser unavailable');
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not open the support page. Try again with internet access.',
                          ),
                        ),
                      );
                    }
                  }
                },
          icon: const Icon(
            Icons.sports_bar_outlined,
            size: 18,
            color: Color(0xffffb780),
          ),
          label: const Text('Buy me a beer'),
        ),
        Text(
          destination == null
              ? 'Tip jar coming soon'
              : 'Optional • Opens browser • Internet required',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Session-only gate: rebuilding or returning from another Activity does not
/// reset acknowledgment; a new application state starts at welcome again.
class EntryFlow extends StatefulWidget {
  final Widget Function(VoidCallback changeMount) workspace;
  const EntryFlow({super.key, required this.workspace});
  @override
  State<EntryFlow> createState() => _EntryFlowState();
}

class _EntryFlowState extends State<EntryFlow> {
  int stage = 0;
  bool accepted = false;
  @override
  Widget build(BuildContext context) {
    if (stage == 2) return widget.workspace(() => setState(() => stage = 1));
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: EdgeInsets.all(16),
              children: stage == 0 ? welcome(context) : chooser(context),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> welcome(BuildContext context) => [
    const SizedBox(height: 4),
    const Center(child: ToolkitEmblem(size: 64)),
    const SizedBox(height: 14),
    const Text(
      'WELCOME TO',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 10,
        letterSpacing: 2,
        color: Color(0xffcabeff),
      ),
    ),
    const SizedBox(height: 4),
    Text(
      'Mount Mischief\nToolkit',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineLarge
          ?.copyWith(fontWeight: FontWeight.w700, height: 1.12),
    ),
    const SizedBox(height: 10),
    const Text(
      'It worked before I touched it.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 14, height: 1.4, color: Color(0xffcabeff)),
    ),
    const SizedBox(height: 20),
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff201e28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xff77612d)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: Color(0xfffbbf24),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Experimental software notice',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xfffbbf24),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'This app will break your mount. Probably your weekend, too. It is not meant to be used by anyone. Unfortunately, you appear to be someone.',
            style: TextStyle(fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff352012),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xff72501a)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seriously: this is experimental community software. Things can fail, settings or data can be lost, and your equipment could be damaged. There are no promises that it will work, or that troubleshooting will end before sunrise.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xfffde68a),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Continue only if you understand the risks and are prepared to recover your equipment.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: Color(0xfffde68a),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    Material(
      color: const Color(0xff1c1a24),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xff484555)),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        controlAffinity: ListTileControlAffinity.leading,
        value: accepted,
        onChanged: (value) => setState(() => accepted = value ?? false),
        title: const Text(
          'I understand this is experimental software and I accept the risks.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
      ),
    ),
    const SizedBox(height: 12),
    FilledButton(
      onPressed: accepted ? () => setState(() => stage = 1) : null,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text('Accept and continue'),
      ),
    ),
    const SizedBox(height: 4),
    TextButton(
      onPressed: () => SystemNavigator.pop(),
      child: const Text('Get me out of here'),
    ),
    const Divider(height: 28),
    const Text(
      'Find MMT useful? Buy me a beer.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xffc9c4d8)),
    ),
    const SizedBox(height: 10),
    const SupportButton(),
    const SizedBox(height: 18),
    const Text(
      communityNotice,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xff938ea1)),
    ),
  ];
  List<Widget> chooser(BuildContext context) => [
    const SizedBox(height: 8),
    Row(
      children: [
        const ToolkitEmblem(size: 36),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('Mount Mischief Toolkit', style: TextStyle(fontSize: 14)),
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
    const SizedBox(height: 24),
    Text('Choose your mount', style: Theme.of(context).textTheme.headlineLarge),
    const SizedBox(height: 8),
    const Text(
      'Select your mount.',
      style: TextStyle(color: Color(0xffc9c4d8)),
    ),
    const SizedBox(height: 16),
    Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xff484555)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => stage = 2),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  backgroundColor: Color(0xff005047),
                  side: BorderSide.none,
                  avatar: Icon(
                    Icons.verified_outlined,
                    size: 16,
                    color: Color(0xffb5fff1),
                  ),
                  label: Text(
                    'Supported',
                    style: TextStyle(fontSize: 12, color: Color(0xffb5fff1)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const MountIllustration(height: 210),
              const SizedBox(height: 16),
              Text(
                'Benro Polaris',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                'Motorized photography and astronomy mount',
                style: TextStyle(fontSize: 14, color: Color(0xffc9c4d8)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => setState(() => stage = 2),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Choose Polaris'),
              ),
            ],
          ),
        ),
      ),
    ),
    const SizedBox(height: 12),
    const Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.bluetooth, size: 20, color: Color(0xff938ea1)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'You’ll connect to your mount on the next screen.',
                style: TextStyle(fontSize: 14, color: Color(0xffc9c4d8)),
              ),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 24),
    const Text(
      communityNotice,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11, color: Color(0xff938ea1)),
    ),
  ];
}

/// Clay mount artwork shared with the Android launcher icon.
class ToolkitEmblem extends StatelessWidget {
  final double size;
  const ToolkitEmblem({super.key, this.size = 104});
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Mount Mischief Toolkit emblem',
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xff301044),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xff484555)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(size * 0.04),
        child: Image.asset(
          'assets/branding/bandaged-mount.png',
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}

/// Product-style artwork exported from the user's Stitch project.
class MountIllustration extends StatelessWidget {
  final double height;
  const MountIllustration({super.key, this.height = 160});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.asset(
      'assets/branding/polaris-stitch.png',
      height: height,
      width: double.infinity,
      fit: BoxFit.contain,
      semanticLabel: 'Benro Polaris mount',
    ),
  );
}

class ToolkitAbout extends StatelessWidget {
  const ToolkitAbout({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About & support')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Row(
            children: [
              ToolkitEmblem(size: 56),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mount Mischief Toolkit',
                      style: TextStyle(
                        fontFamily: 'RedHatDisplay',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Version 0.1.0',
                      style: TextStyle(fontSize: 12, color: Color(0xff938ea1)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Card(child: KeepScreenAwakeSetting()),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Support MMT',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 12),
                  Text('Find MMT useful? Buy me a beer.'),
                  SizedBox(height: 16),
                  SupportButton(),
                  SizedBox(height: 12),
                  Text(
                    'Tips are optional. All features are available without them.',
                    style: TextStyle(fontSize: 13, color: Color(0xffc9c4d8)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Open-source licenses'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Mount Mischief Toolkit',
                applicationVersion: '0.1.0',
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            communityNotice,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xff938ea1)),
          ),
        ],
      ),
    ),
  );
}

class KeepScreenAwakeSetting extends StatefulWidget {
  const KeepScreenAwakeSetting({super.key});
  @override
  State<KeepScreenAwakeSetting> createState() => _KeepScreenAwakeSettingState();
}

class _KeepScreenAwakeSettingState extends State<KeepScreenAwakeSetting> {
  static const channel = MethodChannel('org.mountmischief/toolkit');
  bool? enabled;
  bool saving = false;
  String? failure;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await channel.invokeMethod<bool>('getKeepScreenAwake');
      if (mounted) setState(() => enabled = value ?? false);
    } catch (_) {
      if (mounted) setState(() => failure = 'Screen setting unavailable');
    }
  }

  Future<void> change(bool value) async {
    setState(() { saving = true; failure = null; });
    try {
      await channel.invokeMethod<void>('setKeepScreenAwake', value);
      if (mounted) setState(() => enabled = value);
    } catch (_) {
      if (mounted) setState(() => failure = 'Could not save screen setting');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: const Text('Keep screen awake'),
    subtitle: Text(failure ?? 'While MMT is open. Uses more battery.'),
    value: enabled ?? false,
    onChanged: enabled == null || saving ? null : change,
  );
}
