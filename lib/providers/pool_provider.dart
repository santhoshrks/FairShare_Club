import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contribution_model.dart';
import '../models/expense_model.dart';
import '../providers/expense_provider.dart';
import '../services/firestore_service.dart';

// ─── Contributions (real-time Firestore stream) ───────────────────────────────
class ContributionNotifier extends StateNotifier<List<ContributionModel>> {
  ContributionNotifier() : super([]) {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _contribSub?.cancel();
      _contribSub = null;
      if (user != null) {
        _contribSub =
            FirestoreService.instance.contributionsStream().listen((contributions) {
          state = contributions;
        });
      } else {
        state = [];
      }
    });
  }

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<ContributionModel>>? _contribSub;

  @override
  void dispose() {
    _authSub?.cancel();
    _contribSub?.cancel();
    super.dispose();
  }

  Future<void> addContribution(ContributionModel contribution) =>
      FirestoreService.instance.saveContribution(contribution);

  Future<void> deleteContribution(String id) =>
      FirestoreService.instance.deleteContribution(id);

  void refresh() {} // no-op: Firestore stream auto-updates
}

final contributionProvider =
    StateNotifierProvider<ContributionNotifier, List<ContributionModel>>((ref) {
  return ContributionNotifier();
});

/// Per-group real-time contributions stream.
final _groupContributionsStreamProvider =
    StreamProvider.family<List<ContributionModel>, String>((ref, groupId) {
  return FirestoreService.instance.contributionsByGroupStream(groupId);
});

final contributionsByGroupProvider =
    Provider.family<List<ContributionModel>, String>((ref, groupId) {
  return ref.watch(_groupContributionsStreamProvider(groupId)).valueOrNull ??
      (ref
          .watch(contributionProvider)
          .where((c) => c.groupId == groupId)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date)));
});

