import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_scope.dart';
import '../window/title_bar.dart';
import 'epg_panel.dart';
import 'fullscreen.dart';
import 'playback_overlays.dart';
import 'player_controls.dart';

/// Abre o canal selecionado em uma página própria (cobrindo a janela), com a
/// programação (EPG) embaixo. [channels] é a lista de onde o canal veio, usada
/// pelos botões "canal anterior/próximo". Ao voltar, a transmissão é encerrada
/// (libera a conexão do provedor).
Future<void> openLivePlayer(BuildContext context, List<LiveChannel> channels) async {
  final app = AppScope.read(context);
  final downloads = app.downloads;
  downloads.suspendForPlayback();
  app.catalog.beginPlayback(); // sem trabalho novo em segundo plano
  try {
    await _pushLivePlayer(context, channels);
  } finally {
    app.catalog.endPlayback();
    unawaited(downloads.resumeAfterPlayback());
  }
}

Future<void> _pushLivePlayer(BuildContext context, List<LiveChannel> channels) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, a, b) => LivePlayerPage(channels: channels),
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class LivePlayerPage extends StatefulWidget {
  const LivePlayerPage({super.key, required this.channels});

  final List<LiveChannel> channels;

  @override
  State<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends State<LivePlayerPage> {
  late final PlaybackController _playback;
  bool _showEpg = true;

  @override
  void initState() {
    super.initState();
    _playback = AppScope.read(context).playback;
  }

  @override
  void dispose() {
    // Depois do frame: parar notifica ouvintes e não pode ocorrer durante o
    // desmonte da árvore.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_playback.stop());
    });
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = AppScope.of(context);
    final channel = c.selected;
    if (channel == null) return;
    final url = c.streamUrlFor(channel);
    if (url == null) return;
    final nonce = c.playbackNonce;
    final headers = c.playbackHeaders;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        c.playback.play(
          channelId: channel.streamId,
          nonce: nonce,
          url: url,
          headers: headers,
        ),
      );
    });
  }

  void _step(int delta) {
    final c = AppScope.read(context);
    final list = widget.channels;
    if (list.isEmpty) return;
    final i = list.indexWhere((ch) => ch.streamId == c.selected?.streamId);
    final n = list.length;
    final next = ((i < 0 ? 0 : i) + delta + n) % n;
    c.selectChannel(list[next]);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final channel = c.selected;
    final fav = channel != null && c.isFavorite(channel.streamId);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.keyF): () =>
            enterVideoFullscreen(context, _playback),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          body: Column(
            children: [
              TitleBar(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Voltar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.arrow_back, color: AppColors.text),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          channel?.name ?? 'TV ao vivo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.title(24, spacing: 1),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (channel != null)
                        IconButton(
                          tooltip: fav
                              ? 'Remover dos favoritos'
                              : 'Adicionar aos favoritos',
                          onPressed: () => c.toggleFavorite(channel),
                          icon: Icon(
                            fav ? Icons.favorite : Icons.favorite_border,
                            size: 20,
                            color: fav ? AppColors.accent : AppColors.textMuted,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Canal anterior (←)',
                        onPressed: () => _step(-1),
                        icon: Icon(Icons.skip_previous, color: AppColors.text),
                      ),
                      IconButton(
                        tooltip: 'Próximo canal (→)',
                        onPressed: () => _step(1),
                        icon: Icon(Icons.skip_next, color: AppColors.text),
                      ),
                      IconButton(
                        tooltip: _showEpg
                            ? 'Ocultar programação'
                            : 'Mostrar programação',
                        onPressed: () => setState(() => _showEpg = !_showEpg),
                        icon: Icon(
                          Icons.event_note_outlined,
                          color: _showEpg ? AppColors.accent : AppColors.text,
                        ),
                      ),
                      const Expanded(child: SizedBox.expand()),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ColoredBox(
                      color: Colors.black,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Video(
                            controller: _playback.video,
                            controls: (state) => const SizedBox.shrink(),
                          ),
                          Positioned.fill(
                            child: PlayerControls(
                              playback: _playback,
                              fullscreen: false,
                              onToggleFullscreen: () =>
                                  enterVideoFullscreen(context, _playback),
                            ),
                          ),
                          Positioned.fill(
                            child: PlaybackOverlays(playback: _playback),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_showEpg) const EpgPanel(),
            ],
          ),
        ),
      ),
    );
  }
}
