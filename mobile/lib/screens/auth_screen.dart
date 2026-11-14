import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../state/app_scope.dart';
import '../widgets/gradient_button.dart';
import '../widgets/makasi_logo.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.firstRun = false});

  final bool firstRun;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthMode { signIn, signUp }

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  // La création de compte est le choix par défaut.
  _AuthMode _mode = _AuthMode.signUp;
  bool _loading = false;
  bool _exporting = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _info = null;
    });
  }

  void _setError(String message) {
    setState(() {
      _error = message;
      _info = null;
    });
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();

    final controller = AppScope.read(context);
    final email = _email.text.trim();
    final password = _password.text;
    final name = _name.text.trim();

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _setError('Indiquez une adresse e-mail valide.');
      return;
    }
    if (password.length < 6) {
      _setError('Le mot de passe doit contenir au moins 6 caractères.');
      return;
    }
    if (_mode == _AuthMode.signUp && name.length < 2) {
      _setError('Indiquez un nom (2 caractères minimum).');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      if (_mode == _AuthMode.signUp) {
        await controller.signUp(name, email, password);
      } else {
        await controller.signIn(email, password);
      }
      if (!mounted) return;
      if (!widget.firstRun) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) _setError(friendlyAuthMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueAsGuest() async {
    await AppScope.read(context).continueAsGuest();
    if (mounted && !widget.firstRun) Navigator.of(context).maybePop();
  }

  Future<void> _exportChats() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final uri = await AppScope.read(context).exportChats();
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
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: widget.firstRun
          ? null
          : AppBar(
              leading: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              title: const Text('Compte'),
            ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              widget.firstRun ? 26 : 4,
              20,
              MediaQuery.viewInsetsOf(context).bottom > 0 ? 24 : 30,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 410),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.firstRun) ...[
                      const Center(child: MakasiLogo(size: 62, glow: true)),
                      const SizedBox(height: 20),
                      Text(
                        'Bienvenue sur Makasi AI',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontSize: 24,
                            ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Créez votre compte pour garder vos conversations dans '
                        'l’application et retrouver votre mémoire à chaque ouverture.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 12.5,
                              height: 1.5,
                            ),
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      Text(
                        controller.isSignedIn
                            ? 'Votre compte Makasi'
                            : 'Votre compte sur ce téléphone',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Vos conversations restent dans l’application.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 12.5,
                            ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    _LocalNotice(
                      exporting: _exporting,
                      onExport: _exportChats,
                    ),
                    const SizedBox(height: 18),

                    _ModeTabs(mode: _mode, onChanged: _switchMode),
                    const SizedBox(height: 18),

                    if (_mode == _AuthMode.signUp) ...[
                      _Field(
                        label: 'Nom ou pseudo',
                        controller: _name,
                        hint: 'Alphonse',
                        icon: Icons.person_outline_rounded,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                      ),
                      const SizedBox(height: 13),
                    ],
                    _Field(
                      label: 'E-mail',
                      controller: _email,
                      hint: 'vous@exemple.com',
                      icon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 13),
                    _Field(
                      label: 'Mot de passe',
                      controller: _password,
                      hint: '6 caractères minimum',
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: [
                        _mode == _AuthMode.signUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      onSubmitted: (_) => _submit(),
                      suffix: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 19,
                        ),
                        tooltip: _obscure ? 'Afficher' : 'Masquer',
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 13),
                      _Banner(
                        icon: Icons.error_outline_rounded,
                        color: colors.error,
                        text: _error!,
                      ),
                    ],
                    if (_info != null) ...[
                      const SizedBox(height: 13),
                      _Banner(
                        icon: Icons.check_circle_outline_rounded,
                        color: const Color(0xFF10B981),
                        text: _info!,
                      ),
                    ],

                    const SizedBox(height: 20),
                    GradientButton(
                      label: _mode == _AuthMode.signUp
                          ? 'Créer mon compte'
                          : 'Se connecter',
                      loading: _loading,
                      onPressed: _submit,
                    ),

                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.phone_iphone_rounded,
                          size: 15,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _mode == _AuthMode.signUp
                                ? 'Aucun e-mail de confirmation n’est envoyé. '
                                    'Choisissez un mot de passe et notez-le : '
                                    'votre compte reste sur ce téléphone.'
                                : 'Utilisez l’e-mail et le mot de passe créés '
                                    'sur ce téléphone.',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontSize: 10.5,
                                  height: 1.45,
                                  color: colors.onSurfaceVariant,
                                  letterSpacing: 0,
                                ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: Divider(color: colors.outline)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'ou',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        Expanded(child: Divider(color: colors.outline)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _continueAsGuest,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurfaceVariant,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('Continuer sans compte'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalNotice extends StatelessWidget {
  const _LocalNotice({required this.exporting, required this.onExport});

  final bool exporting;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(13),
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
                Icons.smartphone_rounded,
                size: 17,
                color: Color(0xFFD97706),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Votre compte reste sur ce téléphone',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontSize: 12,
                            color: const Color(0xFFB45309),
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Si vous désinstallez l’application, vous perdrez votre '
                      'compte et vos conversations. Enregistrez-les avant.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10.8,
                            height: 1.45,
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: exporting ? null : onExport,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 34),
                visualDensity: VisualDensity.compact,
                foregroundColor: const Color(0xFFB45309),
              ),
              icon: exporting
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    )
                  : const Icon(Icons.save_alt_rounded, size: 16),
              label: Text(
                exporting
                    ? 'Enregistrement…'
                    : 'Enregistrer mes conversations',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.mode, required this.onChanged});

  final _AuthMode mode;
  final ValueChanged<_AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          _tab(context, 'Créer un compte', _AuthMode.signUp),
          _tab(context, 'Connexion', _AuthMode.signIn),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, String label, _AuthMode value) {
    final colors = Theme.of(context).colorScheme;
    final selected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? colors.onSurface : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscure = false,
    this.onSubmitted,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscure;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  color: colors.onSurfaceVariant,
                  letterSpacing: 0.2,
                ),
          ),
        ),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          obscureText: obscure,
          onSubmitted: onSubmitted,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            prefixIcon: Icon(icon, size: 18),
            prefixIconConstraints: const BoxConstraints(minWidth: 42),
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    height: 1.45,
                    color: color,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
