import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/contribution_model.dart';
import '../models/expense_model.dart';
import '../models/group_model.dart';
import '../models/member_model.dart';
import '../providers/expense_provider.dart';
import '../providers/pool_provider.dart';
import '../providers/group_provider.dart';
import '../utils/helpers.dart';
import '../utils/constants.dart';
import '../services/notification_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/member_avatar.dart';

// Minimum selectable month
final _kMinMonth = DateTime(2026, 1);

String _monthKey(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}';

String _formatMonth(DateTime dt) => DateFormat('MMMM yyyy').format(dt);

bool _isCurrentMonth(DateTime dt) {
  final now = DateTime.now();
  return dt.year == now.year && dt.month == now.month;
}

class PoolFundScreen extends ConsumerStatefulWidget {
  final String groupId;
  const PoolFundScreen({super.key, required this.groupId});

  @override
  ConsumerState<PoolFundScreen> createState() => _PoolFundScreenState();
}

class _PoolFundScreenState extends ConsumerState<PoolFundScreen> {
  bool _showOverall = false;

  DateTime get _maxMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final selectedMonth =
        ref.watch(poolSelectedMonthProvider(widget.groupId));
    final group = ref.watch(groupByIdProvider(widget.groupId));
    final members = ref.watch(membersByGroupProvider(widget.groupId));

    final p = GroupMonthParam(
      groupId: widget.groupId,
      year: selectedMonth.year,
      month: selectedMonth.month,
    );

    final balance = ref.watch(poolMonthlyBalanceProvider(p));
    final totalContributed =
        ref.watch(poolMonthlyTotalContributedProvider(p));
    final totalSpent = ref.watch(poolMonthlyTotalSpentProvider(p));
    final percentage = ref.watch(poolMonthlyPercentageProvider(p));

    final List<Map<String, dynamic>> timeline = _showOverall
        ? ref.watch(poolTimelineProvider(widget.groupId))
        : ref.watch(poolMonthlyTimelineProvider(p));

    final memberSummary =
        ref.watch(memberContributionSummaryMonthProvider(p));
    final memberBalances =
        ref.watch(memberPoolBalanceMonthProvider(p));

    final isContributionClosed =
        group?.poolContributionClosedMonths.contains(_monthKey(selectedMonth)) ??
            false;
    final isCurrent = _isCurrentMonth(selectedMonth);

