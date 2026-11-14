import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../state/app_controller.dart';
import '../state/app_scope.dart';
import '../widgets/avatar.dart';
import '../widgets/gradient_button.dart';
import 'auth_screen.dart';

/// Ouvre la fiche du compte, depuis le tiroir ou les paramètres.
Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const AccountSheet(),
  );
}

class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key});

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  bool _busy = false;

  Future<void> _openAuth() async {
    final navigator = Navigator.of(context);
    navigator.pop();
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const AuthScreen(),
      ),
    );
  }

  Future<void> _rename(AppController controller) async {
    final text = TextEditingController(text: controller.userName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Votre nom'),
          content: TextField(
            controller: text,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Nom affiché dans Makasi',
              counterText: '',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(text.text),
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
    text.dispose();
    if (name == null || name.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      await controller.updateDisplayName(name.trim());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(friendlyAuthMessage(error))),
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(AppController controller) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final uri = await controller.exportChats();
      if (!mounted) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(friendlyAuthMessage(error))),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut(AppController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Se déconnecter ?'),
          content: const Text(
            'Votre compte sera retiré de ce téléphone. Vos conversations '
            'restent dans l’application : vous pourrez les retrouver en vous '
            'connectant à nouveau ou en continuant sans compte.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Se déconnecter'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context);
    await controller.signOut();
    if (!mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: controller.isSignedIn
            ? _SignedIn(
                controller: controller,
                busy: _busy,
                onRename: () => _rename(controller),
                onExport: () => _export(controller),
                onSignOut: () => _signOut(controller),
              )
            : _Guest(
                busy: _busy,
                onAuth: _openAuth,
                onExport: () => _export(controller),
                onClose: () => Navigator.of(context).pop(),
              ),
      ),
    );
  }
}

class _Guest extends StatelessWidget {
  const _Guest({
    required this.busy,
    required this.onAuth,
    required this.onExport,
    required this.onClose,
  });

  final bool busy;
  final VoidCallback onAuth;
  final VoidCallback onExport;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: MakasiAvatar(name: '', guest: true, size: 58)),
        const SizedBox(height: 14),
        Text(
          'Créez votre compte Makasi',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Un compte simple, enregistré sur ce téléphone, pour garder vos '
          'conversations dans l’application.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                height: 1.5,
              ),
        ),
        const SizedBox(height: 18),
        const _Feature(
          icon: Icons.phone_iphone_rounded,
          title: 'Vos conversations restent ici',
          subtitle: 'Elles sont conservées dans l’application.',
        ),
        const _Feature(
          icon: Icons.lock_outline_rounded,
          title: 'Un accès personnel',
          subtitle: 'Votre nom, votre e-mail et votre mot de passe.',
        ),
        const _Feature(
          icon: Icons.save_alt_rounded,
          title: 'Enregistrez avant de désinstaller',
          subtitle: 'Un fichier suffit pour conserver vos échanges.',
        ),
        const SizedBox(height: 12),
        _Warning(
          text: 'Si vous désinstallez l’application, votre compte et vos '
              'conversations seront supprimés. Enregistrez-les avant.',
          action: TextButton.icon(
            onPressed: busy ? null : onExport,
            icon: busy
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  )
                : const Icon(Icons.save_alt_rounded, size: 16),
            label: Text(busy ? 'Enregistrement…' : 'Enregistrer mes conversations'),
          ),
        ),
        const SizedBox(height: 20),
        GradientButton(
          label: 'Créer mon compte',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: onAuth,
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: onAuth,
          style: TextButton.styleFrom(
            foregroundColor: colors.onSurfaceVariant,
            minimumSize: const Size.fromHeight(40),
          ),
          child: const Text('J’ai déjà un compte'),
        ),
        TextButton(
          onPressed: onClose,
          style: TextButton.styleFrom(
            foregroundColor: colors.onSurfaceVariant,
            minimumSize: const Size.fromHeight(40),
          ),
          child: const Text('Continuer sans compte'),
        ),
        const SizedBox(height: 2),
        Text(
          'Sans compte, les discussions restent aussi sur cet appareil.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9.5,
                letterSpacing: 0,
                color: colors.onSurfaceVariant.withValues(alpha: 0.7),
              ),
        ),
      ],
    );
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn({
    required this.controller,
    required this.busy,
    required this.onRename,
    required this.onExport,
    required this.onSignOut,
  });

  final AppController controller;
  final bool busy;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = controller.userName.isEmpty
        ? controller.userEmail
        : controller.userName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: MakasiAvatar(name: controller.userName, size: 62),
        ),
        const SizedBox(height: 13),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 2),
        Text(
          controller.userEmail,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colors.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.phone_iphone_rounded,
                  size: 13,
                  color: colors.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  'Compte enregistré sur ce téléphone',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 9.5,
                        letterSpacing: 0,
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _Warning(
          text: 'Votre compte et vos conversations restent sur ce téléphone. '
              'Si vous désinstallez l’application, ils seront supprimés. '
              'Enregistrez vos conversations avant.',
          action: TextButton.icon(
            onPressed: busy ? null : onExport,
            icon: busy
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  )
                : const Icon(Icons.save_alt_rounded, size: 16),
            label: Text(busy ? 'Enregistrement…' : 'Enregistrer mes conversations'),
          ),
        ),
        const SizedBox(height: 18),
        _ActionTile(
          icon: Icons.edit_outlined,
          title: 'Modifier mon nom',
          onTap: busy ? null : onRename,
        ),
        _ActionTile(
          icon: Icons.save_alt_rounded,
          title: 'Enregistrer mes conversations',
          subtitle: 'Fichier Markdown à conserver hors du téléphone',
          onTap: busy ? null : onExport,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : onSignOut,
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.error,
            side: BorderSide(color: colors.error.withValues(alpha: 0.3)),
            minimumSize: const Size.fromHeight(44),
          ),
          icon: const Icon(Icons.logout_rounded, size: 17),
          label: const Text('Se déconnecter'),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 13,
              color: colors.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Vos conversations ne sont pas envoyées sur un serveur de '
                'comptes : elles restent dans l’application. Les clés de l’IA '
                'restent sur le serveur Makasi.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9.5,
                      height: 1.4,
                      letterSpacing: 0,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: Color(0xFFD97706),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        height: 1.45,
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerLeft, child: action!),
          ],
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: colors.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: onTap == null
                    ? colors.onSurfaceVariant.withValues(alpha: 0.4)
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              letterSpacing: 0,
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
