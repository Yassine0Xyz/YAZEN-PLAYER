import 'dart:ui' show FontFeature;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';
import '../core/theme/theme_tokens.dart';

Future<void> showThemePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (_) => const _ThemePickerSheet(),
  );
}

class _ThemePickerSheet extends StatelessWidget {
  const _ThemePickerSheet();

  static const _palette = <Color>[
    Color(0xFF7C5CFC),
    Color(0xFF4F46E5),
    Color(0xFF2563EB),
    Color(0xFF0891B2),
    Color(0xFF0F9D78),
    Color(0xFF65A30D),
    Color(0xFFEAB308),
    Color(0xFFF97316),
    Color(0xFFEF4444),
    Color(0xFFDB2777),
    Color(0xFF9333EA),
    Color(0xFF64748B),
    Color(0xFF0F172A),
    Color(0xFF1F2937),
    Color(0xFFE2E8F0),
    Color(0xFFFFFFFF),
  ];

  static const _roles = <(String, String)>[
    ('background', 'Background'),
    ('surface', 'Surface'),
    ('surfaceElevated', 'Elevated surface'),
    ('surfaceMuted', 'Muted surface'),
    ('accent', 'Primary / accent'),
    ('accentStrong', 'Secondary accent'),
    ('textPrimary', 'Primary text'),
    ('textSecondary', 'Secondary text'),
    ('divider', 'Borders & dividers'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final tokens = theme.tokens;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: tokens.divider),
          ),
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: tokens.divider,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Appearance & Themes',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Choose a preset, use your own wallpaper, or tune every app color.',
                    style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'PRESET THEMES',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        EchoThemePreset.values.map((preset) {
                          final presetTokens = ThemeTokens.fromPreset(preset);
                          final selected =
                              theme.preset == preset && !theme.hasCustomTheme;
                          return ChoiceChip(
                            selected: selected,
                            label: Text(preset.label),
                            avatar: CircleAvatar(
                              backgroundColor: presetTokens.accent,
                              radius: 7,
                            ),
                            onSelected: (_) => theme.setPreset(preset),
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'YOUR WALLPAPER',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (theme.customBackground != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 116,
                        width: double.infinity,
                        child: Image(
                          image: theme.customBackground!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final selectedFile = await FilePicker.pickFile(
                                type: FileType.image,
                              );
                              final path = selectedFile?.path;
                              if (path != null) {
                                await theme.setCustomBackgroundPath(path);
                              }
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not load that wallpaper image.',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                            }
                          },
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(
                            theme.hasCustomBackground
                                ? 'Change image'
                                : 'Choose image',
                          ),
                        ),
                      ),
                      if (theme.hasCustomBackground) ...<Widget>[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Remove wallpaper',
                          onPressed: theme.clearCustomBackground,
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'CUSTOM COLOR PALETTE',
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: theme.resetCustomTheme,
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  Text(
                    'Changes preview instantly across the app and are saved automatically.',
                    style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  ..._roles.map((role) {
                    final current = _readColor(tokens, role.$1);
                    return _ThemeColorRole(
                      label: role.$2,
                      color: current,
                      palette: _palette,
                      onSelect: (color) => theme.setCustomColor(role.$1, color),
                    );
                  }),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: tokens.surfaceElevated,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: tokens.divider),
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: tokens.accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            color: tokens.isLight ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Live theme preview',
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Your selected colors are already applied behind this panel.',
                                style: TextStyle(
                                  color: tokens.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _readColor(ThemeTokens tokens, String key) => switch (key) {
    'background' => tokens.background,
    'surface' => tokens.surface,
    'surfaceElevated' => tokens.surfaceElevated,
    'surfaceMuted' => tokens.surfaceMuted,
    'accent' => tokens.accent,
    'accentStrong' => tokens.accentStrong,
    'textPrimary' => tokens.textPrimary,
    'textSecondary' => tokens.textSecondary,
    'divider' => tokens.divider,
    _ => tokens.accent,
  };
}

class _ThemeColorRole extends StatelessWidget {
  const _ThemeColorRole({
    required this.label,
    required this.color,
    required this.palette,
    required this.onSelect,
  });

  final String label;
  final Color color;
  final List<Color> palette;
  final ValueChanged<Color> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeProvider>().tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.divider),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 10,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              ...palette.map(
                (swatch) => InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onSelect(swatch),
                  child: Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            swatch == color
                                ? tokens.textPrimary
                                : tokens.divider,
                        width: swatch == color ? 2 : 0.7,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Choose any color',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final picked = await showDialog<Color>(
                    context: context,
                    builder: (_) => _HsvColorDialog(initial: color),
                  );
                  if (picked != null) onSelect(picked);
                },
                icon: const Icon(Icons.colorize_rounded, size: 18),
              ),
            ],
          ),
          Divider(height: 14, color: tokens.divider),
        ],
      ),
    );
  }
}

class _HsvColorDialog extends StatefulWidget {
  const _HsvColorDialog({required this.initial});
  final Color initial;
  @override
  State<_HsvColorDialog> createState() => _HsvColorDialogState();
}

class _HsvColorDialogState extends State<_HsvColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hexController = TextEditingController(
    text:
        widget.initial.toARGB32().toRadixString(16).substring(2).toUpperCase(),
  );
  String? _hexError;

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor value) {
    setState(() {
      _hsv = value;
      _hexError = null;
      _hexController.text =
          value
              .toColor()
              .toARGB32()
              .toRadixString(16)
              .substring(2)
              .toUpperCase();
    });
  }

  void _applyHex(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null || normalized.length != 6) {
      setState(() => _hexError = 'Enter a valid 6-digit HEX color.');
      return;
    }
    setState(() {
      _hsv = HSVColor.fromColor(Color(0xFF000000 | parsed));
      _hexError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: const Text('Choose a custom color'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 48,
              width: double.infinity,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 16),
            _slider(
              'Hue',
              _hsv.hue,
              360,
              (value) => _setHsv(_hsv.withHue(value)),
            ),
            _slider(
              'Saturation',
              _hsv.saturation,
              1,
              (value) => _setHsv(_hsv.withSaturation(value)),
            ),
            _slider(
              'Brightness',
              _hsv.value,
              1,
              (value) => _setHsv(_hsv.withValue(value)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hexController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'HEX color',
                prefixText: '#',
                errorText: _hexError,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _applyHex,
            ),
            const SizedBox(height: 8),
            Text(
              '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
              style: const TextStyle(
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _hexError == null ? () => Navigator.pop(context, color) : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double max,
    ValueChanged<double> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      Slider(
        value: value.clamp(0, max).toDouble(),
        min: 0,
        max: max,
        onChanged: onChanged,
      ),
    ],
  );
}
