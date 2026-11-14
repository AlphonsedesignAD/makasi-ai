import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../data/models.dart';
import '../state/app_controller.dart';
import '../state/app_scope.dart';
import '../widgets/avatar.dart';
import '../widgets/composer.dart';
import '../widgets/makasi_logo.dart';
import '../widgets/message_bubble.dart';
import 'account_sheet.dart';
import 'chat_drawer.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  AppController? _controller;
  String? _knownChatId;
  int _knownCount = 0;
  bool _stickToBottom = true;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.read(context);
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_onControllerChanged);
    _controller = controller;
    controller.addListener(_onControllerChanged);
    _knownChatId = controller.activeId;
    _knownCount = controller.activeChat?.messages.length ?? 0;
    _scheduleScroll(animate: false);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.offset;
    if (remaining > 90 && _stickToBottom) {
      setState(() => _stickToBottom = false);
    } else if (remaining <= 24 && !_stickToBottom) {
      setState(() => _stickToBottom = true);
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;
    final chat = controller.activeChat;
    final id = chat?.id;
    final count = chat?.messages.length ?? 0;
    final changed = id != _knownChatId || count != _knownCount;
    if (changed) {
      _knownChatId = id;
      _knownCount = count;
      _stickToBottom = true;
      _scheduleScroll();
    } else if (controller.streaming && _stickToBottom) {
      _scheduleScroll();
    }
  }

  void _scheduleScroll({bool animate = true}) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animate && target > 0) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  void _newChat() {
    final controller = AppScope.read(context);
    controller.newChat();
    _stickToBottom = true;
    _scheduleScroll(animate: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _openAccount() {
    _scaffoldKey.currentState?.closeDrawer();
    showAccountSheet(context);
  }

  void _openSettings() {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  void _sendSuggestion(String prompt) {
    AppScope.read(context).send(prompt);
    _stickToBottom = true;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    final colors = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final drawer = ChatDrawer(
          embedded: wide,
          onOpenAccount: _openAccount,
          onOpenSettings: _openSettings,
        );

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: colors.surface,
          drawer: wide ? null : drawer,
          body: Row(
            children: [
              if (wide) drawer,
              Expanded(
                child: SafeArea(
                  left: !wide,
                  child: Column(
                    children: [
                      _Header(
                        wide: wide,
                        onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                        onNewChat: _newChat,
                        onAccount: _openAccount,
                      ),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: controller,
                          builder: (context, _) {
                            final chat = controller.activeChat;
                            if (chat == null || chat.messages.isEmpty) {
                              return _Welcome(
                                onSuggestion: _sendSuggestion,
                              );
                            }
                            return _Conversation(
                              chat: chat,
                              scrollController: _scroll,
                              wide: wide,
                            );
                          },
                        ),
                      ),
                      _ComposerArea(
                        controller: _text,
                        focusNode: _focus,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.wide,
    required this.onMenu,
    required this.onNewChat,
    required this.onAccount,
  });

  final bool wide;
  final VoidCallback onMenu;
  final VoidCallback onNewChat;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final chat = controller.activeChat;
          final title = wide
              ? (chat == null || chat.title.isEmpty
                  ? 'Nouvelle discussion'
                  : chat.title)
              : 'Makasi AI';

          return Row(
            children: [
              if (!wide)
                IconButton(
                  onPressed: onMenu,
                  tooltip: 'Mes discussions',
                  icon: const Icon(Icons.menu_rounded, size: 22),
                )
              else
                const SizedBox(width: 6),
              if (!wide)
                const MakasiLogo(size: 26)
              else
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 17,
                  color: colors.onSurfaceVariant,
                ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: wide ? 13.5 : 15,
                        color: wide ? colors.onSurface : colors.onSurface,
                      ),
                ),
              ),
              if (controller.isSignedIn)
                _LocalBadge(onTap: onAccount)
              else
                _GuestBadge(onTap: onAccount),
              const SizedBox(width: 3),
              IconButton(
                onPressed: onNewChat,
                tooltip: 'Nouvelle discussion',
                icon: const Icon(Icons.edit_square, size: 19),
              ),
              const SizedBox(width: 2),
              InkResponse(
                onTap: onAccount,
                radius: 22,
                child: MakasiAvatar(
                  name: controller.userName,
                  guest: !controller.isSignedIn,
                  size: 32,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LocalBadge extends StatelessWidget {
  const _LocalBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Compte enregistré sur ce téléphone',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.phone_iphone_rounded,
                size: 12,
                color: Color(0xFF059669),
              ),
              const SizedBox(width: 4),
              Text(
                'Compte',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9.5,
                      letterSpacing: 0,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF059669),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestBadge extends StatelessWidget {
  const _GuestBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_outline_rounded,
              size: 13,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              'Invité',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 0,
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.chat,
    required this.scrollController,
    required this.wide,
  });

  final Chat chat;
  final ScrollController scrollController;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const maxContent = 840.0;
        final side = constraints.maxWidth > maxContent
            ? (constraints.maxWidth - maxContent) / 2
            : (wide ? 38.0 : 16.0);
        return ListView.builder(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(side, 22, side, 16),
          itemCount: chat.messages.length,
          itemBuilder: (context, index) {
            return MessageBubble(
              chat: chat,
              message: chat.messages[index],
              index: index,
              isLast: index == chat.messages.length - 1,
            );
          },
        );
      },
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onSuggestion});

  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final now = DateTime.now();

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth > 900
            ? (constraints.maxWidth - 780) / 2
            : (constraints.maxWidth > 600 ? 40.0 : 22.0);
        final twoColumns = constraints.maxWidth >= 660;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, 34, horizontal, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MakasiLogo(size: 48, glow: true),
              const SizedBox(height: 18),
              Text(
                greetingForHour(now.hour),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                      letterSpacing: 0.1,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Comment puis-je vous aider ?',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: constraints.maxWidth < 400 ? 26 : 30,
                    ),
              ),
              const SizedBox(height: 7),
              Text(
                'Posez une question ou joignez un document. '
                'Makasi garde le fil de vos échanges.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      height: 1.55,
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 26),
              if (twoColumns)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _SuggestionCard(
                            icon: Icons.lightbulb_outline_rounded,
                            title: 'Expliquer simplement',
                            subtitle: 'Un concept, une idée, un sujet',
                            onTap: () => onSuggestion(
                              'Explique-moi un concept complexe avec des mots simples et un exemple concret.',
                            ),
                          ),
                          const SizedBox(height: 10),
                          _SuggestionCard(
                            icon: Icons.edit_note_rounded,
                            title: 'Rédiger un message',
                            subtitle: 'E-mail, réponse, publication',
                            onTap: () => onSuggestion(
                              'Aide-moi à rédiger un message professionnel clair et courtois.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        children: [
                          _SuggestionCard(
                            icon: Icons.summarize_outlined,
                            title: 'Résumer un document',
                            subtitle: 'Points clés et actions',
                            onTap: () => onSuggestion(
                              'Donne-moi une méthode efficace pour résumer un document en points clés.',
                            ),
                          ),
                          const SizedBox(height: 10),
                          _SuggestionCard(
                            icon: Icons.text_snippet_outlined,
                            title: 'Améliorer un texte',
                            subtitle: 'Plus clair et professionnel',
                            onTap: () => onSuggestion(
                              'Aide-moi à améliorer un texte pour le rendre plus clair, plus court et plus professionnel.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                _SuggestionCard(
                  icon: Icons.lightbulb_outline_rounded,
                  title: 'Expliquer simplement',
                  subtitle: 'Un concept, une idée, un sujet',
                  onTap: () => onSuggestion(
                    'Explique-moi un concept complexe avec des mots simples et un exemple concret.',
                  ),
                ),
                const SizedBox(height: 9),
                _SuggestionCard(
                  icon: Icons.edit_note_rounded,
                  title: 'Rédiger un message',
                  subtitle: 'E-mail, réponse, publication',
                  onTap: () => onSuggestion(
                    'Aide-moi à rédiger un message professionnel clair et courtois.',
                  ),
                ),
                const SizedBox(height: 9),
                _SuggestionCard(
                  icon: Icons.summarize_outlined,
                  title: 'Résumer un document',
                  subtitle: 'Points clés et actions',
                  onTap: () => onSuggestion(
                    'Donne-moi une méthode efficace pour résumer un document en points clés.',
                  ),
                ),
                const SizedBox(height: 9),
                _SuggestionCard(
                  icon: Icons.text_snippet_outlined,
                  title: 'Améliorer un texte',
                  subtitle: 'Plus clair et professionnel',
                  onTap: () => onSuggestion(
                    'Aide-moi à améliorer un texte pour le rendre plus clair, plus court et plus professionnel.',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Vos échanges restent privés. Makasi se souvient de votre contexte.',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 9.5,
                            letterSpacing: 0,
                            color: colors.onSurfaceVariant.withValues(alpha: 0.75),
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: colors.outline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: isDark ? 0.14 : 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: colors.primary),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontSize: 12.5,
                            ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 10.5,
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_outward_rounded,
                  size: 15,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerArea extends StatelessWidget {
  const _ComposerArea({
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Composer(
          textController: controller,
          focusNode: focusNode,
        ),
      ),
    );
  }
}
