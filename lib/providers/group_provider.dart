import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/group_model.dart';
import '../services/firestore_service.dart';
import '../services/hive_service.dart';

// Keep HiveService for settings only
final hiveServiceProvider = Provider<HiveService>((ref) => HiveService());

// ─── Groups (real-time Firestore stream) ─────────────────────────────────────
class GroupNotifier extends StateNotifier<List<GroupModel>> {
  bool _disposed = false;
  AppLifecycleListener? _lifecycleListener;

  GroupNotifier() : super([]) {
    // Re-trigger invite linking whenever the app comes to the foreground.
    // This covers the case where another user added the current user to a new
    // group while this app was in the background or offline.
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (!_disposed) {
          FirestoreService.instance.linkPendingInvites().catchError((_) {});
        }
      },
    );

    // React to every auth change so the stream always belongs to the current user
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      _groupSub?.cancel();
      _groupSub = null;
      if (user != null) {
        // Link any pending invites FIRST (e.g. added to group after registration)
        // This is non-blocking for the stream — invites update Firestore, and the
        // real-time stream below will pick them up automatically.
        FirestoreService.instance.linkPendingInvites().catchError((_) {});

        if (_disposed) return;
        _groupSub =
            FirestoreService.instance.groupsStream().listen((groups) {
          if (!_disposed) state = groups;
        }, onError: (_) {
          // byUid stream error — Firestore will reconnect automatically;
          // avoid crashing the notifier.
        });
      } else {
        if (!_disposed) state = [];
      }
    });
  }

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<GroupModel>>? _groupSub;

  @override
  void dispose() {
    _disposed = true;
    _lifecycleListener?.dispose();
    _authSub?.cancel();
    _groupSub?.cancel();
    super.dispose();
  }

  Future<void> addGroup(GroupModel group) =>
      FirestoreService.instance.saveGroup(group);

  Future<void> updateGroup(GroupModel group) =>
      FirestoreService.instance.saveGroup(group);

  Future<void> deleteGroup(String id) =>
      FirestoreService.instance.deleteGroupData(id);

  Future<void> archiveGroup(String id) async {
    final group = state.where((g) => g.id == id).firstOrNull;
    if (group != null) {
      await FirestoreService.instance
          .saveGroup(group.copyWith(isArchived: true));
    }
  }

  Future<void> unarchiveGroup(String id) async {
    final group = state.where((g) => g.id == id).firstOrNull;
    if (group != null) {
      await FirestoreService.instance
          .saveGroup(group.copyWith(isArchived: false));
    }
  }

  /// Manually re-triggers pending-invite linking.
  /// Used as a pull-to-refresh action so the user can force a sync when
  /// another user has added them to a group recently.
  void refresh() {
    FirestoreService.instance.linkPendingInvites().catchError((_) {});
  }
}

final groupProvider =
    StateNotifierProvider<GroupNotifier, List<GroupModel>>((ref) {
  return GroupNotifier();
});

final activeGroupsProvider = Provider<List<GroupModel>>((ref) {
  return ref.watch(groupProvider).where((g) => !g.isArchived).toList();
});

final archivedGroupsProvider = Provider<List<GroupModel>>((ref) {
  return ref.watch(groupProvider).where((g) => g.isArchived).toList();
});

final groupByIdProvider = Provider.family<GroupModel?, String>((ref, id) {
  try {
    return ref.watch(groupProvider).firstWhere((g) => g.id == id);
  } catch (_) {
    return null;
  }
});