    // Low balance notification (25% threshold)
    if (percentage < 25 && totalContributed > 0 && isCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService().showPoolLowBalanceNotification(
          groupName: group?.name ?? '',
          balance: balance,
          percentage: percentage,
        );
      });
    }

    final hasRecords =
        memberSummary.isNotEmpty || timeline.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Month Selector ─────────────────────────────────────────────────
        _MonthSelector(
          selectedMonth: selectedMonth,
          minMonth: _kMinMonth,
          maxMonth: _maxMonth,
          onChanged: (month) {
            ref
                .read(poolSelectedMonthProvider(widget.groupId).notifier)
                .state = month;
          },
        ),
        const SizedBox(height: 12),

        // ── Balance Summary Card (member icons, no progress bar) ────────────
        _BalanceSummaryCard(
          balance: balance,
          totalContributed: totalContributed,
          totalSpent: totalSpent,
          percentage: percentage,
          members: members,
          isContributionClosed: isContributionClosed,
          selectedMonth: selectedMonth,
        ),
        const SizedBox(height: 16),

        // ── Action Buttons ─────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () =>
                    _showAddExpenseDialog(context, ref, selectedMonth),
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
                onPressed:
                    (isContributionClosed || !isCurrent)
                        ? null
                        : () => _showAddContributionDialog(
                            context, ref, members),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Add Contribution'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF43A047),
                ),
              ),
            ),
          ],
        ),

        // ── Load Money for All Button ──────────────────────────────────────
        if (!isContributionClosed && isCurrent && members.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () =>
                  _showLoadForAllDialog(context, ref, members),
              icon: const Icon(Icons.group_add, size: 18),
              label: const Text('Load Money for All'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
              ),
            ),
          ),
        ],

        // ── Close Contribution Button ──────────────────────────────────────
        if (isCurrent && !isContributionClosed && group != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  _closeContribution(context, ref, group, selectedMonth),
              icon: Icon(Icons.lock_outline,
                  size: 18, color: Colors.orange.shade700),
              label: Text(
                'Close Contribution',
                style: TextStyle(color: Colors.orange.shade700),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.orange.shade400),
              ),
            ),
          ),
        ],

        // ── Contribution Closed Banner ─────────────────────────────────────
        if (isContributionClosed) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.lock, size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isCurrent
                        ? 'Contributions are closed for this month'
                        : 'Contributions were closed for ${_formatMonth(selectedMonth)}',
                    style: TextStyle(
                        color: Colors.orange.shade700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // ── No Records ─────────────────────────────────────────────────────
        if (!hasRecords) ...[
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nothing is here',
            subtitle:
                'No contributions or expenses for this month yet.',
          ),
        ] else ...[
          // ── Member Pool Balances ─────────────────────────────────────────
          if (memberSummary.isNotEmpty) ...[
            Text(
              'Member Pool Balances',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...members.map((member) {
              final remaining = memberBalances[member.id] ?? 0;
              final contributed = memberSummary[member.id] ?? 0;
              if (contributed == 0) return const SizedBox.shrink();
              final isZero = remaining <= 0.01;
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(member.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text(
                              'Contributed: ${Helpers.formatCurrency(contributed)}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Helpers.formatCurrency(remaining),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isZero
                                    ? Colors.red.shade600
                                    : const Color(0xFF43A047)),
                          ),
                          Text(
                            isZero ? 'No balance' : 'Remaining',
                            style: TextStyle(
                                fontSize: 10,
                                color: isZero
                                    ? Colors.red.shade400
                                    : Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],

          // ── Transaction History ──────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Transaction History',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => _showOverall = !_showOverall),
                child: Text(
                  _showOverall ? 'This Month' : 'Overall',
                  style: const TextStyle(color: Color(0xFF00897B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_showOverall)
            Text(
              'Showing all-time transactions',
              style:
                  TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          const SizedBox(height: 8),
          if (timeline.isEmpty)
            const EmptyState(
              icon: Icons.history,
              title: 'Nothing is here',
              subtitle: 'No transactions for this period',
            )
          else
            ...timeline.map((item) => _TimelineItem(
                  item: item,
                  members: members,
                )),
        ],

        const SizedBox(height: 80),
      ],
    );
  }

  void _closeContribution(BuildContext context, WidgetRef ref,
      GroupModel group, DateTime selectedMonth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.lock_outline, color: Colors.orange),
          SizedBox(width: 8),
          Text('Close Contribution'),
        ]),
        content: Text(
          'Close contributions for ${_formatMonth(selectedMonth)}?\n\n'
          'No new contributions can be added until next month.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final key = _monthKey(selectedMonth);
              final updated = group.copyWith(
                poolContributionClosedMonths: [
                  ...group.poolContributionClosedMonths,
                  key
                ],
              );
              await ref
                  .read(groupProvider.notifier)
                  .updateGroup(updated);
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAddExpenseDialog(
      BuildContext context, WidgetRef ref, DateTime selectedMonth) {
    final members = ref.read(membersByGroupProvider(widget.groupId));
    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add members first')),
      );
      return;
    }

    final amountController = TextEditingController();
    final descController = TextEditingController();
    String selectedMemberId = members.first.id;

    // Always check against current month's balance (expense is dated today)
    final now = DateTime.now();
    final currentMonthParam = GroupMonthParam(
        groupId: widget.groupId, year: now.year, month: now.month);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final memberBalances =
              ref.read(memberPoolBalanceMonthProvider(currentMonthParam));
          final memberBalance = memberBalances[selectedMemberId] ?? 0;
          final isBalanceZero = memberBalance <= 0.01;

          return AlertDialog(
            title: const Text('Add Pool Expense'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedMemberId,
                    decoration:
                        const InputDecoration(labelText: 'Member'),
                    items: members
                        .map<DropdownMenuItem<String>>(
                            (m) => DropdownMenuItem(
                                  value: m.id,
                                  child: Text(m.name),
                                ))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedMemberId = v!),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isBalanceZero
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isBalanceZero
                              ? Colors.red.shade200
                              : Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isBalanceZero
                              ? 'No remaining balance this month'
                              : 'Available this month: ${Helpers.formatCurrency(memberBalance)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isBalanceZero
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                          ),
                        ),
                        if (isBalanceZero)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'This member has used all their contribution this month.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red.shade600),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountController,
                    enabled: !isBalanceZero,
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹)',
                      prefixText: '₹ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descController,
                    enabled: !isBalanceZero,
                    decoration:
                        const InputDecoration(labelText: 'Description'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: isBalanceZero
                    ? null
                    : () async {
                        final amount = double.tryParse(
                            amountController.text.trim());
                        if (amount == null || amount <= 0) {
                          // Show error IN FRONT of the dialog using the outer context
                          showDialog(
                            context: context,
                            builder: (errCtx) => AlertDialog(
                              title: const Text('Invalid Amount'),
                              content: const Text(
                                  'Please enter a valid amount.'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(errCtx).pop(),
                                    child: const Text('OK'))
                              ],
                            ),
                          );
                          return;
                        }
                        if (descController.text.trim().isEmpty) {
                          // Show error IN FRONT of the dialog using the outer context
                          showDialog(
                            context: context,
                            builder: (errCtx) => AlertDialog(
                              title: const Text('Description Required'),
                              content: const Text(
                                  'Please enter a description for this expense.'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(errCtx).pop(),
                                    child: const Text('OK'))
                              ],
                            ),
                          );
                          return;
                        }

                        final currentBalance = ref
                                .read(memberPoolBalanceMonthProvider(
                                    currentMonthParam))[
                            selectedMemberId] ??
                            0;
                        if (amount > currentBalance + 0.01) {
                          Navigator.of(ctx).pop();
                          if (context.mounted) {
                            showDialog(
                              context: context,
                              builder: (alertCtx) => AlertDialog(
                                title: const Row(children: [
                                  Icon(Icons.warning_amber_rounded,
                                      color: Colors.orange),
                                  SizedBox(width: 8),
                                  Text('Exceeds Balance'),
                                ]),
                                content: Text(
                                  'This member only has '
                                  '${Helpers.formatCurrency(currentBalance)} remaining this month.\n\n'
                                  'You can add up to ${Helpers.formatCurrency(currentBalance)} for this member.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(alertCtx).pop(),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          }
                          return;
                        }

                        Navigator.of(ctx).pop();

                        final selectedMember = members
                            .firstWhere((m) => m.id == selectedMemberId);
                        final expense = ExpenseModel(
                          id: const Uuid().v4(),
                          groupId: widget.groupId,
                          description: descController.text.trim(),
                          amount: amount,
                          paidByMemberId: selectedMemberId,
                          splitAmongMemberIds: [selectedMemberId],
                          splitType: AppConstants.equalSplit,
                          date: DateTime.now(),
                          category: 'other',
                        );
                        await ref
                            .read(expenseProvider.notifier)
                            .addExpense(expense);

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                            content: Text(
                                '✅ ₹${amount.toStringAsFixed(0)} deducted from ${selectedMember.name}\'s pool balance'),
                            backgroundColor: const Color(0xFF00897B),
                          ));
                        }
                      },
                child: const Text('Deduct from Pool'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddContributionDialog(
      BuildContext context, WidgetRef ref, List<MemberModel> members) {
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
                decoration:
                    const InputDecoration(labelText: 'Member'),
                items: members
                    .map<DropdownMenuItem<String>>(
                        (m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.name),
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
                decoration: const InputDecoration(
                    labelText: 'Note (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final amount =
                    double.tryParse(amountController.text);
                if (amount == null ||
                    amount <= 0 ||
                    selectedMemberId == null) {
                  return;
                }
                final c = ContributionModel(
                  id: const Uuid().v4(),
                  groupId: widget.groupId,
                  memberId: selectedMemberId!,
                  amount: amount,
                  date: DateTime.now(),
                  note: noteController.text.trim(),
                );
                await ref
                    .read(contributionProvider.notifier)
                    .addContribution(c);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Add to Pool'),
            ),
          ],
        ),
      ),
    );
  }
  void _showLoadForAllDialog(
      BuildContext context, WidgetRef ref, List<MemberModel> members) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.group_add, color: Color(0xFF00897B)),
          SizedBox(width: 8),
          Text('Load Money for All'),
        ]),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter one amount to add as contribution for all '
                '${members.length} member${members.length != 1 ? 's' : ''}.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount per member (₹)',
                  prefixText: '₹ ',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final val = double.tryParse(v ?? '');
                  if (val == null || val <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteController,
                decoration:
                    const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.done_all, size: 16),
            label: const Text('Add for All'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                foregroundColor: Colors.white),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final amount =
                  double.tryParse(amountController.text.trim()) ?? 0;
              final note = noteController.text.trim().isNotEmpty
                  ? noteController.text.trim()
                  : 'Load for all';
              Navigator.of(ctx).pop();

              for (final member in members) {
                await ref
                    .read(contributionProvider.notifier)
                    .addContribution(ContributionModel(
                  id: const Uuid().v4(),
                  groupId: widget.groupId,
                  memberId: member.id,
                  amount: amount,
                  date: DateTime.now(),
                  note: note,
                ));
              }

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      '✅ ₹${amount.toStringAsFixed(0)} added for all '
                      '${members.length} members'),
                  backgroundColor: const Color(0xFF00897B),
                ));
              }
            },
          ),
        ],
      ),
    );
  }
}
class _MonthSelector extends StatelessWidget {
  final DateTime selectedMonth;
  final DateTime minMonth;
  final DateTime maxMonth;
  final ValueChanged<DateTime> onChanged;

