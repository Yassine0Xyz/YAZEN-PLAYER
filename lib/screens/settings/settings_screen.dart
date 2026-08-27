import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(builder: (_) => const SettingsScreen());
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _appVersion = '0.1.0+1';
  static const _equalizerKey = 'yazen.settings.equalizer_enabled';
  static const _surroundKey = 'yazen.settings.surround_enabled';
  static const _speedKey = 'yazen.settings.playback_speed';

  bool _equalizerEnabled = true;
  bool _surroundEnabled = false;
  double _playbackSpeed = 1.0;
  bool _preferencesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final tokens = theme.tokens;
    final controller = context.read<HybridMusicController>();

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
        children: <Widget>[
          _SectionLabel(label: 'Appearance', tokens: tokens),
          _SettingsCard(
            tokens: tokens,
            child: RadioGroup<EchoThemePreset>(
              groupValue: theme.preset,
              onChanged: (value) {
                if (value != null) theme.setPreset(value);
              },
              child: Column(
                children: EchoThemePreset.values
                    .map((preset) => _ThemeOption(preset: preset))
                    .toList(growable: false),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel(label: 'Audio and playback', tokens: tokens),
          _SettingsCard(
            tokens: tokens,
            child: Column(
              children: <Widget>[
                _PreferenceSwitch(
                  icon: Icons.equalizer_rounded,
                  title: 'Equalizer',
                  subtitle:
                      controller.audioHandler.equalizerAvailable
                          ? 'Use the active Android audio effect profile'
                          : 'Unavailable on this device; playback remains stable',
                  value: _equalizerEnabled,
                  enabled:
                      _preferencesLoaded &&
                      controller.audioHandler.equalizerAvailable,
                  onChanged: (value) => _setEqualizer(controller, value),
                ),
                Divider(color: tokens.divider, height: 1),
                _PreferenceSwitch(
                  icon: Icons.surround_sound_rounded,
                  title: '3D surround audio',
                  subtitle: 'Enable the optional native spatial effect',
                  value: _surroundEnabled,
                  enabled: _preferencesLoaded,
                  onChanged: (value) => _setSurround(controller, value),
                ),
                Divider(color: tokens.divider, height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.speed_rounded, color: tokens.accent),
                  title: const Text(
                    'Playback speed',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${_playbackSpeed.toStringAsFixed(2)}×',
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                  trailing: DropdownButton<double>(
                    value: _playbackSpeed,
                    items: const <DropdownMenuItem<double>>[
                      DropdownMenuItem(value: 0.75, child: Text('0.75×')),
                      DropdownMenuItem(value: 1.0, child: Text('1.00×')),
                      DropdownMenuItem(value: 1.25, child: Text('1.25×')),
                      DropdownMenuItem(value: 1.5, child: Text('1.50×')),
                      DropdownMenuItem(value: 2.0, child: Text('2.00×')),
                    ],
                    onChanged:
                        _preferencesLoaded
                            ? (value) {
                              if (value != null) _setSpeed(controller, value);
                            }
                            : null,
                  ),
                ),
                Divider(color: tokens.divider, height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.bedtime_outlined, color: tokens.accent),
                  title: const Text(
                    'Sleep timer',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _sleepTimerLabel(controller),
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                  trailing: TextButton(
                    onPressed: () => _chooseSleepTimer(controller),
                    child: const Text('Change'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel(label: 'Storage', tokens: tokens),
          _SettingsCard(
            tokens: tokens,
            child: Column(
              children: <Widget>[
                FutureBuilder<int>(
                  future: controller.audioHandler.cache.totalBytes(),
                  builder: (context, snapshot) {
                    final size =
                        snapshot.data == null
                            ? 'Calculating…'
                            : _formatBytes(snapshot.data!);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.sd_storage_outlined,
                        color: tokens.accent,
                      ),
                      title: const Text(
                        'YouTube audio cache',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '$size used · 512 MB maximum',
                        style: TextStyle(color: tokens.textSecondary),
                      ),
                      trailing: TextButton(
                        onPressed: () => _clearCache(controller),
                        child: const Text('Clear'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel(label: 'About YAZEN', tokens: tokens),
          _SettingsCard(
            tokens: tokens,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.graphic_eq_rounded, color: tokens.accent),
              title: const Text(
                'YAZEN',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                'Version $_appVersion',
                style: TextStyle(color: tokens.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _equalizerEnabled = preferences.getBool(_equalizerKey) ?? true;
      _surroundEnabled = preferences.getBool(_surroundKey) ?? false;
      _playbackSpeed = preferences.getDouble(_speedKey) ?? 1.0;
      _preferencesLoaded = true;
    });
    final controller = context.read<HybridMusicController>();
    await controller.audioHandler.setSpeed(_playbackSpeed);
    await controller.audioHandler.setEqualizerEnabled(_equalizerEnabled);
    await controller.audioHandler.setThreeDSurroundEnabled(_surroundEnabled);
  }

  Future<void> _setSpeed(HybridMusicController controller, double value) async {
    setState(() => _playbackSpeed = value);
    await controller.audioHandler.setSpeed(value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_speedKey, value);
  }

  String _sleepTimerLabel(HybridMusicController controller) {
    final remaining = controller.audioHandler.sleepTimerRemaining;
    if (remaining == null) return 'Off';
    return '${remaining.inMinutes} min remaining';
  }

  Future<void> _chooseSleepTimer(HybridMusicController controller) async {
    final minutes = await showModalBottomSheet<int?>(
      context: context,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  title: const Text('Off'),
                  onTap: () => Navigator.pop(context, 0),
                ),
                for (final value in <int>[15, 30, 60, 90])
                  ListTile(
                    title: Text('$value minutes'),
                    onTap: () => Navigator.pop(context, value),
                  ),
              ],
            ),
          ),
    );
    if (minutes == null) return;
    controller.audioHandler.setSleepTimer(
      minutes == 0 ? null : Duration(minutes: minutes),
    );
    if (mounted) setState(() {});
  }

  Future<void> _setPreference(
    String key,
    bool value,
    void Function(bool value) apply,
  ) async {
    apply(value);
    setState(() {});
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(key, value);
  }

  Future<void> _setEqualizer(
    HybridMusicController controller,
    bool value,
  ) async {
    await controller.audioHandler.setEqualizerEnabled(value);
    await _setPreference(
      _equalizerKey,
      value,
      (next) => _equalizerEnabled = next,
    );
  }

  Future<void> _setSurround(
    HybridMusicController controller,
    bool value,
  ) async {
    await controller.audioHandler.setThreeDSurroundEnabled(value);
    await _setPreference(
      _surroundKey,
      value,
      (next) => _surroundEnabled = next,
    );
  }

  Future<void> _clearCache(HybridMusicController controller) async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear YouTube cache?'),
            content: const Text(
              'Completed offline audio will be removed. Your playlists and favorites will remain untouched.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear cache'),
              ),
            ],
          ),
    );
    if (shouldClear != true) return;
    await controller.audioHandler.cache.clearAll();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('YouTube cache cleared')));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.tokens});

  final String label;
  final ThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.tokens, required this.child});

  final ThemeTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.divider),
      ),
      child: child,
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.preset});

  final EchoThemePreset preset;

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.fromPreset(preset);
    return InkWell(
      onTap:
          () => RadioGroup.maybeOf<EchoThemePreset>(context)?.onChanged(preset),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: <Color>[tokens.accentStrong, tokens.accent],
                ),
              ),
              child: Icon(
                Icons.palette_outlined,
                color: tokens.isLight ? Colors.white : Colors.black,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                preset.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Radio<EchoThemePreset>(value: preset),
          ],
        ),
      ),
    );
  }
}

class _PreferenceSwitch extends StatelessWidget {
  const _PreferenceSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: tokens.accent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, style: TextStyle(color: tokens.textSecondary)),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}
