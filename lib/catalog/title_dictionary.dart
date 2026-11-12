import 'smart_search.dart';

/// Dicionário pequeno de palavras comuns em títulos, português ↔ inglês.
/// Serve para a busca achar "The Last of Us" ao digitar "o último de nós" (e
/// o contrário). É uma lista curta escrita à mão: **não cobre todos os
/// títulos** — só traduz palavra por palavra, sem entender frases.
class TitleDictionary {
  TitleDictionary._();

  /// (português, inglês), já sem acentos e em minúsculas. Quando uma palavra
  /// tem mais de um par, o primeiro vale.
  static const _pairs = <(String, String)>[
    ('ultimo', 'last'), ('ultima', 'last'), ('ultimos', 'last'),
    ('nos', 'us'), ('nosso', 'our'), ('nossa', 'our'),
    ('vida', 'life'), ('vidas', 'lives'), ('morte', 'death'), ('amor', 'love'),
    ('guerra', 'war'), ('guerras', 'wars'), ('paz', 'peace'),
    ('noite', 'night'), ('noites', 'nights'), ('dia', 'day'), ('dias', 'days'),
    ('manha', 'morning'), ('tarde', 'afternoon'),
    ('homem', 'man'), ('homens', 'men'), ('mulher', 'woman'),
    ('mulheres', 'women'), ('menino', 'boy'), ('menina', 'girl'),
    ('garoto', 'boy'), ('garota', 'girl'), ('crianca', 'child'),
    ('criancas', 'children'),
    ('aranha', 'spider'), ('morcego', 'bat'), ('formiga', 'ant'),
    ('vespa', 'wasp'), ('tartarugas', 'turtles'), ('tubarao', 'shark'),
    ('lobo', 'wolf'), ('urso', 'bear'), ('leao', 'lion'),
    ('cachorro', 'dog'), ('gato', 'cat'), ('cavalo', 'horse'),
    ('passaro', 'bird'), ('dragao', 'dragon'), ('dragoes', 'dragons'),
    ('rei', 'king'), ('reis', 'kings'), ('rainha', 'queen'),
    ('principe', 'prince'), ('princesa', 'princess'), ('senhor', 'lord'),
    ('aneis', 'rings'), ('anel', 'ring'), ('cavaleiro', 'knight'),
    ('guerreiro', 'warrior'), ('capitao', 'captain'), ('doutor', 'doctor'),
    ('estranho', 'strange'), ('estranha', 'strange'), ('estranhas', 'strange'),
    ('estranhos', 'strange'), ('coisas', 'things'), ('maravilha', 'wonder'),
    ('viuva', 'widow'), ('pantera', 'panther'), ('ferro', 'iron'),
    ('sereia', 'mermaid'), ('bela', 'beauty'), ('fera', 'beast'),
    ('neve', 'snow'), ('gelo', 'ice'), ('fogo', 'fire'), ('agua', 'water'),
    ('sangue', 'blood'), ('sombra', 'shadow'), ('sombras', 'shadows'),
    ('escuro', 'dark'), ('escuridao', 'darkness'), ('luz', 'light'),
    ('negro', 'black'), ('negra', 'black'), ('preto', 'black'),
    ('branco', 'white'), ('branca', 'white'), ('vermelho', 'red'),
    ('azul', 'blue'), ('verde', 'green'), ('dourado', 'golden'),
    ('ouro', 'gold'), ('prata', 'silver'),
    ('grande', 'big'), ('pequeno', 'small'), ('pequena', 'little'),
    ('novo', 'new'), ('nova', 'new'), ('velho', 'old'), ('velha', 'old'),
    ('jovem', 'young'), ('bom', 'good'), ('mau', 'bad'), ('feliz', 'happy'),
    ('triste', 'sad'), ('louco', 'crazy'), ('louca', 'crazy'),
    ('velozes', 'fast'), ('furiosos', 'furious'), ('furioso', 'furious'),
    ('perigoso', 'dangerous'), ('secreto', 'secret'), ('segredo', 'secret'),
    ('segredos', 'secrets'), ('perdido', 'lost'), ('perdidos', 'lost'),
    ('esquecido', 'forgotten'), ('selvagem', 'wild'), ('impossivel', 'impossible'),
    ('fantastico', 'fantastic'), ('quarteto', 'four'),
    ('vingadores', 'avengers'), ('vingador', 'avenger'), ('vinganca', 'revenge'),
    ('guardioes', 'guardians'), ('galaxia', 'galaxy'), ('estrela', 'star'),
    ('estrelas', 'stars'), ('lua', 'moon'), ('sol', 'sun'),
    ('ilha', 'island'), ('cidade', 'city'), ('floresta', 'forest'),
    ('montanha', 'mountain'), ('rio', 'river'), ('mar', 'sea'),
    ('oceano', 'ocean'), ('terra', 'earth'), ('mundo', 'world'), ('ceu', 'sky'),
    ('casa', 'house'), ('lar', 'home'), ('estrada', 'road'),
    ('caminho', 'path'), ('viagem', 'journey'), ('tempo', 'time'),
    ('futuro', 'future'), ('passado', 'past'), ('sonho', 'dream'),
    ('sonhos', 'dreams'), ('pesadelo', 'nightmare'), ('jogo', 'game'),
    ('jogos', 'games'), ('vorazes', 'hunger'), ('fuga', 'escape'),
    ('missao', 'mission'), ('volta', 'return'), ('retorno', 'return'),
    ('ascensao', 'rise'), ('queda', 'fall'), ('ressurreicao', 'resurrection'),
    ('irmao', 'brother'), ('irmaos', 'brothers'), ('irma', 'sister'),
    ('irmandade', 'brotherhood'), ('pai', 'father'), ('mae', 'mother'),
    ('filho', 'son'), ('filha', 'daughter'), ('familia', 'family'),
    ('amigo', 'friend'), ('amigos', 'friends'), ('inimigo', 'enemy'),
    ('heroi', 'hero'), ('viloes', 'villains'), ('vilao', 'villain'),
    ('bruxa', 'witch'), ('feiticeiro', 'wizard'), ('fantasma', 'ghost'),
    ('monstro', 'monster'), ('monstros', 'monsters'), ('vampiro', 'vampire'),
    ('zumbi', 'zombie'), ('zumbis', 'zombies'), ('sobrevivente', 'survivor'),
    ('sobreviventes', 'survivors'), ('apocalipse', 'apocalypse'),
    ('policia', 'police'), ('assassino', 'killer'), ('justica', 'justice'),
    ('liga', 'league'), ('esquadrao', 'squad'), ('suicida', 'suicide'),
    ('lei', 'law'), ('ordem', 'order'), ('assalto', 'heist'),
    ('exterminador', 'terminator'), ('piratas', 'pirates'),
    ('caribe', 'caribbean'), ('procurando', 'finding'), ('era', 'age'),
    ('chefao', 'godfather'), ('paraiso', 'paradise'), ('inferno', 'hell'),
    ('anjo', 'angel'), ('demonio', 'demon'), ('diabo', 'devil'),
    ('deus', 'god'), ('casamento', 'wedding'), ('ferias', 'vacation'),
    ('natal', 'christmas'), ('verao', 'summer'), ('inverno', 'winter'),
    ('tempestade', 'storm'), ('verdade', 'truth'), ('mentira', 'lie'),
    ('mentiras', 'lies'), ('culpa', 'guilt'), ('esperanca', 'hope'),
    ('coragem', 'courage'), ('destino', 'destiny'), ('lenda', 'legend'),
    ('misterio', 'mystery'), ('cartas', 'letters'), ('carta', 'letter'),
    ('hospital', 'hospital'), ('escola', 'school'), ('colegio', 'school'),
    ('praia', 'beach'), ('deserto', 'desert'), ('ponte', 'bridge'),
    ('porta', 'door'), ('chave', 'key'), ('espelho', 'mirror'),
    ('relogio', 'clock'), ('laranja', 'orange'),
  ];

  static final Map<String, String> _ptToEn = {
    for (final (pt, en) in _pairs) pt: en,
  };
  static final Map<String, String> _enToPt = _buildEnToPt();

  static Map<String, String> _buildEnToPt() {
    final m = <String, String>{};
    for (final (pt, en) in _pairs) {
      m.putIfAbsent(en, () => pt); // o primeiro par de cada palavra em inglês
    }
    return m;
  }

  /// Versão traduzida da busca (palavra por palavra) ou nulo se nenhuma
  /// palavra estiver no dicionário. Palavras que existem nos dois idiomas
  /// com a mesma grafia ou que não estão no dicionário ficam como estão.
  static String? translate(String query) {
    final nq = SmartSearch.normalize(query);
    if (nq.isEmpty) return null;
    var changed = false;
    final out = <String>[];
    for (final w in nq.split(' ')) {
      final t = _ptToEn[w] ?? _enToPt[w];
      if (t != null && t != w) {
        out.add(t);
        changed = true;
      } else {
        out.add(w);
      }
    }
    return changed ? out.join(' ') : null;
  }
}
