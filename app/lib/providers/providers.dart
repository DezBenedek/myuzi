import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart' as models;
import '../services/api_client.dart';

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

final familyProvider = FutureProvider.autoDispose((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn) {
    return (family: null as models.Family?, members: <models.FamilyMember>[]);
  }
  return ref.watch(apiProvider).myFamily();
});

final homeProvider = FutureProvider.autoDispose((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn) {
    return (
      conversations: <models.ConversationSummary>[],
      people: <models.FamilyMember>[],
    );
  }
  return ref.watch(apiProvider).listConversations();
});
