import 'package:flutter/material.dart';

class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color});

  final Color? color;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final t = (_controller.value + index * 0.18) % 1.0;
            final wave = (1 - (t * 2 - 1).abs()).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Transform.translate(
                offset: Offset(0, -3 * wave),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.35 + 0.55 * wave),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
