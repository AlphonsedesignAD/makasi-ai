import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_scope.dart';

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.textController,
    required this.focusNode,
  });

  final TextEditingController textController;
  final FocusNode focusNode;

  @override
  State<Composer> createState() => _ComposerState();
}

enum _PickKind { photo, camera, file }

class _ComposerState extends State<Composer> {
  final ImagePicker _picker = ImagePicker();
  final SpeechToText _speech = SpeechToText();

  Attachment? _attachment;
  bool _speechReady = false;
  bool _listening = false;
  String _voiceBase = '';

  @override
  void initState() {
    super.initState();
    widget.textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.textController.removeListener(_onTextChanged);
    if (_listening) {
      _speech.stop();
    }
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /* ---------- Pièces jointes ---------- */
  Future<void> _openAttachmentSheet() async {
    final kind = await showModalBottomSheet<_PickKind>(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    'Joindre à la conversation',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _SheetTile(
                  icon: Icons.photo_library_outlined,
                  title: 'Photo de la galerie',
                  subtitle: 'Image, capture d’écran',
                  onTap: () => Navigator.pop(context, _PickKind.photo),
                ),
                _SheetTile(
                  icon: Icons.photo_camera_outlined,
                  title: 'Prendre une photo',
                  subtitle: 'Appareil photo',
                  onTap: () => Navigator.pop(context, _PickKind.camera),
                ),
                _SheetTile(
                  icon: Icons.attach_file_rounded,
                  title: 'Fichier',
                  subtitle: 'Code, texte, PDF, CSV…',
                  onTap: () => Navigator.pop(context, _PickKind.file),
                ),
                const SizedBox(height: 4),
                Text(
                  'Taille maximale : 10 Mo.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (kind == null || !mounted) return;
    switch (kind) {
      case _PickKind.photo:
        await _pickImage(ImageSource.gallery);
        break;
      case _PickKind.camera:
        await _pickImage(ImageSource.camera);
        break;
      case _PickKind.file:
        await _pickFile();
        break;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 86,
        maxWidth: 2200,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final name = picked.name.isEmpty ? 'image.jpg' : picked.name;
      _setAttachment(
        name: name,
        bytes: bytes,
        mime: _mimeFor(name, picked.mimeType),
      );
    } catch (e) {
      _snack('Impossible d’ouvrir l’image. Vérifiez les autorisations.');
    }
  }

  Future<void> _pickFile() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      _setAttachment(
        name: file.name,
        bytes: bytes,
        mime: _mimeFor(file.name, null),
      );
    } catch (e) {
      _snack('Impossible d’ouvrir le fichier.');
    }
  }

  void _setAttachment({
    required String name,
    required Uint8List bytes,
    required String mime,
  }) {
    if (bytes.length > 10 * 1024 * 1024) {
      _snack('Fichier trop volumineux (maximum 10 Mo).');
      return;
    }
    final kind = Attachment.kindFrom(name, mime);
    String? text;
    if (kind == AttachmentKind.text) {
      try {
        text = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        text = null;
      }
    }
    setState(() {
      _attachment = Attachment(
        name: name,
        size: bytes.length,
        mime: mime,
        kind: kind,
        bytes: bytes,
        text: text,
      );
    });
    widget.focusNode.requestFocus();
  }

  String _mimeFor(String name, String? fallback) {
    if (fallback != null && fallback.isNotEmpty) return fallback;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      case 'json':
        return 'application/json';
      case 'csv':
        return 'text/csv';
      case 'md':
        return 'text/markdown';
      case 'html':
        return 'text/html';
      case 'css':
        return 'text/css';
      case 'js':
        return 'text/javascript';
      case 'dart':
      case 'py':
      case 'ts':
      case 'tsx':
      case 'jsx':
      case 'java':
      case 'c':
      case 'cpp':
      case 'php':
      case 'sql':
      case 'txt':
      case 'yaml':
      case 'yml':
      case 'xml':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  void _clearAttachment() {
    setState(() => _attachment = null);
  }

  /* ---------- Dictée vocale ---------- */
  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    try {
      if (!_speechReady) {
        _speechReady = await _speech.initialize(
          onStatus: (status) {
            if (!mounted) return;
            if (status == 'done' || status == 'notListening') {
              setState(() => _listening = false);
            }
          },
          onError: (error) {
            if (!mounted) return;
            setState(() => _listening = false);
            if (error.errorMsg != 'error_no_match') {
              _snack('Dictée indisponible sur cet appareil.');
            }
          },
        );
      }

      if (!_speechReady) {
        _snack('La dictée vocale n’est pas disponible sur cet appareil.');
        return;
      }

      _voiceBase = widget.textController.text.trim();
      await _speech.listen(
        onResult: _onVoiceResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          localeId: 'fr_FR',
        ),
      );
      if (mounted) setState(() => _listening = true);
    } catch (_) {
      if (!mounted) return;
      try {
        await _speech.listen(
          onResult: _onVoiceResult,
          listenOptions: SpeechListenOptions(
            partialResults: true,
            listenMode: ListenMode.dictation,
            localeId: 'fr_FR',
          ),
        );
        if (mounted) setState(() => _listening = true);
      } catch (_) {
        _snack('La dictée vocale n’est pas disponible sur cet appareil.');
      }
    }
  }

