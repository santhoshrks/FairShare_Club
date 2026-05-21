import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/group_model.dart';
import '../services/firestore_service.dart';
import '../services/hive_service.dart';

// Keep HiveService for settings only
final hiveServiceProvider = Provider<HiveService>((ref) => HiveService());

// ─── Groups (real-time Firestore stream) ─────────────────────────────────────
class GroupNotifier extends StateNotifier<List<GroupModel>> {
  GroupNotifier() : super([]) {
    _subscription = FirestoreService.instance.groupsStream().listen((groups) {
      state = groups;
    });
  }

  StreamSubscription<List<GroupModel>>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
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

  void refresh() {} // no-op: Firestore stream auto-updates
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
