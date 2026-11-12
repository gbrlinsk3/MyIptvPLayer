import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_scope.dart';

/// Guia de programação do canal selecionado, embaixo de toda a área da TV ao
/// vivo. Pode ser minimizada (a escolha é salva).
class EpgPanel extends StatefulWidget {
  const EpgPanel({super.key});

  @override
  State<EpgPanel> createState() => _EpgPanelState();
}

class _EpgPanelState extends State<EpgPanel> {
  static const double _cardExtent = 252;
  static const double _expandedHeight = 196;
  static const double _collapsedHeight = 44;

  final _scroll = ScrollController();
  Timer? _clock;
  int? _lastChannelId;
  List<EpgProgram>? _scrolledFor;

  @override
  void initState() {
    super.initState();
    // Atualiza a marcação de "agora" e a barra de progresso.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = AppScope.of(context);
    final channel = c.selected;
    if (channel?.streamId == _lastChannelId) return;
    _lastChannelId = channel?.streamId;
    final account = c.account;
    // Depois do frame, para não notificar ouvintes no meio da construção.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(c.epg.showChannel(channel, account));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final epg = c.epg;
    final channel = c.selected;

    return ListenableBuilder(
      listenable: epg,
      builder: (context, _) {
        final collapsed = epg.collapsed;
        final matches =
            channel != null && epg.viewChannel?.streamId == channel.streamId;
        final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final programs = matches ? epg.programs : const <EpgProgram>[];

        EpgProgram? current;
        for (final p in programs) {
          if (p.start <= nowEpoch && nowEpoch < p.stop) current = p;
        }

        // Ao carregar a lista, rola até o programa em andamento (ou o próximo).
        if (!collapsed &&
            programs.isNotEmpty &&
            !identical(_scrolledFor, epg.programs)) {
          _scrolledFor = epg.programs;
          final index = math.max(0, programs.indexWhere((p) => p.stop > nowEpoch));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scroll.hasClients) return;
            _scroll.jumpTo(
              math.min(index * _cardExtent, _scroll.position.maxScrollExtent),
            );
          });
        }

        return Container(
          // +1: a borda de cima ocupa 1 px dentro da altura do contêiner.
          height: (collapsed ? _collapsedHeight : _expandedHeight) + 1,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: [
              _Header(
                channel: channel,
                current: current,
                sourceLabel: matches ? epg.sourceLabel : null,
                collapsed: collapsed,
                onToggle: () => epg.setCollapsed(!collapsed),
              ),
              if (!collapsed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _body(
                      channel: channel,
                      matches: matches,
                      programs: programs,
                      nowEpoch: nowEpoch,
                      loading: epg.loadingView,
                      error: epg.viewError,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _body({
    required LiveChannel? channel,
    required bool matches,
    required List<EpgProgram> programs,
    required int nowEpoch,
    required bool loading,
    required String? error,
  }) {
    if (channel == null) {
      return const _Note('Selecione um canal para ver a programação.');
    }
    if (!matches || loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (programs.isEmpty) {
      final hint = channel.epgKey == null
          ? 'O provedor não informa um código de EPG para este canal.'
          : 'Nenhuma fonte tem programação para este canal.';
      return _Note(
        error == null
            ? 'Sem programação disponível. $hint'
            : 'Sem programação disponível. $error',
      );
    }
    return ListView.builder(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      itemExtent: _cardExtent,
      itemCount: programs.length,
      itemBuilder: (context, i) =>
          _ProgramCard(program: programs[i], nowEpoch: nowEpoch),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.channel,
    required this.current,
    required this.sourceLabel,
    required this.collapsed,
    required this.onToggle,
  });

  final LiveChannel? channel;
  final EpgProgram? current;
  final String? sourceLabel;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(
          children: [
            Icon(Icons.event_note_outlined,
                size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Text(
                channel == null
                    ? 'Programação'
                    : 'Programação · ${channel!.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Text(
                current == null ? '' : 'Agora: ${current!.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (sourceLabel != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  'Fonte: $sourceLabel',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            IconButton(
              tooltip: collapsed ? 'Expandir programação' : 'Minimizar programação',
              onPressed: onToggle,
              icon: Icon(
                collapsed ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.program, required this.nowEpoch});

  final EpgProgram program;
  final int nowEpoch;

  @override
  Widget build(BuildContext context) {
    final isCurrent = program.start <= nowEpoch && nowEpoch < program.stop;
    final isPast = program.stop <= nowEpoch;
    final span = program.stop - program.start;
    final progress = isCurrent && span > 0
        ? ((nowEpoch - program.start) / span).clamp(0.0, 1.0).toDouble()
        : null;
    final day = formatDayLabel(program.startTime, DateTime.now());
    final times =
        '$day · ${formatClock(program.startTime)} – ${formatClock(program.stopTime)}';
    final description = program.description;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: description == null
            ? program.title
            : '${program.title}\n\n$description',
        waitDuration: const Duration(milliseconds: 600),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isCurrent ? AppColors.accentSoft : AppColors.surface,
            border: Border.all(
              color: isCurrent ? AppColors.accent : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                times,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isCurrent ? AppColors.accent : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                program.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isPast ? AppColors.textMuted : AppColors.text,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
              const Spacer(),
              if (progress != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    color: AppColors.accent,
                    backgroundColor: AppColors.border,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      ),
    );
  }
}
