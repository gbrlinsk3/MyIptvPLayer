import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../downloads/download_models.dart';
import '../../library/library_import.dart';
import '../../state/app_scope.dart';
import '../catalog/poster_image.dart';
import '../catalog/title_details_page.dart';
import '../catalog/title_details_panel.dart';
import '../catalog/vod_player_page.dart';
import '../widgets/common.dart';
import 'history_view.dart';
import 'import_editor.dart';

/// Minha biblioteca: o que está baixando e o que já foi baixado (formato
/// original), com reprodução direta do arquivo no computador.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  /// 0 = Arquivos (baixados e importados), 1 = Histórico.
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final downloads = app.downloads;
    final imports = app.imports;
    return ListenableBuilder(
      listenable: Listenable.merge([downloads, imports]),
      builder: (context, _) {
        final mine = [for (final i in imports.items) if (!i.isRecording) i];
        final recordings = [for (final i in imports.items) if (i.isRecording) i];
        final queue = downloads.unfinished;
        final done = downloads.finished;
        final movies = [for (final e in done) if (e.isMovie) e];
        final episodes = [for (final e in done) if (!e.isMovie) e];

        // Séries: um grupo por série.
        final groups = <String, List<DownloadEntry>>{};
        for (final e in episodes) {
          groups.putIfAbsent('${e.seriesId ?? e.title}', () => []).add(e);
        }

        if (_tab == 1) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MINHA BIBLIOTECA', style: AppFonts.title(30, spacing: 1.2)),
                const SizedBox(height: 10),
                _tabs(),
                const SizedBox(height: 12),
                const Expanded(child: HistoryView()),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Row(
              children: [
                Text('MINHA BIBLIOTECA', style: AppFonts.title(30, spacing: 1.2)),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => showImportEditor(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar arquivo'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => downloads.openFolder(),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Abrir pasta'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _tabs(),
            const SizedBox(height: 10),
            Text(
              done.isEmpty && mine.isEmpty && recordings.isEmpty
                  ? 'Arquivos baixados ficam aqui, no formato original do provedor.'
                  : '${movies.length} ${movies.length == 1 ? 'filme' : 'filmes'}'
                      '  ·  ${episodes.length} ${episodes.length == 1 ? 'episódio' : 'episódios'}'
                      '  ·  ${formatBytes(downloads.usedBytes)}',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            if (queue.isEmpty && done.isEmpty && mine.isEmpty && recordings.isEmpty) const _Empty(),
            if (queue.isNotEmpty) ...[
              _SectionTitle('Em andamento'),
              for (final e in queue) _QueueRow(entry: e),
              const SizedBox(height: 20),
            ],
            if (movies.isNotEmpty)
              _LibRow(
                label: 'Filmes',
                info: '${movies.length}  ·  ${formatBytes(movies.fold<int>(0, (a, e) => a + e.doneBytes))}',
                entries: movies,
                playList: movies,
              ),
            for (final g in groups.values) _SeriesRow(episodes: g),
            if (mine.isNotEmpty) _ImportRow(items: mine, label: 'Meus arquivos'),
            if (recordings.isNotEmpty)
              _ImportRow(items: recordings, label: 'Gravações'),
          ],
        );
      },
    );
  }

  Widget _tabs() => Wrap(
        spacing: 8,
        children: [
          for (final (i, label) in [(0, 'Arquivos'), (1, 'Histórico')])
            ChoiceChip(
              label: Text(label),
              selected: _tab == i,
              onSelected: (_) => setState(() => _tab = i),
            ),
        ],
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text.toUpperCase(), style: AppFonts.title(22, spacing: 1.2)),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.download_for_offline_outlined,
              size: 36, color: AppColors.textMuted),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Nada baixado ainda. Abra um filme ou série e toque em "Baixar". '
              'O arquivo é salvo exatamente como o provedor entrega, sem '
              'recompressão, e toca aqui mesmo sem internet.',
              style: TextStyle(color: AppColors.textMuted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- reprodução do arquivo local --------------------------------------------------

PlayItem _playItem(DownloadEntry e) => PlayItem(
      kind: e.kind,
      id: e.itemId,
      title: e.title,
      subtitle: e.subtitle,
      url: e.filePath,
      image: e.image,
      seriesId: e.seriesId,
      season: e.season,
      episode: e.episode,
    );

Future<void> _play(
  BuildContext context,
  List<DownloadEntry> list,
  int index,
) async {
  final app = AppScope.read(context);
  final items = [for (final e in list) _playItem(e)];
  final p = await app.catalog.progressOf(items[index]);
  if (!context.mounted) return;
  await playItems(
    context,
    items: items,
    index: index,
    startAt: (p != null && p.canResume) ? Duration(milliseconds: p.positionMs) : null,
  );
  app.catalog.bumpProgress();
}

/// Toque num título baixado: segue o ajuste "Ao abrir um item da biblioteca"
/// (Conta → Personalização): reproduzir, painel lateral ou card expandido.
Future<void> _openEntry(
  BuildContext context,
  List<DownloadEntry> list,
  int index,
) async {
  final app = AppScope.read(context);
  final mode = app.libraryOpenMode;
  if (mode == 'player') return _play(context, list, index);
  final e = list[index];
  final id = e.isMovie ? e.itemId : (e.seriesId ?? e.itemId);
  final title = await app.catalog.titleById(e.kind, id);
  if (!context.mounted) return;
  if (title == null) {
    // O título não está mais no catálogo: reproduz direto.
    return _play(context, list, index);
  }
  if (mode == 'expanded') {
    await showTitleDetailsPage(context, title);
  } else {
    await showTitleDetails(context, title);
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  List<DownloadEntry> list,
  String what,
) async {
  final app = AppScope.read(context);
  final ok = await confirmDialog(
    context,
    title: 'Excluir $what?',
    message: 'Apaga o arquivo baixado deste computador. Você pode baixar de '
        'novo depois. Não afeta sua conta no provedor.',
    action: 'Excluir',
  );
  if (ok) await app.downloads.deleteMany(list);
}

// ---- em andamento -----------------------------------------------------------------

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.entry});

  final DownloadEntry entry;

  @override
  Widget build(BuildContext context) {
    final downloads = AppScope.read(context).downloads;
    final e = entry;
    final String status;
    switch (e.status) {
      case DownloadStatus.downloading:
        status = [
          if (e.fraction != null) '${(e.fraction! * 100).round()}%',
          e.totalBytes > 0
              ? '${formatBytes(e.doneBytes)} de ${formatBytes(e.totalBytes)}'
              : formatBytes(e.doneBytes),
          if (e.speed > 0) '${formatBytes(e.speed)}/s',
        ].join('  ·  ');
      case DownloadStatus.queued:
        status = e.error ?? 'Na fila';
      case DownloadStatus.paused:
        status = 'Pausado  ·  ${formatBytes(e.doneBytes)}';
      case DownloadStatus.error:
        status = e.error ?? 'Erro no download';
      case DownloadStatus.done:
        status = '';
    }
    final running = e.status == DownloadStatus.downloading ||
        e.status == DownloadStatus.queued;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 64,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: PosterImage(url: e.image, name: e.title, cacheWidth: 140),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (e.subtitle != null)
                  Text(
                    e.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: e.status == DownloadStatus.queued ? 0 : e.fraction,
                    minHeight: 5,
                    backgroundColor: AppColors.hover,
                    color: e.status == DownloadStatus.error
                        ? AppColors.danger
                        : AppColors.accent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: e.status == DownloadStatus.error
                        ? AppColors.danger
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: running ? 'Pausar' : 'Retomar',
            onPressed: () => running ? downloads.pause(e) : downloads.resume(e),
            icon: Icon(running ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(
            tooltip: 'Cancelar e apagar o que foi baixado',
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Cancelar este download?',
                message: 'O que já foi baixado será apagado.',
                action: 'Cancelar download',
              );
              if (ok) await downloads.cancel(e);
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

// ---- fileiras deitadas (como no catálogo, mas horizontais) -----------------------

/// Uma fileira com cartões horizontais (16:9) de itens já baixados.
class _LibRow extends StatelessWidget {
  const _LibRow({
    required this.label,
    required this.entries,
    required this.playList,
    this.info,
    this.trailing,
  });

  final String label;
  final String? info;
  final List<DownloadEntry> entries;

  /// Lista usada na reprodução (o toque abre o item `i` e segue para o próximo).
  final List<DownloadEntry> playList;
  final Widget? trailing;

  static const double cardWidth = 272;
  static const double _imageHeight = cardWidth * 9 / 16;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.title(22, spacing: 1.2),
                  ),
                ),
                if (info != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    info!,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
                const Spacer(),
                ?trailing,
              ],
            ),
          ),
          SizedBox(
            height: _imageHeight + 64,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              // Folga em cima/embaixo para a borda de destaque não ser cortada.
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: entries.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _LandCard(
                  entry: entries[i],
                  onPlay: () => _openEntry(context, playList, playList.indexOf(entries[i])),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesRow extends StatelessWidget {
  const _SeriesRow({required this.episodes});

  final List<DownloadEntry> episodes;

  @override
  Widget build(BuildContext context) {
    final list = [...episodes]..sort((a, b) {
        final s = (a.season ?? 0).compareTo(b.season ?? 0);
        return s != 0 ? s : (a.episode ?? 0).compareTo(b.episode ?? 0);
      });
    final size = list.fold<int>(0, (a, e) => a + e.doneBytes);
    return _LibRow(
      label: list.first.title,
      info: '${list.length} ${list.length == 1 ? 'episódio' : 'episódios'}'
          '  ·  ${formatBytes(size)}',
      entries: list,
      playList: list,
      trailing: IconButton(
        tooltip: 'Excluir todos os episódios baixados desta série',
        onPressed: () =>
            _confirmDelete(context, list, 'a série "${list.first.title}"'),
        icon: Icon(Icons.delete_outline, size: 20, color: AppColors.textMuted),
      ),
    );
  }
}

class _LandCard extends StatefulWidget {
  const _LandCard({required this.entry, required this.onPlay});

  final DownloadEntry entry;
  final VoidCallback onPlay;

  @override
  State<_LandCard> createState() => _LandCardState();
}

class _LandCardState extends State<_LandCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final app = AppScope.read(context);
    final isMovie = e.isMovie;
    final primary = isMovie ? e.title : (e.subtitle ?? e.code);
    return SizedBox(
      width: _LibRow.cardWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPlay,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                scale: _hover ? 1.03 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: _LibRow._imageHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _hover ? AppColors.accent : AppColors.border,
                      width: _hover ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _LandImage(entry: e),
                        AnimatedOpacity(
                          opacity: _hover ? 1 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: const ColoredBox(
                            color: Color(0x66000000),
                            child: Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                size: 52,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: PopupMenuButton<String>(
                            tooltip: 'Opções',
                            color: AppColors.surface,
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white,
                              size: 20,
                              shadows: [Shadow(blurRadius: 6)],
                            ),
                            onSelected: (v) {
                              if (v == 'folder') app.downloads.openFolder(e);
                              if (v == 'delete') {
                                _confirmDelete(context, [e], '"$primary"');
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'folder',
                                child: Text('Mostrar na pasta'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Excluir arquivo'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                primary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                formatBytes(e.doneBytes),
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Imagem horizontal do cartão: a guardada no download; se o item é antigo e
/// não tem, tenta buscar no servidor; sem nada, usa o pôster borrado.
class _LandImage extends StatelessWidget {
  const _LandImage({required this.entry});

  final DownloadEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final app = AppScope.read(context);
    final stored = e.backdrop;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF141312)),
        if (e.image != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: PosterImage(url: e.image, name: '', cacheWidth: 200),
          ),
        const ColoredBox(color: Color(0x44000000)),
        if (stored != null && stored.isNotEmpty)
          ChainImage(
            key: ValueKey('b:${e.id}'),
            urls: [if (tmdbSize(stored, 'w780') != stored) tmdbSize(stored, 'w780')!, stored],
            cacheWidth: 600,
          )
        else
          FutureBuilder(
            future: app.catalog.detailsOrNull(
              e.kind,
              e.isMovie ? e.itemId : (e.seriesId ?? e.itemId),
            ),
            builder: (context, snap) {
              final b = snap.data?.backdrop;
              if (b == null || b.isEmpty) {
                // Sem imagem horizontal: pôster nítido no centro.
                return Center(
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: PosterImage(url: e.image, name: e.title, cacheWidth: 300),
                      ),
                    ),
                  ),
                );
              }
              return ChainImage(
                key: ValueKey('b:${e.id}:$b'),
                urls: [if (tmdbSize(b, 'w780') != b) tmdbSize(b, 'w780')!, b],
                cacheWidth: 600,
              );
            },
          ),
      ],
    );
  }
}


