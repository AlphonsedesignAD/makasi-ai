import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../state/app_controller.dart';
import '../state/app_scope.dart';
import 'makasi_logo.dart';
import 'markdown_view.dart';
import 'typing_dots.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.chat,
    required this.message,
    required this.index,
    required this.isLast,
  });

  final Chat chat;
  final ChatMessage message;
  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    if (message.isUser) {
      return _UserBubble(message: message);
    }

    final streamingThis = controller.streaming && isLast;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: MakasiLogo(size: 26),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.text.trim().isEmpty && streamingThis)
                  const Padding(
                    padding: EdgeInsets.only(top: 7, bottom: 4),
                    child: TypingDots(),
                  )
                else if (message.error)
                  _ErrorBody(text: message.text)
                else
                  SelectionArea(
                    child: MarkdownView(text: message.text),
                  ),
                if (message.interrupted)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Réponse interrompue',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                if (!streamingThis)
                  _Actions(
                    message: message,
                    controller: controller,
                    onRetry: () => controller.retryFrom(chat, index),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final attachment = message.attachment;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18, left: 42),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: isDark ? 0.17 : 0.09),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(6),
          ),
          border: Border.all(
            color: colors.primary.withValues(alpha: isDark ? 0.22 : 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment != null) ...[
              _AttachmentChip(attachment: attachment),
              if (message.visibleText.trim().isNotEmpty) const SizedBox(height: 8),
            ],
            if (message.visibleText.trim().isNotEmpty)
              Text(
                message.visibleText,
                textAlign: TextAlign.left,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14.5,
                      height: 1.5,
                      color: colors.onSurface,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = attachment.isImage
        ? Icons.image_outlined
        : attachment.isPdf
            ? Icons.picture_as_pdf_outlined
            : attachment.kind == AttachmentKind.text
                ? Icons.code_rounded
                : Icons.insert_drive_file_outlined;

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 7, 11, 7),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outline.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.primary),
          const SizedBox(width: 7),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurface,
                      ),
                ),
                if (attachment.size > 0)
                  Text(
                    attachment.sizeLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 9.5,
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

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.error.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    height: 1.45,
                    color: colors.error,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.message,
    required this.controller,
    required this.onRetry,
  });

  final ChatMessage message;
  final AppController controller;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final speaking = controller.speakingId == message.id;
    final hasText = message.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasText)
            _MiniAction(
              icon: Icons.content_copy_rounded,
              tooltip: 'Copier',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: message.text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Réponse copiée'),
                      duration: Duration(milliseconds: 1300),
                    ),
                  );
                }
              },
            ),
          if (hasText)
            _MiniAction(
              icon: speaking
                  ? Icons.stop_circle_outlined
                  : Icons.volume_up_outlined,
              tooltip: speaking ? 'Arrêter' : 'Écouter',
              active: speaking,
              onTap: () => controller.toggleSpeak(message),
            ),
          _MiniAction(
            icon: Icons.refresh_rounded,
            tooltip: 'Régénérer',
            onTap: controller.streaming ? null : onRetry,
          ),
          if (message.error)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Réessayez',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.primary,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 16,
            color: active
                ? colors.primary
                : colors.onSurfaceVariant.withValues(alpha: onTap == null ? 0.3 : 0.75),
          ),
        ),
      ),
    );
  }
}
