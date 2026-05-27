import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/expense_model.dart';
import '../models/member_model.dart';
import '../services/firestore_service.dart';
import '../utils/helpers.dart';
import 'group_provider.dart';
import 'auth_provider.dart';
import 'settlement_provider.dart';

// Re-export GroupMonthParam for convenience
export '../utils/helpers.dart' show GroupMonthParam;

// ─── Expenses (real-time Firestore stream) ───────────────────────────────────
class ExpenseNotifier extends StateNotifier<List<ExpenseModel>> {
  ExpenseNotifier() : super([]) {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _expSub?.cancel();
      _expSub = null;
      if (user != null) {
        _expSub =
            FirestoreService.instance.expensesStream().listen((expenses) {
          state = expenses;
        });
      } else {
        state = [];
      }
    });
  }

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<ExpenseModel>>? _expSub;

  @override
  void dispose() {
    _authSub?.cancel();
    _expSub?.cancel();
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

/// Per-group real-time expense stream — directly from Firestore, filtered
/// at the server level so all group members get instant push updates.
final _groupExpensesStreamProvider =
    StreamProvider.family<List<ExpenseModel>, String>((ref, groupId) {
  return FirestoreService.instance.expensesByGroupStream(groupId);
});

final expensesByGroupProvider =
    Provider.family<List<ExpenseModel>, String>((ref, groupId) {
  // Prefer the per-group real-time stream; fall back to global state while
  // loading (e.g. during cold-start before the stream fires first event).
  return ref.watch(_groupExpensesStreamProvider(groupId)).valueOrNull ??
      (ref
          .watch(expenseProvider)
          .where((e) => e.groupId == groupId)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date)));
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

// ─── Current logged-in user's member ID (= Firebase UID) ─────────────────────
final currentUserMemberIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.uid;
});

// ─── Pairwise net debts for a group ──────────────────────────────────────────
// Map<debtorId, Map<creditorId, netAmount>>
final pairwiseDebtsProvider =
    Provider.family<Map<String, Map<String, double>>, String>((ref, groupId) {
  final expenses = ref.watch(expensesByGroupProvider(groupId));
  final settlements = ref.watch(settlementsByGroupProvider(groupId));
  return Helpers.calculatePairwiseDebts(expenses, settlements);
});

// ─── Current user's debts for a specific group ───────────────────────────────
// Returns { 'youOwe': [{memberId, amount}], 'owedToYou': [{memberId, amount}] }
final currentUserGroupDebtsProvider = Provider.family<
    ({List<({String memberId, double amount})> youOwe,
        List<({String memberId, double amount})> owedToYou}),
    String>((ref, groupId) {
  final currentUserId = ref.watch(currentUserMemberIdProvider);
  if (currentUserId == null) {
    return (youOwe: [], owedToYou: []);
  }

  final pairwiseDebts = ref.watch(pairwiseDebtsProvider(groupId));

  final youOwe = <({String memberId, double amount})>[];
  final owedToYou = <({String memberId, double amount})>[];

  // What the current user owes others
  final myDebts = pairwiseDebts[currentUserId] ?? {};
  myDebts.forEach((creditorId, amount) {
    if (amount > 0.01) {
      youOwe.add((memberId: creditorId, amount: amount));
    }
  });

  // What others owe the current user
  pairwiseDebts.forEach((debtorId, creditors) {
    if (debtorId == currentUserId) return;
    final amount = creditors[currentUserId] ?? 0;
    if (amount > 0.01) {
      owedToYou.add((memberId: debtorId, amount: amount));
    }
  });

  // Sort by amount descending
  youOwe.sort((a, b) => b.amount.compareTo(a.amount));
  owedToYou.sort((a, b) => b.amount.compareTo(a.amount));

  return (youOwe: youOwe, owedToYou: owedToYou);
});

// ─── Members (real-time Firestore stream) ────────────────────────────────────
class MemberNotifier extends StateNotifier<List<MemberModel>> {
  MemberNotifier() : super([]) {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _memberSub?.cancel();
      _memberSub = null;
      if (user != null) {
        _memberSub =
            FirestoreService.instance.membersStream().listen((members) {
          state = members;
        });
      } else {
        state = [];
      }
    });
  }

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<MemberModel>>? _memberSub;

  @override
  void dispose() {
    _authSub?.cancel();
    _memberSub?.cancel();
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

// ─── Month-filtered expense providers ────────────────────────────────────────

/// Expenses for a group filtered to a specific month.
final expensesByGroupMonthProvider =
    Provider.family<List<ExpenseModel>, GroupMonthParam>((ref, p) {
  return ref
      .watch(expensesByGroupProvider(p.groupId))
      .where((e) => e.date.year == p.year && e.date.month == p.month)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
});

/// Balances for a group computed from a single month's expenses only.
/// Settlements (all-time) are included so "paid" amounts are reflected correctly.
final balancesByGroupMonthProvider =
    Provider.family<Map<String, double>, GroupMonthParam>((ref, p) {
  final expenses = ref.watch(expensesByGroupMonthProvider(p));
  final settlements = ref.watch(settlementsByGroupProvider(p.groupId));
  return Helpers.calculateBalances(expenses, settlements);
});

/// Selected month for expense-split/balances view (default = current month).
final selectedMonthForGroupProvider =
    StateProvider.family<DateTime, String>((ref, groupId) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

