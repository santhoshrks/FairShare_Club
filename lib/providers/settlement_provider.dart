import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settlement_model.dart';
import '../services/firestore_service.dart';

class SettlementNotifier extends StateNotifier<List<SettlementModel>> {
  SettlementNotifier() : super([]) {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _settleSub?.cancel();
      _settleSub = null;
      if (user != null) {
        _settleSub =
            FirestoreService.instance.settlementsStream().listen((s) {
          state = s;
        });
      } else {
        state = [];
      }
    });
  }

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<SettlementModel>>? _settleSub;

  @override
  void dispose() {
    _authSub?.cancel();
    _settleSub?.cancel();
    super.dispose();
  }

  Future<void> addSettlement(SettlementModel s) =>
      FirestoreService.instance.saveSettlement(s);
}

final settlementProvider =
    StateNotifierProvider<SettlementNotifier, List<SettlementModel>>((ref) {
  return SettlementNotifier();
});

/// Per-group real-time settlements stream.
final _groupSettlementsStreamProvider =
    StreamProvider.family<List<SettlementModel>, String>((ref, groupId) {
  return FirestoreService.instance.settlementsByGroupStream(groupId);
});

final settlementsByGroupProvider =
    Provider.family<List<SettlementModel>, String>((ref, groupId) {
  return ref.watch(_groupSettlementsStreamProvider(groupId)).valueOrNull ??
      (ref
          .watch(settlementProvider)
          .where((s) => s.groupId == groupId)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date)));
});

