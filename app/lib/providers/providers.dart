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
    unawaited(LocalCache.trimCaches());
    try {
      await _api.loadSession();
      final cached = await LocalCache.loadUser();
      final hasToken = _api.token != null && _api.token!.isNotEmpty;

      if (!hasToken) {
        await LocalCache.clearUser();
        state = const AuthState(loading: false);
        return;
      }

      // Stay logged in offline with last known profile while we validate.
      if (cached != null) {
        // Keep the auth gate in validation mode until /me confirms the token.
        // Otherwise realtime can start with a stale cached session and loop
        // on 401 responses while the UI still looks logged in.
        state = AuthState(user: cached, loading: true);
      }

      try {
        final user = await _api.me();
        if (user != null) {
          await LocalCache.saveUser(user);
          state = AuthState(user: user, loading: false);
        } else {
          // Session rejected (401) — real logout.
          await LocalCache.clearUser();
          state = const AuthState(loading: false);
        }
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          await LocalCache.clearUser();
          state = const AuthState(loading: false);
          return;
        }
        // Network / server blip: keep cached session if we have one.
        if (cached != null) {
          state = AuthState(user: cached, loading: false);
        } else {
          state = const AuthState(loading: false);
        }
      } catch (_) {
        if (cached != null) {
          state = AuthState(user: cached, loading: false);
        } else {
          state = const AuthState(loading: false);
        }
      }
    } catch (_) {
      state = const AuthState(loading: false);
    }
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

  /// Resend login code (server enforces 30s cooldown).
  Future<void> resendLoginCode() async {
    final email = state.pendingEmail;
    if (email == null || email.isEmpty) {
      throw ApiException('Nincs folyamatban lévő belépés');
    }
    await _api.startLogin(email: email, visionAssist: state.pendingVision);
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
    await LocalCache.saveUser(user);
    state = AuthState(user: user, loading: false);
  }

  Future<void> refresh() async {
    try {
      final user = await _api.me();
      if (user == null) {
        await LocalCache.clearUser();
        state = const AuthState(loading: false);
        return;
      }
      await LocalCache.saveUser(user);
      state = AuthState(user: user, loading: false);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await LocalCache.clearUser();
        state = const AuthState(loading: false);
      }
      // Keep current UI on transient failures.
    } catch (_) {}
  }

  Future<void> setVisionAssist(bool value) async {
    try {
      final user = await _api.updateMe(visionAssist: value);
      await LocalCache.saveUser(user);
      state = state.copyWith(user: user);
    } on ApiException catch (e) {
      if (e.statusCode == 401) await invalidateSession();
      rethrow;
    }
  }

  Future<void> invalidateSession() async {
    await _api.clearSession();
    await LocalCache.clearUser();
    state = const AuthState(loading: false);
  }

  Future<void> updateProfile({required String name, required String email}) async {
    final user = await _api.updateMe(name: name, email: email);
    await LocalCache.saveUser(user);
    state = state.copyWith(user: user);
  }

  Future<void> setAvatar(models.User user) async {
    await LocalCache.saveUser(user);
    state = state.copyWith(user: user);
  }

  Future<void> logout() async {
    await _api.logout();
    await LocalCache.clearUser();
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
  HomeNotifier(this._ref)
      : super(const AsyncData((conversations: [], people: []))) {
    _boot();
  }

  final Ref _ref;
  var _busy = false;

  Future<void> _boot() async {
    final cached = await LocalCache.loadHome();
    if (cached != null) {
      state = AsyncData(cached);
    }
    // Auth may still be loading; refresh when ready.
    final auth = _ref.read(authProvider);
    if (auth.isLoggedIn) {
      await refresh(silent: true);
    } else if (!auth.loading) {
      state = const AsyncData((conversations: [], people: []));
    }
  }

  /// Push fresh server data into UI + disk cache (no network).
  void applyData(HomeData data) {
    state = AsyncData(data);
    unawaited(
      LocalCache.saveHome(
        conversations: data.conversations,
        people: data.people,
      ),
    );
  }

  Future<void> refresh({bool silent = true}) async {
    if (_busy) return;
    final auth = _ref.read(authProvider);
    if (auth.loading) return;
    if (!auth.isLoggedIn) {
      state = const AsyncData((conversations: [], people: []));
      return;
    }
    _busy = true;
    // Never wipe the list for a spinner if we already have (cached) data.
    if (!silent && state.asData == null) {
      state = const AsyncLoading();
    }
    try {
      final api = _ref.read(apiProvider);
      final data = await api.listConversations();
      applyData(data);
    } catch (e, st) {
      if (state.asData == null) {
        state = AsyncError(e, st);
      }
    } finally {
      _busy = false;
    }
  }
}

/// Kept alive so leaving a chat and returning is instant from memory/cache.
final homeNotifierProvider =
    StateNotifierProvider<HomeNotifier, AsyncValue<HomeData>>((ref) {
  final notifier = HomeNotifier(ref);
  ref.listen(authProvider, (prev, next) {
    if (prev?.isLoggedIn != next.isLoggedIn ||
        (prev?.loading == true && next.loading == false && next.isLoggedIn)) {
      unawaited(notifier.refresh(silent: true));
    }
    if (prev?.isLoggedIn == true && !next.isLoggedIn) {
      notifier.applyData((conversations: [], people: []));
    }
  });
  return notifier;
});

/// Compatibility alias used by existing screens.
final homeProvider = Provider<AsyncValue<HomeData>>((ref) {
  return ref.watch(homeNotifierProvider);
});

final familyProvider = FutureProvider.autoDispose((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn) {
    return (family: null as models.Family?, members: <models.FamilyMember>[]);
  }
  return ref.watch(apiProvider).myFamily();
});
