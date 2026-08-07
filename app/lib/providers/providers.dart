import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart' as models;
import '../services/api_client.dart';
import '../services/local_cache.dart';

final apiProvider = Provider<ApiClient>((ref) => ApiClient());

class AuthState {
  const AuthState({
    this.user,
    this.loading = true,
    this.pendingEmail,
    this.pendingIsNew = false,
    this.pendingVision = false,
  });

  final models.User? user;
  final bool loading;
  final String? pendingEmail;
  final bool pendingIsNew;
  final bool pendingVision;

  bool get isLoggedIn => user != null;

  AuthState copyWith({
    models.User? user,
    bool? loading,
    String? pendingEmail,
    bool? pendingIsNew,
    bool? pendingVision,
    bool clearUser = false,
    bool clearPending = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      loading: loading ?? this.loading,
      pendingEmail: clearPending ? null : (pendingEmail ?? this.pendingEmail),
      pendingIsNew: clearPending ? false : (pendingIsNew ?? this.pendingIsNew),
      pendingVision: pendingVision ?? this.pendingVision,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._api) : super(const AuthState()) {
    _bootstrap();
  }

  final ApiClient _api;

  Future<void> _bootstrap() async {
    await _api.loadSession();
    final user = await _api.me();
    state = AuthState(user: user, loading: false);
  }

  Future<void> startLogin({
    required String email,
    required bool visionAssist,
  }) async {
    final isNew = await _api.startLogin(email: email, visionAssist: visionAssist);
    state = state.copyWith(
      pendingEmail: email.trim().toLowerCase(),
      pendingIsNew: isNew,
      pendingVision: visionAssist,
    );
  }

  Future<void> verify(String code, {String? name}) async {
    final email = state.pendingEmail;
    if (email == null) throw ApiException('Nincs folyamatban lévő belépés');
    final user = await _api.verifyLogin(
      email: email,
      code: code,
      name: name,
      visionAssist: state.pendingVision,
    );
    state = AuthState(user: user, loading: false);
  }

  Future<void> refresh() async {
    final user = await _api.me();
    state = AuthState(user: user, loading: false);
  }

  Future<void> setVisionAssist(bool value) async {
    final user = await _api.updateMe(visionAssist: value);
    state = state.copyWith(user: user);
  }

  Future<void> updateProfile({required String name, required String email}) async {
    final user = await _api.updateMe(name: name, email: email);
    state = state.copyWith(user: user);
  }

  Future<void> logout() async {
    await _api.logout();
    state = const AuthState(loading: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(apiProvider));
});

typedef HomeData = ({
  List<models.ConversationSummary> conversations,
  List<models.FamilyMember> people,
});

class HomeNotifier extends StateNotifier<AsyncValue<HomeData>> {
  HomeNotifier(this._ref) : super(const AsyncLoading()) {
    _boot();
  }

  final Ref _ref;
  var _busy = false;

  Future<void> _boot() async {
    final cached = await LocalCache.loadHome();
    if (cached != null) {
      state = AsyncData(cached);
    }
    await refresh();
  }

  Future<void> refresh({bool silent = false}) async {
    if (_busy) return;
    final auth = _ref.read(authProvider);
    if (!auth.isLoggedIn) {
      state = const AsyncData((conversations: [], people: []));
      return;
    }
    _busy = true;
    if (!silent && state is! AsyncData) {
      state = const AsyncLoading();
    }
    try {
      final api = _ref.read(apiProvider);
      final data = await api.listConversations();
      await LocalCache.saveHome(
        conversations: data.conversations,
        people: data.people,
      );
      state = AsyncData(data);
      // Prefetch a few recent message metas + audio in background.
      unawaited(_prefetchRecent(api, data.conversations));
    } catch (e, st) {
      if (state is! AsyncData) {
        state = AsyncError(e, st);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _prefetchRecent(
    ApiClient api,
    List<models.ConversationSummary> conversations,
  ) async {
    final recent = [...conversations]
      ..sort((a, b) => (b.lastMessageAt ?? '').compareTo(a.lastMessageAt ?? ''));
    for (final c in recent.take(5)) {
      try {
        final msgs = await api.listMessages(c.id, limit: 12);
        await LocalCache.saveMessages(c.id, msgs);
        await LocalCache.prefetchAudio(api, msgs, keep: 4);
      } catch (_) {}
    }
  }
}

final homeNotifierProvider =
    StateNotifierProvider.autoDispose<HomeNotifier, AsyncValue<HomeData>>((ref) {
  return HomeNotifier(ref);
});

/// Compatibility alias used by existing screens.
final homeProvider = Provider.autoDispose<AsyncValue<HomeData>>((ref) {
  return ref.watch(homeNotifierProvider);
});

final familyProvider = FutureProvider.autoDispose((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn) {
    return (family: null as models.Family?, members: <models.FamilyMember>[]);
  }
  return ref.watch(apiProvider).myFamily();
});
