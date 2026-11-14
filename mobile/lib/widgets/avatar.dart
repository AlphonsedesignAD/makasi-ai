import 'package:flutter/material.dart';

import '../core/theme.dart';

class MakasiAvatar extends StatelessWidget {
  const MakasiAvatar({
    super.key,
    required this.name,
    this.size = 38,
    this.guest = false,
  });

  final String name;
  final double size;
  final bool guest;

  String get _initial {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    return clean.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (guest) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(color: colors.outline),
        ),
        child: Icon(
          Icons.person_outline_rounded,
          size: size * 0.5,
          color: colors.onSurfaceVariant,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: MakasiTheme.gradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: MakasiTheme.brandMid.withValues(alpha: 0.22),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        _initial,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
