import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'catalog_models.dart';
import 'catalog_parsing.dart';
import 'epg_parsing.dart';
import 'models.dart';

class XtreamException implements Exception {
  XtreamException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cliente da API Xtream Codes (player_api.php).
///
/// Os caminhos e campos usados aqui seguem a convenção conhecida do Xtream
/// Codes. Eles NÃO foram verificados contra o servidor do seu provedor.
class XtreamClient {
  XtreamClient({
    required String server,
    required this.username,
    required this.password,
    http.Client? httpClient,
  })  : server = normalizeServer(server),
        _http = httpClient ?? http.Client();

  /// Origem normalizada: esquema + host (+ porta), sem barra final.
  final String server;
  final String username;
  final String password;
  final http.Client _http;

  static String normalizeServer(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      throw XtreamException('Informe o endereço do servidor.');
    }
    if (!value.contains('://')) value = 'http://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      throw XtreamException('Endereço do servidor inválido.');
    }
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  void close() => _http.close();

  Uri _api([Map<String, String> extra = const {}]) {
    return Uri.parse('$server/player_api.php').replace(
      queryParameters: {
        'username': username,
        'password': password,
        ...extra,
      },
    );
  }

  Future<Uint8List> _getBytes(Uri uri, {Duration timeout = const Duration(seconds: 60)}) async {
    final http.Response response;
    try {
      response = await _http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
    } on TimeoutException {
      throw XtreamException('O servidor demorou demais para responder.');
    } on SocketException catch (e) {
      throw XtreamException(
        'Não foi possível conectar ao servidor. Confira o endereço, a porta e a internet. (${e.message})',
      );
    } on http.ClientException catch (e) {
      throw XtreamException(
        'Falha de conexão com o servidor. (${e.message})',
      );
    }

    final code = response.statusCode;
    if (code == 401 || code == 403) {
      throw XtreamException(
        'Acesso negado pelo servidor (HTTP $code). A conta pode estar bloqueada ou o servidor recusa este aplicativo.',
      );
    }
    if (code != 200) {
      throw XtreamException('O servidor respondeu com erro HTTP $code.');
    }
    return response.bodyBytes;
  }

  /// Valida usuário/senha e devolve os dados da conta.
  Future<AccountInfo> authenticate() async {
    final bytes = await _getBytes(_api());
    Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      throw XtreamException(
        'A resposta do servidor não é válida. Confira o endereço e a porta.',
      );
    }
    if (json is! Map || json['user_info'] is! Map) {
      throw XtreamException(
        'Resposta inesperada. Confira se o endereço é de um servidor Xtream Codes.',
      );
    }
    final user = json['user_info'] as Map;
    if ('${user['auth']}' != '1') {
      throw XtreamException('Usuário ou senha inválidos.');
    }
    final exp = int.tryParse('${user['exp_date']}');
    return AccountInfo(
      status: user['status']?.toString(),
      expiresAt:
          exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      maxConnections: int.tryParse('${user['max_connections']}'),
      activeConnections: int.tryParse('${user['active_cons']}'),
    );
  }

  Future<List<LiveCategory>> fetchLiveCategories() async {
    final bytes = await _getBytes(_api({'action': 'get_live_categories'}));
    try {
      return await compute(parseCategories, bytes);
    } on FormatException {
      throw XtreamException('Lista de categorias em formato inesperado.');
    }
  }

  Future<List<LiveChannel>> fetchLiveChannels() async {
    final bytes = await _getBytes(
      _api({'action': 'get_live_streams'}),
      timeout: const Duration(seconds: 180),
    );
    try {
      // O parse roda em outro isolate para não travar a interface.
      return await compute(parseChannels, bytes);
    } on FormatException {
      throw XtreamException('Lista de canais em formato inesperado.');
    }
  }

  // ---- filmes e séries ------------------------------------------------------

  Future<List<LiveCategory>> fetchCategories(CatalogKind kind) async {
    final action = kind == CatalogKind.movies
        ? 'get_vod_categories'
        : 'get_series_categories';
    final bytes = await _getBytes(_api({'action': action}));
    try {
      return await compute(parseVodCategories, bytes);
    } on FormatException {
      throw XtreamException('Lista de categorias de ${kind.label.toLowerCase()} em formato inesperado.');
    }
  }

  Future<List<CatalogTitle>> fetchTitles(CatalogKind kind) async {
    final action =
        kind == CatalogKind.movies ? 'get_vod_streams' : 'get_series';
    final bytes = await _getBytes(
      _api({'action': action}),
      timeout: const Duration(seconds: 240),
    );
    try {
      return await compute(parseTitles, ParseTitlesJob(bytes, kind));
    } on FormatException {
      throw XtreamException('Lista de ${kind.label.toLowerCase()} em formato inesperado.');
    }
  }

  Future<TitleDetails> fetchMovieInfo(int id) async {
    final bytes = await _getBytes(
      _api({'action': 'get_vod_info', 'vod_id': '$id'}),
      timeout: const Duration(seconds: 30),
    );
    return parseVodInfo(bytes);
  }

  Future<TitleDetails> fetchSeriesInfo(int id) async {
    final bytes = await _getBytes(
      _api({'action': 'get_series_info', 'series_id': '$id'}),
      timeout: const Duration(seconds: 45),
    );
    return parseSeriesInfo(bytes);
  }

  /// Programação de um canal. Tenta a tabela completa e, se vier vazia, a
  /// versão curta. Ações e campos seguem a convenção Xtream; não foram
  /// verificados no servidor do usuário.
  Future<List<EpgProgram>> fetchChannelEpg(int streamId) async {
    for (final action in const ['get_simple_data_table', 'get_short_epg']) {
      final bytes = await _getBytes(
        _api({
          'action': action,
          'stream_id': '$streamId',
          if (action == 'get_short_epg') 'limit': '60',
        }),
        timeout: const Duration(seconds: 30),
      );
      final list = parseProviderEpg(bytes);
      if (list.isNotEmpty) return list;
    }
    return const [];
  }
}

/// Funções de nível superior para poderem rodar via compute().
List<LiveCategory> parseCategories(Uint8List bytes) {
  final data = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  if (data is! List) return const [];
  final out = <LiveCategory>[];
  for (final item in data) {
    if (item is! Map) continue;
    final id = item['category_id']?.toString();
    final name = item['category_name']?.toString();
    if (id == null || name == null) continue;
    out.add(LiveCategory(id: id, name: name.trim()));
  }
  return out;
}

List<LiveChannel> parseChannels(Uint8List bytes) {
  final data = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  if (data is! List) return const [];
  final out = <LiveChannel>[];
  for (final item in data) {
    if (item is! Map) continue;
    final id = int.tryParse('${item['stream_id']}');
    if (id == null) continue;
    final name = (item['name'] ?? '').toString().trim();
    final icon = item['stream_icon']?.toString().trim();
    final epg = item['epg_channel_id']?.toString().trim();
    out.add(
      LiveChannel(
        streamId: id,
        name: name.isEmpty ? 'Canal $id' : name,
        categoryId: (item['category_id'] ?? '').toString(),
        icon: (icon == null || icon.isEmpty) ? null : icon,
        epgId: (epg == null || epg.isEmpty) ? null : epg,
      ),
    );
  }
  return out;
}