  void _onVoiceResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.trim();
    final prefix = _voiceBase.isEmpty ? '' : '$_voiceBase ';
    final text = '$prefix$words';
    widget.textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    if (!_listening && mounted) setState(() => _listening = true);
  }

  Future<void> _cancelVoice() async {
    await _speech.stop();
    widget.textController.value = TextEditingValue(
      text: _voiceBase,
      selection: TextSelection.collapsed(offset: _voiceBase.length),
    );
    if (mounted) setState(() => _listening = false);
  }

  /* ---------- Envoi ---------- */
  Future<void> _send() async {
    final controller = AppScope.read(context);
    final text = widget.textController.text.trim();
    final attachment = _attachment;
    if (controller.streaming) return;
    if (text.isEmpty && attachment == null) return;

    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
    }

    widget.textController.clear();
    setState(() => _attachment = null);
    widget.focusNode.requestFocus();
    unawaited(controller.send(text, attachment: attachment));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final controller = AppScope.read(context);
    final attachment = _attachment;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(7, 7, 7, 7),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: colors.outline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.22
                        : 0.05,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (attachment != null)
                  _AttachmentPreview(
                    attachment: attachment,
                    onRemove: _clearAttachment,
                  ),
                if (_listening) _VoiceBar(onCancel: _cancelVoice),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _RoundIcon(
                      icon: Icons.add_rounded,
                      tooltip: 'Joindre un fichier',
                      onTap: controller.streaming ? null : _openAttachmentSheet,
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: TextField(
                          controller: widget.textController,
                          focusNode: widget.focusNode,
                          minLines: 1,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          textCapitalization: TextCapitalization.sentences,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontSize: 14.5,
                                height: 1.45,
                              ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            hintText: 'Écrivez votre message…',
                            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                                  fontSize: 14.5,
                                ),
                          ),
                        ),
                      ),
                    ),
                    _RoundIcon(
                      icon: _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      tooltip: _listening ? 'Arrêter la dictée' : 'Dictée vocale',
                      active: _listening,
                      onTap: controller.streaming ? null : _toggleVoice,
                    ),
                    const SizedBox(width: 5),
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) {
                        final hasContent = widget.textController.text.trim().isNotEmpty ||
                            _attachment != null;
                        return _SendButton(
                          streaming: controller.streaming,
                          enabled: hasContent,
                          onSend: _send,
                          onStop: controller.stopStreaming,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 7, bottom: 6),
            child: Text(
              'Makasi AI peut faire des erreurs. Vérifiez les informations importantes.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                    letterSpacing: 0,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.attachment,
    required this.onRemove,
  });

  final Attachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bytes = attachment.bytes;
    return Container(
      margin: const EdgeInsets.fromLTRB(3, 2, 3, 8),
      padding: const EdgeInsets.fromLTRB(8, 7, 5, 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          if (attachment.isImage && bytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.memory(
                bytes,
                width: 33,
                height: 33,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            )
          else
            Container(
              width: 33,
              height: 33,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                attachment.isPdf
                    ? Icons.picture_as_pdf_outlined
                    : attachment.kind == AttachmentKind.text
                        ? Icons.code_rounded
                        : Icons.insert_drive_file_outlined,
                size: 17,
                color: colors.primary,
              ),
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurface,
                      ),
                ),
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
          IconButton(
            onPressed: onRemove,
            tooltip: 'Retirer',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: 17,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceBar extends StatelessWidget {
  const _VoiceBar({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(3, 2, 3, 8),
      padding: const EdgeInsets.fromLTRB(11, 6, 5, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Parlez… Makasi vous écoute',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    color: const Color(0xFFEF4444),
                  ),
            ),
          ),
          IconButton(
            onPressed: onCancel,
            tooltip: 'Annuler',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: 17,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
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
        radius: 20,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 21,
            color: active
                ? const Color(0xFFEF4444)
                : colors.onSurfaceVariant.withValues(alpha: onTap == null ? 0.3 : 1),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.streaming,
    required this.enabled,
    required this.onSend,
    required this.onStop,
  });

  final bool streaming;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = streaming || enabled;

    return SizedBox(
      width: 38,
      height: 38,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: streaming || enabled ? MakasiTheme.gradient : null,
            color: streaming || enabled ? null : colors.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: streaming ? onStop : (enabled ? onSend : null),
            child: Icon(
              streaming ? Icons.stop_rounded : Icons.arrow_upward_rounded,
              size: streaming ? 20 : 20,
              color: active ? Colors.white : colors.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({
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
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: colors.primary),
            ),
            const SizedBox(width: 12),
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
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: colors.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
