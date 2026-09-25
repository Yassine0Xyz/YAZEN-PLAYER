import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_provider.dart';
import '../../../widgets/echo_motion.dart';
import '../../../models/media_track.dart';

class LibraryTabs extends StatelessWidget {
  const LibraryTabs({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final LibraryTab selected;
  final ValueChanged<LibraryTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: LibraryTab.values.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = LibraryTab.values[index];
          final isSelected = selected == tab;
          return AnimatedScale(
            scale: isSelected ? 1.035 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: EchoPressable(
              onTap: () => onSelected(tab),
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow:
                      isSelected
                          ? <BoxShadow>[
                            BoxShadow(
                              color: tokens.accent.withValues(alpha: 0.22),
                              blurRadius: 14,
                              spreadRadius: 1,
                            ),
                          ]
                          : const <BoxShadow>[],
                ),
                child: ChoiceChip(
                  avatar: Icon(
                    _iconFor(tab),
                    size: 16,
                    color:
                        isSelected
                            ? (tokens.isLight ? Colors.white : Colors.black)
                            : tokens.textSecondary,
                  ),
                  label: Text(tab.label),
                  selected: isSelected,
                  onSelected: (_) => onSelected(tab),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    color:
                        isSelected
                            ? (tokens.isLight ? Colors.white : Colors.black)
                            : tokens.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: tokens.surface,
                  selectedColor: tokens.accent,
                  side: BorderSide(
                    color: isSelected ? tokens.accent : tokens.divider,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(LibraryTab tab) {
    return switch (tab) {
      LibraryTab.videos => Icons.ondemand_video_rounded,
      LibraryTab.songs => Icons.music_note_rounded,
      LibraryTab.playlists => Icons.queue_music_rounded,
      LibraryTab.folders => Icons.folder_rounded,
      LibraryTab.artists => Icons.person_rounded,
      LibraryTab.albums => Icons.album_rounded,
      LibraryTab.hidden => Icons.visibility_off_rounded,
    };
  }
}
