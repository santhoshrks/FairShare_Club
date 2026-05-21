import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contribution_model.dart';
import '../providers/group_provider.dart';
import '../providers/expense_provider.dart';
import '../services/firestore_service.dart';

// ─── Contributions (real-time Firestore stream) ───────────────────────────────
class ContributionNotifier extends StateNotifier<List<ContributionModel>> {
  ContributionNotifier() : super([]) {
    _subscription =
        FirestoreService.instance.contributionsStream().listen((contributions) {
      state = contributions;
    });
  }

  StreamSubscription<List<ContributionModel>>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
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

final contributionsByGroupProvider =
    Provider.family<List<ContributionModel>, String>((ref, groupId) {
  return ref
      .watch(contributionProvider)
      .where((c) => c.groupId == groupId)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
});

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

// Combined pool timeline (contributions + expenses)
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

// Member contribution summary for pool
final memberContributionSummaryProvider =
    Provider.family<Map<String, double>, String>((ref, groupId) {
  final contributions = ref.watch(contributionsByGroupProvider(groupId));
  final Map<String, double> summary = {};
  for (final c in contributions) {
    summary[c.memberId] = (summary[c.memberId] ?? 0) + c.amount;
  }
  return summary;
});
