import 'package:flutter/widgets.dart';

import '../core/app_log.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../epg/epg_controller.dart';
import '../playback/playback_controller.dart';
import '../state/app_controller.dart';
import 'profile.dart';
import 'profile_store.dart';

/// Sessão do perfil aberto: banco, EPG e estado do app daquele perfil.
class ProfileSession {
  ProfileSession(this.profile, this.db, this.epg, this.app);

  final Profile profile;
  final AppDatabase db;
  final EpgController epg;
  final AppController app;
}

/// Lista de perfis e perfil ativo. O player ([playback]) é único e fica fora
/// da sessão: é parado ao trocar de perfil.
class ProfilesController extends ChangeNotifier {
  ProfilesController(this.playback);

  final PlaybackController playback;

  ProfileStore? _store;
  List<Profile> profiles = const [];
  ProfileSession? session;

  bool loading = true;
  bool entering = false;
  String? error;
  bool indexRecovered = false;

  /// true quando o índice de perfis foi aberto com sucesso.
  bool get ready => _store != null;

  @override
  void dispose() {
    // Fechamento do app: libera os controllers do perfil aberto, se houver.
    session?.app.dispose();
    session?.epg.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final store = await ProfileStore.open();
      _store = store;
      indexRecovered = store.recovered;
      profiles = await store.list();
      await _restoreShape(store);
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  // ---- formato da tela de perfis ------------------------------------------

  static const _shapeKey = 'last_button_shape';

  /// "Quem está assistindo?" repete o formato do último perfil usado (o ajuste
  /// em si continua guardado em cada perfil).
  Future<void> _restoreShape(ProfileStore store) async {
    try {
      AppShape.rounded = await store.appSetting(_shapeKey) != 'square';
    } catch (e) {
      AppLog.warn('perfis.formato', e);
    }
  }

  Future<void> _rememberShape(String shape) async {
    try {
      await _store!.setAppSetting(_shapeKey, shape);
    } catch (e) {
      AppLog.warn('perfis.formato', e);
    }
  }

  Future<void> _reload() async {
    profiles = await _store!.list();
    notifyListeners();
  }

  // ---- gerenciar perfis ---------------------------------------------------

  Future<Profile> create(String name, String avatar, int accent) async {
    final profile = await _store!.create(name.trim(), avatar, accent);
    await _reload();
    return profile;
  }

  Future<void> update(Profile profile) async {
    await _store!.update(profile);
    await _reload();
  }

  Future<void> delete(Profile profile) async {
    await _store!.delete(profile.id);
    await _reload();
  }

  // ---- entrar / sair ------------------------------------------------------

  Future<void> enter(Profile profile) async {
    if (entering || session != null) return;
    entering = true;
    error = null;
    notifyListeners();

    AppDatabase? db;
    EpgController? epg;
    AppController? app;
    try {
      db = await AppDatabase.open(_store!.pathFor(profile.id));
      epg = EpgController(db);
      app = AppController(db, playback, epg);
      // Entra no perfil já: a abertura toca e o Início começa a montar enquanto
      // o controlador carrega (a interface espera `phase` sair de "booting").
      AppColors.applyAccent(profile.accentColor);
      session = ProfileSession(profile, db, epg, app);
      notifyListeners();
      await app.init();
      final opened = app;
      await _rememberShape(opened.buttonShape);
      // Trocas de formato dentro do perfil também contam.
      opened.shapeRevision.addListener(
        () => _rememberShape(opened.buttonShape),
      );
    } catch (e) {
      error = 'Não foi possível abrir o perfil: $e';
      session = null;
      AppColors.resetProfileLook();
      app?.dispose();
      epg?.dispose();
      await db?.close();
    }
    entering = false;
    notifyListeners();
  }

  /// Volta para "Quem está assistindo?".
  Future<void> leave() async {
    final s = session;
    if (s == null) return;
    session = null;
    await playback.stop();
    AppColors.resetProfileLook();
    notifyListeners();
    // Descarta depois que a interface deixou de usar os controllers.
    await WidgetsBinding.instance.endOfFrame;
    s.app.dispose();
    s.epg.dispose();
    await s.db.close();
  }

  /// Atualiza o perfil ativo (nome/avatar/cor editados pela própria sessão).
  Future<void> updateActive(Profile profile) async {
    final s = session;
    await update(profile);
    if (s != null && s.profile.id == profile.id) {
      AppColors.applyAccent(profile.accentColor);
      session = ProfileSession(profile, s.db, s.epg, s.app);
      notifyListeners();
    }
  }
}
