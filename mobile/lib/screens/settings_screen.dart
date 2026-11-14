import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils.dart';
import '../state/app_controller.dart';
import '../state/app_scope.dart';
import '../widgets/avatar.dart';
import '../widgets/makasi_logo.dart';
import 'account_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _clearChats(
    BuildContext context,
    AppController controller,
  ) async {
    if (controller.streaming) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendez la fin de la réponse en cours.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tout supprimer ?'),
          content: Text(
            controller.isSignedIn
                ? 'Toutes vos discussions seront supprimées de l’application, sur ce téléphone. Cette action est définitive. Pensez à les enregistrer avant si vous voulez les conserver.'
                : 'Toutes les discussions enregistrées sur ce téléphone seront supprimées. Cette action est définitive. Pensez à les enregistrer avant si vous voulez les conserver.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Tout supprimer'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    await controller.clearAllChats();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Toutes les discussions ont été supprimées.')),
    );
  }

  Future<void> _exportChats(BuildContext context, AppController controller) async {
    try {
      final uri = await controller.exportChats();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              uri == null
                  ? 'Aucune conversation à enregistrer pour le moment.'
                  : 'Conversations enregistrées. Conservez ce fichier avant de désinstaller l’application.',
            ),
          ),
        );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(friendlyAuthMessage(error))),
        );
    }
  }

  Future<void> _openSite(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir le site.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Paramètres'),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              _Section(
                label: 'APPARENCE',
                child: _Card(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thème',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontSize: 13),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Choisissez l’apparence de Makasi.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _ThemeChoice(
                                icon: Icons.brightness_auto_rounded,
                                label: 'Système',
                                selected:
                                    controller.themeMode == ThemeMode.system,
                                onTap: () =>
                                    controller.setThemeMode(ThemeMode.system),
                              ),
                              const SizedBox(width: 8),
                              _ThemeChoice(
                                icon: Icons.light_mode_outlined,
                                label: 'Clair',
                                selected:
                                    controller.themeMode == ThemeMode.light,
                                onTap: () =>
                                    controller.setThemeMode(ThemeMode.light),
                              ),
                              const SizedBox(width: 8),
                              _ThemeChoice(
                                icon: Icons.dark_mode_outlined,
                                label: 'Sombre',
                                selected:
                                    controller.themeMode == ThemeMode.dark,
                                onTap: () =>
                                    controller.setThemeMode(ThemeMode.dark),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _Section(
                label: 'COMPTE',
                child: _Card(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => showAccountSheet(context),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
                          child: Row(
                            children: [
                              MakasiAvatar(
                                name: controller.userName,
                                guest: !controller.isSignedIn,
                                size: 40,
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      controller.isSignedIn
                                          ? (controller.userName.isEmpty
                                              ? controller.userEmail
                                              : controller.userName)
                                          : 'Mode invité',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(fontSize: 13),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      controller.isSignedIn
                                          ? controller.userEmail
                                          : 'Vos discussions restent sur cet appareil',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontSize: 10.5,
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: controller.isSignedIn
                                      ? const Color(0xFF10B981)
                                          .withValues(alpha: 0.1)
                                      : colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  controller.isSignedIn
                                      ? 'Compte local'
                                      : 'Créer un compte',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        fontSize: 9.5,
                                        letterSpacing: 0,
                                        fontWeight: FontWeight.w600,
                                        color: controller.isSignedIn
                                            ? const Color(0xFF059669)
                                            : colors.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (controller.isSignedIn) ...[
                      const Divider(height: 1, indent: 13, endIndent: 13),
                      _RowAction(
                        icon: Icons.save_alt_rounded,
                        title: 'Enregistrer mes conversations',
                        subtitle: 'À conserver avant une désinstallation.',
                        onTap: () => _exportChats(context, controller),
                      ),
                    ],
                  ],
                ),
              ),
              _Section(
                label: 'MÉMOIRE ET DONNÉES',
                child: _Card(
                  children: [
                    _RowAction(
                      icon: Icons.phone_iphone_rounded,
                      title: 'Mémoire de l’application',
                      subtitle: controller.isSignedIn
                          ? 'Votre compte et vos conversations restent sur ce téléphone.'
                          : 'Vos conversations restent sur ce téléphone.',
                      onTap: () => showAccountSheet(context),
                    ),
                    const Divider(height: 1, indent: 13, endIndent: 13),
                    _RowAction(
                      icon: Icons.save_alt_rounded,
                      title: 'Enregistrer mes conversations',
                      subtitle: 'Fichier Markdown à conserver hors du téléphone.',
                      onTap: () => _exportChats(context, controller),
                    ),
                    const Divider(height: 1, indent: 13, endIndent: 13),
                    _RowAction(
                      icon: Icons.delete_outline_rounded,
                      title: 'Supprimer toutes les discussions',
                      subtitle: 'Dans l’application, sur cet appareil.',
                      destructive: true,
                      onTap: () => _clearChats(context, controller),
                    ),
                  ],
                ),
              ),
              _Section(
                label: 'SERVICE',
                child: _Card(
                  children: [
                    _InfoRow(
                      icon: Icons.dns_outlined,
                      label: 'Serveur',
                      value: controller.displayServer,
                    ),
                    const Divider(height: 1, indent: 13, endIndent: 13),
                    _InfoRow(
                      icon: Icons.phone_iphone_rounded,
                      label: 'Compte',
                      value: controller.isSignedIn
                          ? 'Enregistré sur ce téléphone'
                          : 'Mode invité, sur ce téléphone',
                    ),
                    const Divider(height: 1, indent: 13, endIndent: 13),
                    _InfoRow(
                      icon: Icons.shield_outlined,
                      label: 'Sécurité',
                      value: 'Les clés de l’IA restent sur le serveur.',
                    ),
                  ],
                ),
              ),
              _Section(
                label: 'À PROPOS',
                child: _Card(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(13, 14, 13, 13),
                      child: Row(
                        children: [
                          const MakasiLogo(size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Makasi AI',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontSize: 13.5),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  'Version 1.0.0',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontSize: 10.5,
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, indent: 13, endIndent: 13),
                    _RowAction(
                      icon: Icons.public_rounded,
                      title: 'Ouvrir le site Makasi',
                      subtitle: controller.displayServer,
                      onTap: () => _openSite(context, controller.displayServer),
                    ),
                    const Divider(height: 1, indent: 13, endIndent: 13),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
                      child: Text(
                        'Makasi AI peut faire des erreurs. Vérifiez les informations importantes. '
                        'Vos discussions vous appartiennent et ne sont jamais utilisées pour entraîner un modèle public.',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 9.5,
                              height: 1.5,
                              letterSpacing: 0,
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 7),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 0.7,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 56,
            decoration: BoxDecoration(
              color: selected
                  ? colors.primary.withValues(alpha: 0.1)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? colors.primary.withValues(alpha: 0.4)
                    : colors.outline,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w500,
                    color:
                        selected ? colors.primary : colors.onSurfaceVariant,
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

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.title,
    this.subtitle,
    this.destructive = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tint = destructive ? colors.error : colors.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
          child: Row(
            children: [
              Icon(icon, size: 18, color: tint),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: destructive ? colors.error : colors.onSurface,
                          ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              height: 1.4,
                              letterSpacing: 0,
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (onTap == null)
                const SizedBox.shrink()
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 11),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    height: 1.4,
                    color: colors.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
