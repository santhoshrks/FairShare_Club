import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/member_model.dart';
import '../services/firestore_service.dart';
import 'auth_provider.dart';

/// Real-time stream of the current user's saved contacts.
/// Watches [authStateProvider] so the stream is rebuilt whenever the auth
/// state changes (login / logout / token refresh), preventing stale
/// permission-denied errors from a stream subscribed under a different UID.
final userContactsProvider = StreamProvider<List<MemberModel>>((ref) {
  // Depend on auth state — provider rebuilds when user changes.
  final User? user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return FirestoreService.instance.userContactsStream();
});
