import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/contribution_model.dart';
import '../models/expense_model.dart';
import '../models/member_model.dart';
import '../providers/expense_provider.dart';
import '../providers/pool_provider.dart';
import '../providers/group_provider.dart';
import '../utils/helpers.dart';
import '../utils/constants.dart';
import '../services/notification_service.dart';
import '../widgets/pool_progress_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/member_avatar.dart';

class PoolFundScreen extends ConsumerWidget {
  final String groupId;

  const PoolFundScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(poolBalanceProvider(groupId));
    final totalContributed = ref.watch(totalContributedProvider(groupId));
    final percentage = ref.watch(poolPercentageProvider(groupId));
    final timeline = ref.watch(poolTimelineProvider(groupId));
    final members = ref.watch(membersByGroupProvider(groupId));
    final memberSummary = ref.watch(memberContributionSummaryProvider(groupId));

    // Check low balance and notify
    if (percentage < 20 && totalContributed > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService().showPoolLowBalanceNotification(
          groupName: ref.read(groupByIdProvider(groupId))?.name ?? '',
          balance: balance,
          percentage: percentage,
        );
      });
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Pool Progress
        PoolProgressBar(
          balance: balance,
          totalContributed: totalContributed,
          percentage: percentage,
        ),
        const SizedBox(height: 16),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _showAddExpenseDialog(context, ref),
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                label: const Text('Add Expense'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () =>
                    _showAddContributionDialog(context, ref, members),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Add Contribution'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF43A047),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Member Contributions Summary
        if (memberSummary.isNotEmpty) ...[
          Text(
            'Member Contributions',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...members.map((member) {
            final contributed = memberSummary[member.id] ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    MemberAvatar(
                        name: member.name,
                        colorHex: member.colorHex,
                        size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(member.name,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    ),
                    Text(
                      Helpers.formatCurrency(contributed),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF43A047)),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],

        // Transaction Timeline
        Text(
          'Transaction History',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (timeline.isEmpty)
          const EmptyState(
            icon: Icons.history,
            title: 'No Transactions Yet',
            subtitle: 'Add contributions or expenses to see the history',
          )
        else
          ...timeline.map((item) => _TimelineItem(
                item: item,
                members: members,
              )),
        const SizedBox(height: 80),
      ],
    );
  }

  void _showAddExpenseDialog(BuildContext context, WidgetRef ref) {
    final amountController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pool Expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                prefixText: '₹ ',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: descController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text);
              if (amount == null || amount <= 0 || descController.text.isEmpty) {
                return;
              }
              final members = ref.read(membersByGroupProvider(groupId));
              if (members.isEmpty) return;

              // Pool expense: paid by first member, split equally among all
              final expense = ExpenseModel(
                id: const Uuid().v4(),
                groupId: groupId,
                description: descController.text.trim(),
                amount: amount,
                paidByMemberId: members.first.id,
                splitAmongMemberIds: members.map((m) => m.id).toList(),
                splitType: AppConstants.equalSplit,
                date: DateTime.now(),
                category: 'other',
              );
              await ref.read(expenseProvider.notifier).addExpense(expense);
              Navigator.of(ctx).pop();
            },
            child: const Text('Deduct from Pool'),
          ),
        ],
      ),
    );
  }

  void _showAddContributionDialog(
      BuildContext context, WidgetRef ref, List members) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String? selectedMemberId =
        members.isNotEmpty ? members.first.id : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Contribution'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedMemberId,
                decoration: const InputDecoration(labelText: 'Member'),
                items: members
                    .map<DropdownMenuItem<String>>((m) => DropdownMenuItem(
                          value: m.id as String,
                          child: Text(m.name as String),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setDialogState(() => selectedMemberId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixText: '₹ ',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0 || selectedMemberId == null) {
                  return;
                }
                final c = ContributionModel(
                  id: const Uuid().v4(),
                  groupId: groupId,
                  memberId: selectedMemberId!,
                  amount: amount,
                  date: DateTime.now(),
                  note: noteController.text.trim(),
                );
                await ref
                    .read(contributionProvider.notifier)
                    .addContribution(c);
                Navigator.of(ctx).pop();
              },
              child: const Text('Add to Pool'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final List<MemberModel> members;

  const _TimelineItem({required this.item, required this.members});

  @override
  Widget build(BuildContext context) {
    final isContribution = item['type'] == 'contribution';
    final theme = Theme.of(context);
    final color =
        isContribution ? const Color(0xFF43A047) : const Color(0xFFE53935);
    final icon = isContribution ? Icons.add_circle : Icons.remove_circle;

    String memberName = 'Unknown';
    double amount = 0;
    String desc = '';
    DateTime date = DateTime.now();

    if (isContribution) {
      final c = item['data'] as ContributionModel;
      amount = c.amount;
      date = c.date;
      desc = c.note.isNotEmpty ? c.note : 'Contribution';
      final member = members.firstWhereOrNull(
        (m) => m.id == c.memberId,
      );
      if (member != null) {
        memberName = member.name as String;
      }
    } else {
      final e = item['data'];
      amount = e.amount as double;
      date = e.date as DateTime;
      desc = e.description as String;
      final member = members.firstWhereOrNull(
        (m) => m.id == e.paidByMemberId,
      );
      if (member != null) {
        memberName = member.name as String;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(desc,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '$memberName • ${Helpers.formatDate(date)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Text(
              '${isContribution ? '+' : '-'}${Helpers.formatCurrency(amount)}',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}






