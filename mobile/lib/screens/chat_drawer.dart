import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../state/app_scope.dart';
import '../widgets/avatar.dart';
import '../widgets/makasi_logo.dart';

/// Panneau des discussions.
///
/// Affiché dans un [Drawer] sur téléphone et directement à gauche de la
/// conversation sur tablette, ordinateur et web.
class ChatDrawer extends StatefulWidget {
  const ChatDrawer({
    super.key,
    this.embedded = false,
    this.onOpenAccount,
    this.onOpenSettings,
  });

  final bool embedded;
  final VoidCallback? onOpenAccount;
  final VoidCallback? onOpenSettings;

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<ChatDrawer> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _close() {
    if (!widget.embedded) Navigator.of(context).maybePop();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _startChat() {
    AppScope.read(context).newChat();
    _close();
  }

  Future<void> _select(Chat chat) async {
    final controller = AppScope.read(context);
    if (controller.streaming) {
      _snack('Attendez la fin de la réponse avant de changer de discussion.');
      return;
    }
    await controller.openChat(chat.id);
    _close();
  }

  Future<void> _rename(Chat chat) async {
    final controller = AppScope.read(context);
    if (controller.streaming) {
      _snack('La discussion est en cours de génération.');
      return;
    }
    final text = TextEditingController(text: chat.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Renommer la discussion'),
          content: TextField(
            controller: text,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Titre de la discussion',
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
              child: const Text('Renommer'),
            ),
          ],
        );
      },
    );
    text.dispose();
    if (result == null) return;
    await controller.renameChat(chat.id, result);
  }

  Future<void> _delete(Chat chat) async {
    final controller = AppScope.read(context);
    if (controller.streaming) {
      _snack('La discussion est en cours de génération.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer la discussion ?'),
          content: Text(
            '« ${chat.title.isEmpty ? 'Nouvelle discussion' : chat.title} » sera supprimée de cet appareil et de votre compte.',
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
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await controller.deleteChat(chat.id);
    if (mounted) _snack('Discussion supprimée.');
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final signedIn = controller.isSignedIn;

    final filtered = controller.chats.where((chat) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      if (chat.title.toLowerCase().contains(q)) return true;
      return chat.messages.any(
        (m) => m.visibleText.toLowerCase().contains(q),
      );
    }).toList();

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
          child: Row(
            children: [
              const MakasiLogo(size: 38),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Makasi AI',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            letterSpacing: -0.3,
                          ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      signedIn ? 'Compte sur ce téléphone' : 'Mémoire sur cet appareil',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: colors.onSurfaceVariant,
                            letterSpacing: 0,
                          ),
                    ),
                  ],
                ),
              ),
              if (!widget.embedded)
                IconButton(
                  onPressed: _close,
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 0, 13, 10),
          child: _NewChatButton(
            enabled: !controller.streaming,
            onTap: _startChat,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 0, 13, 8),
          child: TextField(
            controller: _search,
            onChanged: (value) => setState(() => _query = value.trim()),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 12.5,
                  color: colors.onSurface,
                ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.55),
              hintText: 'Rechercher une discussion',
              hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 17,
                color: colors.onSurfaceVariant,
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      tooltip: 'Effacer',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(color: colors.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(color: colors.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(color: colors.primary, width: 1.2),
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _EmptyList(query: _query)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(9, 2, 9, 12),
                  itemCount: filtered.length + _sectionCount(filtered),
                  itemBuilder: (context, index) {
                    return _buildItem(context, filtered, index);
                  },
                ),
        ),
        _AccountFooter(
          signedIn: signedIn,
          name: signedIn
              ? (controller.userName.isEmpty
                  ? controller.userEmail
                  : controller.userName)
              : 'Mode invité',
          email: signedIn
              ? 'Compte enregistré sur ce téléphone'
              : 'Vos discussions restent ici',
          onTap: widget.onOpenAccount,
          onSettings: widget.onOpenSettings,
        ),
      ],
    );

    if (widget.embedded) {
      return Container(
        width: 306,
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border(right: BorderSide(color: colors.outline)),
        ),
        child: SafeArea(right: false, child: content),
      );
    }

    return Drawer(
      width: 312,
      backgroundColor: colors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(child: content),
    );
  }

  int _sectionCount(List<Chat> chats) {
    var count = 0;
    String? last;
    for (final chat in chats) {
      final label = relativeDayLabel(chat.updatedAt);
      if (label != last) {
        count++;
        last = label;
      }
    }
    return count;
  }

  Widget _buildItem(BuildContext context, List<Chat> chats, int index) {
    // Parcourt la liste en insérant un titre de section avant chaque groupe.
    var cursor = 0;
    String? last;
    for (final chat in chats) {
      final label = relativeDayLabel(chat.updatedAt);
      if (label != last) {
        if (cursor == index) return _SectionLabel(label: label);
        cursor++;
        last = label;
      }
      if (cursor == index) {
        return _ChatTile(
          chat: chat,
          selected: chat.id == _activeId(context),
          onTap: () => _select(chat),
          onRename: () => _rename(chat),
          onDelete: () => _delete(chat),
        );
      }
      cursor++;
    }
    return const SizedBox.shrink();
  }

  String? _activeId(BuildContext context) => AppScope.read(context).activeId;
}