  const _MonthSelector({
    required this.selectedMonth,
    required this.minMonth,
    required this.maxMonth,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canGoPrev = selectedMonth.isAfter(minMonth) ||
        (selectedMonth.year == minMonth.year &&
            selectedMonth.month > minMonth.month);
    final isAtMax = selectedMonth.year == maxMonth.year &&
        selectedMonth.month == maxMonth.month;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: canGoPrev
                ? () {
                    final prev = DateTime(
                        selectedMonth.year, selectedMonth.month - 1);
                    onChanged(prev);
                  }
                : null,
            color: canGoPrev ? const Color(0xFF00897B) : Colors.grey[300],
          ),
          GestureDetector(
            onTap: () => _pickMonth(context),
            child: Column(
              children: [
                Text(
                  _formatMonth(selectedMonth),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (_isCurrentMonth(selectedMonth))
                  Text(
                    'Current Month',
                    style: TextStyle(
                        fontSize: 11, color: Colors.green.shade600),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: isAtMax
                ? null
                : () {
                    final next = DateTime(
                        selectedMonth.year, selectedMonth.month + 1);
                    onChanged(next);
                  },
            color: isAtMax ? Colors.grey[300] : const Color(0xFF00897B),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMonth(BuildContext context) async {
    // Build list of available months from minMonth to maxMonth
    final months = <DateTime>[];
    var cur = DateTime(minMonth.year, minMonth.month);
    while (!cur.isAfter(maxMonth)) {
      months.add(cur);
      cur = DateTime(cur.year, cur.month + 1);
    }
    months.sort((a, b) => b.compareTo(a)); // newest first

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Month'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: months.length,
            itemBuilder: (_, i) {
              final m = months[i];
              final isSelected = m.year == selectedMonth.year &&
                  m.month == selectedMonth.month;
              return ListTile(
                title: Text(_formatMonth(m)),
                trailing: isSelected
                    ? const Icon(Icons.check, color: Color(0xFF00897B))
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  onChanged(m);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Balance Summary Card (no progress bar, shows member icons) ───────────────
class _BalanceSummaryCard extends StatelessWidget {
  final double balance;
  final double totalContributed;
  final double totalSpent;
  final double percentage;
  final List<MemberModel> members;
  final bool isContributionClosed;
  final DateTime selectedMonth;

  const _BalanceSummaryCard({
    required this.balance,
    required this.totalContributed,
    required this.totalSpent,
    required this.percentage,
    required this.members,
    required this.isContributionClosed,
    required this.selectedMonth,
  });

  Color get _statusColor {
    if (totalContributed <= 0) return Colors.grey;
    if (percentage > 50) return const Color(0xFF43A047);
    if (percentage > 25) return const Color(0xFFFB8C00);
    return const Color(0xFFE53935);
  }

  String get _statusLabel {
    if (totalContributed <= 0) return 'No Data';
    if (percentage > 50) return 'Healthy';
    if (percentage > 25) return 'Running Low';
    return 'Critical';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Balance info
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pool Balance',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Helpers.formatCurrency(balance),
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _statusColor,
                          ),
                    ),
                  ],
                ),
                // Status chip + members
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle,
                              size: 8, color: _statusColor),
                          const SizedBox(width: 4),
                          Text(
                            _statusLabel,
                            style: TextStyle(
                              color: _statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Member icons (instead of progress bar)
                    if (members.isNotEmpty)
                      MemberAvatarStack(
                        members: members
                            .take(5)
                            .map((m) =>
                                (name: m.name, colorHex: m.colorHex))
                            .toList(),
                        size: 28,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Sub-stats row
            Row(
              children: [
                _Stat(
                  label: 'Contributed',
                  value: Helpers.formatCurrency(totalContributed),
                  color: const Color(0xFF43A047),
                ),
                Container(
                    width: 1,
                    height: 32,
                    color: Colors.grey[200],
                    margin: const EdgeInsets.symmetric(horizontal: 12)),
                _Stat(
                  label: 'Spent',
                  value: Helpers.formatCurrency(totalSpent),
                  color: const Color(0xFFE53935),
                ),
                Container(
                    width: 1,
                    height: 32,
                    color: Colors.grey[200],
                    margin: const EdgeInsets.symmetric(horizontal: 12)),
                _Stat(
                  label: 'Remaining',
                  value: totalContributed > 0
                      ? '${percentage.toStringAsFixed(1)}%'
                      : '—',
                  color: _statusColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── Timeline Item ────────────────────────────────────────────────────────────
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
    final icon =
        isContribution ? Icons.add_circle : Icons.remove_circle;

    String memberName = 'Unknown';
    double amount = 0;
    String desc = '';
    DateTime date = DateTime.now();

    if (isContribution) {
      final c = item['data'] as ContributionModel;
      amount = c.amount;
      date = c.date;
      desc = c.note.isNotEmpty ? c.note : 'Contribution';
      final member =
          members.firstWhereOrNull((m) => m.id == c.memberId);
      if (member != null) memberName = member.name;
    } else {
      final e = item['data'] as ExpenseModel;
      amount = e.amount;
      date = e.date;
      desc = e.description;
      final member =
          members.firstWhereOrNull((m) => m.id == e.paidByMemberId);
      if (member != null) memberName = member.name;
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
                      style:
                          const TextStyle(fontWeight: FontWeight.w500),
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
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}