// ---- arquivos adicionados pelo usuário -----------------------------------------------

PlayItem _importItem(LibraryImport i) => PlayItem(
      kind: CatalogKind.movies,
      // Id negativo: nunca colide com o id de um filme do provedor, então o
      // progresso (continuar de onde parou) fica separado.
      id: -(i.id ?? 0),
      title: i.title,
      subtitle: i.year,
      url: i.filePath,
      image: i.image ?? i.backdrop,
    );

Future<void> _playImport(BuildContext context, List<LibraryImport> list, int index) async {
  final app = AppScope.read(context);
  if (!File(list[index].filePath).existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('O arquivo não está mais nesse local. Edite o item para escolher de novo.')),
    );
    return;
  }
  final items = [for (final i in list) _importItem(i)];
  final p = await app.catalog.progressOf(items[index]);
  if (!context.mounted) return;
  await playItems(
    context,
    items: items,
    index: index,
    startAt: (p != null && p.canResume) ? Duration(milliseconds: p.positionMs) : null,
  );
  app.catalog.bumpProgress();
}

class _ImportRow extends StatelessWidget {
  const _ImportRow({required this.items, required this.label});

  final List<LibraryImport> items;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label.toUpperCase(), style: AppFonts.title(22, spacing: 1.2)),
              const SizedBox(width: 12),
              Text(
                '${items.length}',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
          SizedBox(
            height: _LibRow._imageHeight + 64,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: items.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _ImportCard(
                  item: items[i],
                  onPlay: () => _playImport(context, items, i),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportCard extends StatefulWidget {
  const _ImportCard({required this.item, required this.onPlay});

  final LibraryImport item;
  final VoidCallback onPlay;

  @override
  State<_ImportCard> createState() => _ImportCardState();
}

class _ImportCardState extends State<_ImportCard> {
  bool _hover = false;

  /// Três saídas: cancelar, tirar da biblioteca (o arquivo fica) ou apagar o
  /// arquivo do computador (com uma segunda tela de confirmação).
  Future<void> _remove() async {
    final app = AppScope.read(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Tirar da biblioteca?', style: TextStyle(fontSize: 16)),
        content: const Text(
          'Tirar: o item some daqui e o arquivo continua no seu computador.\n'
          'Apagar arquivo: o item some e o arquivo é apagado do computador.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Apagar arquivo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('remove'),
            child: const Text('Tirar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'remove') {
      await app.imports.remove(widget.item);
    } else if (choice == 'delete') {
      final ok = await confirmDialog(
        context,
        title: 'Apagar o arquivo mesmo?',
        message: 'O arquivo "${widget.item.filePath}" será apagado do seu '
            'computador e não vai para a lixeira. Não dá para desfazer.',
        action: 'Apagar definitivamente',
      );
      if (!ok || !mounted) return;
      try {
        final f = File(widget.item.filePath);
        if (f.existsSync()) await f.delete();
        final cover = widget.item.image;
        // A capa só é apagada se foi gerada por nós (.jpg ao lado do vídeo).
        if (widget.item.isRecording && cover != null && cover.endsWith('.jpg')) {
          final c = File(cover);
          if (c.existsSync()) await c.delete();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não consegui apagar o arquivo: $e')),
          );
        }
        return;
      }
      await app.imports.remove(widget.item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final image = i.backdrop ?? i.image;
    return SizedBox(
      width: _LibRow.cardWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPlay,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: _LibRow._imageHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hover ? AppColors.accent : AppColors.border,
                    width: _hover ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(url: image, name: i.title, cacheWidth: 560),
                    if (_hover) ...[
                      const ColoredBox(
                        color: Color(0x66000000),
                        child: Center(
                          child: Icon(Icons.play_circle_fill_rounded,
                              size: 46, color: Colors.white),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              onPressed: () => showImportEditor(context, existing: i),
                              icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.white),
                            ),
                            IconButton(
                              tooltip: 'Tirar da biblioteca',
                              onPressed: _remove,
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                i.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              if (i.year != null)
                Text(
                  i.year!,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