class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 43,
          decoration: BoxDecoration(
            gradient: MakasiTheme.gradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: MakasiTheme.brandMid.withValues(alpha: 0.24),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? onTap : null,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, size: 19, color: Colors.white),
                SizedBox(width: 7),
                Text(
                  'Nouvelle discussion',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.1,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 13, 8, 5),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 9.5,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant.withValues(alpha: 0.75),
            ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final Chat chat;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  String get _preview {
    if (chat.messages.isEmpty) return 'Discussion vide';
    final last = chat.messages.last;
    final text = last.visibleText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isNotEmpty) {
      return text.length > 52 ? '${text.substring(0, 52)}…' : text;
    }
    if (last.attachment != null) return last.attachment!.name;
    return last.isUser ? 'Message envoyé' : 'Réponse de Makasi';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = chat.title.isEmpty ? 'Nouvelle discussion' : chat.title;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.09)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 8, 2, 8),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.chat_bubble_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 12.5,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                              color: selected ? colors.primary : colors.onSurface,
                            ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              letterSpacing: 0,
                              color: colors.onSurfaceVariant
                                  .withValues(alpha: 0.8),
                            ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_ChatAction>(
                  tooltip: 'Options',
                  padding: EdgeInsets.zero,
                  iconSize: 17,
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _ChatAction.rename:
                        onRename();
                        break;
                      case _ChatAction.delete:
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _ChatAction.rename,
                      height: 42,
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 17),
                          SizedBox(width: 9),
                          Text('Renommer'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: _ChatAction.delete,
                      height: 42,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 17),
                          SizedBox(width: 9),
                          Text('Supprimer'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ChatAction { rename, delete }

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              query.isEmpty
                  ? Icons.forum_outlined
                  : Icons.search_off_rounded,
              size: 28,
              color: colors.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 10),
            Text(
              query.isEmpty
                  ? 'Aucune discussion pour le moment'
                  : 'Aucun résultat',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
            ),
            if (query.isEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Commencez une nouvelle conversation.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      letterSpacing: 0,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountFooter extends StatelessWidget {
  const _AccountFooter({
    required this.signedIn,
    required this.name,
    required this.email,
    this.onTap,
    this.onSettings,
  });

  final bool signedIn;
  final String name;
  final String email;
  final VoidCallback? onTap;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      padding: const EdgeInsets.fromLTRB(9, 8, 7, 8),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(5, 5, 4, 5),
                  child: Row(
                    children: [
                      MakasiAvatar(
                        name: signedIn ? name : '',
                        guest: !signedIn,
                        size: 34,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurface,
                                  ),
                            ),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          fontSize: 9.5,
                                          letterSpacing: 0,
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ],
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
          IconButton(
            onPressed: onSettings,
            tooltip: 'Paramètres',
            icon: Icon(
              Icons.settings_outlined,
              size: 19,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