// ─── Selected month for pool fund (default = current month) ──────────────────
final poolSelectedMonthProvider =
    StateProvider.family<DateTime, String>((ref, groupId) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

// ─── Month-filtered contributions ────────────────────────────────────────────
final contributionsByGroupMonthProvider =
    Provider.family<List<ContributionModel>, GroupMonthParam>((ref, p) {
  return ref
      .watch(contributionsByGroupProvider(p.groupId))
      .where((c) => c.date.year == p.year && c.date.month == p.month)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
});

// ─── Month-filtered pool expenses ─────────────────────────────────────────────
final poolExpensesByGroupMonthProvider =
    Provider.family<List<ExpenseModel>, GroupMonthParam>((ref, p) {
  return ref
      .watch(expensesByGroupProvider(p.groupId))
      .where((e) => e.date.year == p.year && e.date.month == p.month)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
});

// ─── Monthly totals ───────────────────────────────────────────────────────────
final poolMonthlyTotalContributedProvider =
    Provider.family<double, GroupMonthParam>((ref, p) {
  final contributions = ref.watch(contributionsByGroupMonthProvider(p));
  return contributions.fold(0.0, (sum, c) => sum + c.amount);
});

final poolMonthlyTotalSpentProvider =
    Provider.family<double, GroupMonthParam>((ref, p) {
  final expenses = ref.watch(poolExpensesByGroupMonthProvider(p));
  return expenses.fold(0.0, (sum, e) => sum + e.amount);
});

final poolMonthlyBalanceProvider =
    Provider.family<double, GroupMonthParam>((ref, p) {
  final contributed = ref.watch(poolMonthlyTotalContributedProvider(p));
  final spent = ref.watch(poolMonthlyTotalSpentProvider(p));
  return contributed - spent;
});

final poolMonthlyPercentageProvider =
    Provider.family<double, GroupMonthParam>((ref, p) {
  final total = ref.watch(poolMonthlyTotalContributedProvider(p));
  if (total <= 0) return 0;
  final balance = ref.watch(poolMonthlyBalanceProvider(p));
  return (balance / total * 100).clamp(0, 100);
});

// ─── Monthly timeline (contributions + expenses) ──────────────────────────────
final poolMonthlyTimelineProvider =
    Provider.family<List<Map<String, dynamic>>, GroupMonthParam>((ref, p) {
  final contributions = ref.watch(contributionsByGroupMonthProvider(p));
  final expenses = ref.watch(poolExpensesByGroupMonthProvider(p));

  final List<Map<String, dynamic>> timeline = [];
  for (final c in contributions) {
    timeline.add({'type': 'contribution', 'data': c, 'date': c.date});
  }
  for (final e in expenses) {
    timeline.add({'type': 'expense', 'data': e, 'date': e.date});
  }
  timeline.sort(
      (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
  return timeline;
});

// ─── All-time timeline ────────────────────────────────────────────────────────
final poolTimelineProvider =
    Provider.family<List<Map<String, dynamic>>, String>((ref, groupId) {
  final contributions = ref.watch(contributionsByGroupProvider(groupId));
  final expenses = ref.watch(expensesByGroupProvider(groupId));

  final List<Map<String, dynamic>> timeline = [];
  for (final c in contributions) {
    timeline.add({'type': 'contribution', 'data': c, 'date': c.date});
  }
  for (final e in expenses) {
    timeline.add({'type': 'expense', 'data': e, 'date': e.date});
  }
  timeline.sort(
      (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
  return timeline;
});

// ─── Monthly member contribution summary ──────────────────────────────────────
final memberContributionSummaryMonthProvider =
    Provider.family<Map<String, double>, GroupMonthParam>((ref, p) {
  final contributions = ref.watch(contributionsByGroupMonthProvider(p));
  final Map<String, double> summary = {};
  for (final c in contributions) {
    summary[c.memberId] = (summary[c.memberId] ?? 0) + c.amount;
  }
  return summary;
});

// ─── Monthly member pool balance (contributed this month - spent this month) ──
final memberPoolBalanceMonthProvider =
    Provider.family<Map<String, double>, GroupMonthParam>((ref, p) {
  final contributed = ref.watch(memberContributionSummaryMonthProvider(p));
  final expenses = ref.watch(poolExpensesByGroupMonthProvider(p));

  final Map<String, double> usage = {};
  for (final e in expenses) {
    if (e.splitAmongMemberIds.length == 1 &&
        e.splitAmongMemberIds.first == e.paidByMemberId) {
      usage[e.paidByMemberId] = (usage[e.paidByMemberId] ?? 0) + e.amount;
    }
  }

  final members = ref.watch(membersByGroupProvider(p.groupId));
  final Map<String, double> balances = {};
  for (final m in members) {
    balances[m.id] = (contributed[m.id] ?? 0) - (usage[m.id] ?? 0);
  }
  return balances;
});

// ─── Overall / all-time totals ────────────────────────────────────────────────
final poolBalanceProvider = Provider.family<double, String>((ref, groupId) {
  final contributions = ref.watch(contributionsByGroupProvider(groupId));
  final totalContributed =
      contributions.fold(0.0, (sum, c) => sum + c.amount);
  final expenses = ref.watch(expensesByGroupProvider(groupId));
  final totalSpent = expenses.fold(0.0, (sum, e) => sum + e.amount);
  return totalContributed - totalSpent;
});

final totalContributedProvider = Provider.family<double, String>((ref, groupId) {
  final contributions = ref.watch(contributionsByGroupProvider(groupId));
  return contributions.fold(0.0, (sum, c) => sum + c.amount);
});

final poolPercentageProvider = Provider.family<double, String>((ref, groupId) {
  final total = ref.watch(totalContributedProvider(groupId));
  if (total <= 0) return 0;
  final balance = ref.watch(poolBalanceProvider(groupId));
  return (balance / total * 100).clamp(0, 100);
});

// Member contribution summary for pool (all-time)
final memberContributionSummaryProvider =
    Provider.family<Map<String, double>, String>((ref, groupId) {
  final contributions = ref.watch(contributionsByGroupProvider(groupId));
  final Map<String, double> summary = {};
  for (final c in contributions) {
    summary[c.memberId] = (summary[c.memberId] ?? 0) + c.amount;
  }
  return summary;
});

// Per-member pool usage (all-time)
final memberPoolUsageProvider =
    Provider.family<Map<String, double>, String>((ref, groupId) {
  final expenses = ref.watch(expensesByGroupProvider(groupId));
  final Map<String, double> usage = {};
  for (final e in expenses) {
    if (e.splitAmongMemberIds.length == 1 &&
        e.splitAmongMemberIds.first == e.paidByMemberId) {
      usage[e.paidByMemberId] = (usage[e.paidByMemberId] ?? 0) + e.amount;
    }
  }
  return usage;
});

// Remaining pool balance per member (all-time)
final memberPoolBalanceProvider =
    Provider.family<Map<String, double>, String>((ref, groupId) {
  final contributed = ref.watch(memberContributionSummaryProvider(groupId));
  final used = ref.watch(memberPoolUsageProvider(groupId));
  final members = ref.watch(membersByGroupProvider(groupId));
  final Map<String, double> balances = {};
  for (final m in members) {
    balances[m.id] = (contributed[m.id] ?? 0) - (used[m.id] ?? 0);
  }
  return balances;
});

