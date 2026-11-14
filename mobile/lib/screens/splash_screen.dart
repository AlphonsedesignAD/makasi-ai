import 'package:flutter/material.dart';

import '../widgets/makasi_logo.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.surface,
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.86, end: 1),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) =>
                      Transform.scale(scale: value, child: child),
                  child: const MakasiLogo(size: 78, glow: true),
                ),
                const SizedBox(height: 24),
                Text(
                  'Makasi AI',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontSize: 24,
                        letterSpacing: -0.6,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Votre assistant personnel',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        color: colors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colors.primary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
