import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/expense_model.dart';
import '../models/member_model.dart';
import '../services/firestore_service.dart';
import '../utils/helpers.dart';
import 'group_provider.dart';

// ─── Expenses (real-time Firestore stream) ───────────────────────────────────
class ExpenseNotifier extends StateNotifier<List<ExpenseModel>> {
  ExpenseNotifier() : super([]) {
    _subscription =
        FirestoreService.instance.expensesStream().listen((expenses) {
      state = expenses;
    });
  }

  StreamSubscription<List<ExpenseModel>>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> addExpense(ExpenseModel expense) =>
      FirestoreService.instance.saveExpense(expense);

  Future<void> updateExpense(ExpenseModel expense) =>
      FirestoreService.instance.saveExpense(expense);

  Future<void> deleteExpense(String id) =>
      FirestoreService.instance.deleteExpense(id);

  void refresh() {} // no-op: Firestore stream auto-updates
}

final expenseProvider =
    StateNotifierProvider<ExpenseNotifier, List<ExpenseModel>>((ref) {
  return ExpenseNotifier();
});

final expensesByGroupProvider =
    Provider.family<List<ExpenseModel>, String>((ref, groupId) {
  return ref
      .watch(expenseProvider)
      .where((e) => e.groupId == groupId)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
});

final balancesByGroupProvider =
    Provider.family<Map<String, double>, String>((ref, groupId) {
  final expenses = ref.watch(expensesByGroupProvider(groupId));
  return Helpers.calculateBalances(expenses);
});

final settlementsProvider =
    Provider.family<List<Map<String, dynamic>>, String>((ref, groupId) {
  final balances = ref.watch(balancesByGroupProvider(groupId));
  return Helpers.simplifyDebts(balances);
});

// ─── Members (real-time Firestore stream) ────────────────────────────────────
class MemberNotifier extends StateNotifier<List<MemberModel>> {
  MemberNotifier() : super([]) {
    _subscription =
        FirestoreService.instance.membersStream().listen((members) {
      state = members;
    });
  }

  StreamSubscription<List<MemberModel>>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> addMember(MemberModel member) =>
      FirestoreService.instance.saveMember(member);

  Future<void> updateMember(MemberModel member) =>
      FirestoreService.instance.saveMember(member);

  Future<void> deleteMember(String id) =>
      FirestoreService.instance.deleteMember(id);

  void refresh() {} // no-op: Firestore stream auto-updates
}

final memberProvider =
    StateNotifierProvider<MemberNotifier, List<MemberModel>>((ref) {
  return MemberNotifier();
});

final membersByGroupProvider =
    Provider.family<List<MemberModel>, String>((ref, groupId) {
  final group = ref.watch(groupByIdProvider(groupId));
  if (group == null) return [];
  final allMembers = ref.watch(memberProvider);
  return allMembers.where((m) => group.memberIds.contains(m.id)).toList();
});

final memberByIdProvider = Provider.family<MemberModel?, String>((ref, id) {
  try {
    return ref.watch(memberProvider).firstWhere((m) => m.id == id);
  } catch (_) {
    return null;
  }
});
