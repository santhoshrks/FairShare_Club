import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../models/expense_model.dart';
import '../models/member_model.dart';
import '../providers/expense_provider.dart';
import '../utils/helpers.dart';
import '../utils/constants.dart';
import '../widgets/balance_card.dart';
import '../widgets/expense_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/member_avatar.dart';

class ExpenseSplitScreen extends ConsumerWidget {
  final String groupId;

  const ExpenseSplitScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(balancesByGroupProvider(groupId));
    final settlements = ref.watch(settlementsProvider(groupId));
    final members = ref.watch(membersByGroupProvider(groupId));
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: theme.appBarTheme.backgroundColor,
            child: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.white,
              tabs: [
                Tab(text: 'Balances'),
                Tab(text: 'Expenses'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Balances Tab
                _BalancesTab(
                  groupId: groupId,
                  balances: balances,
                  settlements: settlements,
                  members: members,
                ),

                // Expenses Tab
                _ExpensesTab(groupId: groupId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalancesTab extends ConsumerWidget {
  final String groupId;
  final Map<String, double> balances;
  final List<Map<String, dynamic>> settlements;
  final List<MemberModel> members;

  const _BalancesTab({
    required this.groupId,
    required this.balances,
    required this.settlements,
    required this.members,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expenses = ref.watch(expensesByGroupProvider(groupId));
    final totalSpent = expenses.fold(0.0, (s, e) => s + e.amount);

    if (members.isEmpty) {
      return const EmptyState(
        icon: Icons.people_alt_outlined,
        title: 'No Members',
        subtitle: 'Add members to track balances',
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(expensesByGroupProvider(groupId));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary card
          Card(
            color: const Color(0xFF00897B),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Group Spend',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          Helpers.formatCurrency(totalSpent),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt_long, color: Colors.white, size: 30),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Member Balances
          Text('Member Balances', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (balances.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No expenses yet', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...members.map((member) {
              final bal = balances[member.id] ?? 0.0;
              return BalanceCard(
                member: member,
                balance: bal,
                onSettleUp: bal < 0
                    ? () => _showSettleUpDialog(context, ref, member.id, bal.abs())
                    : null,
              );
            }),

          if (settlements.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Suggested Payments',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...settlements.map((s) {
              final from =
                  members.firstWhereOrNull((m) => m.id == s['from']);
              final to =
                  members.firstWhereOrNull((m) => m.id == s['to']);
              if (from == null || to == null) return const SizedBox.shrink();
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      MemberAvatar(
                          name: from.name,
                          colorHex: from.colorHex,
                          size: 36),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: DefaultTextStyle.of(context).style,
                                children: [
                                  TextSpan(
                                      text: from.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const TextSpan(text: ' pays '),
                                  TextSpan(
                                      text: to.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            Text(
                              Helpers.formatCurrency(
                                  s['amount'] as double),
                              style: const TextStyle(
                                  color: Color(0xFF00897B),
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      MemberAvatar(
                          name: to.name, colorHex: to.colorHex, size: 36),
                      const SizedBox(width: 8),
                      // ✅ Mark as Paid button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12),
                          backgroundColor: const Color(0xFF00897B),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _recordSettlement(
                          context,
                          ref,
                          fromMemberId: s['from'] as String,
                          toMemberId: s['to'] as String,
                          amount: s['amount'] as double,
                          fromName: from.name,
                          toName: to.name,
                        ),
                        child: const Text('Paid ✓'),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _showSettleUpDialog(
      BuildContext context, WidgetRef ref, String memberId, double amount) {
    // Find who this member owes (first creditor from settlements)
    final creditor = settlements.firstWhereOrNull(
        (s) => s['from'] == memberId);
    if (creditor != null) {
      _recordSettlement(
        context,
        ref,
        fromMemberId: memberId,
        toMemberId: creditor['to'] as String,
        amount: amount,
        fromName: members
                .firstWhereOrNull((m) => m.id == memberId)
                ?.name ??
            'Member',
        toName: members
                .firstWhereOrNull((m) => m.id == creditor['to'])
                ?.name ??
            'Member',
      );
    }
  }

  void _recordSettlement(
    BuildContext context,
    WidgetRef ref, {
    required String fromMemberId,
    required String toMemberId,
    required double amount,
    required String fromName,
    required String toName,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.check_circle_outline, color: Color(0xFF00897B)),
          SizedBox(width: 8),
          Text('Confirm Payment'),
        ]),
        content: RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style.copyWith(fontSize: 15),
            children: [
              TextSpan(
                  text: fromName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: ' paid '),
              TextSpan(
                  text: toName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: ' '),
              TextSpan(
                  text: Helpers.formatCurrency(amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00897B))),
              const TextSpan(text: '?\n\nThis will zero out their balance.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.of(ctx).pop();

              // Save settlement as an expense:
              // fromMember paid the amount, split only among toMember
              // This cancels out their debt in the balance calculation
              final settlement = ExpenseModel(
                id: const Uuid().v4(),
                groupId: groupId,
                description: '💸 Settlement: $fromName → $toName',
                amount: amount,
                paidByMemberId: fromMemberId,
                splitAmongMemberIds: [toMemberId],
                splitType: 'equal',
                date: DateTime.now(),
                category: 'other',
              );

              await ref
                  .read(expenseProvider.notifier)
                  .addExpense(settlement);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '✅ $fromName paid $toName ${Helpers.formatCurrency(amount)}'),
                    backgroundColor: const Color(0xFF00897B),
                  ),
                );
              }
            },
            child: const Text('Mark as Paid'),
          ),
        ],
      ),
    );
  }
}

class _ExpensesTab extends ConsumerStatefulWidget {
  final String groupId;

  const _ExpensesTab({required this.groupId});

  @override
  ConsumerState<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends ConsumerState<_ExpensesTab> {
  String? _filterCategory;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var expenses = ref.watch(expensesByGroupProvider(widget.groupId));
    final members = ref.watch(membersByGroupProvider(widget.groupId));

    if (_filterCategory != null) {
      expenses = expenses.where((e) => e.category == _filterCategory).toList();
    }
    if (_searchController.text.isNotEmpty) {
      final q = _searchController.text.toLowerCase();
      expenses = expenses
          .where((e) => e.description.toLowerCase().contains(q))
          .toList();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search expenses...',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _filterChip('All', null),
              ...AppConstants.categories.map((cat) => _filterChip(cat, cat)),
            ],
          ),
        ),
        Expanded(
          child: expenses.isEmpty
              ? EmptyState(
                  icon: Icons.receipt_long,
                  title: 'No Expenses',
                  subtitle: 'Add an expense to get started',
                  actionLabel: 'Add Expense',
                  onAction: () => context.push(
                      '/group/${widget.groupId}/add-expense'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: expenses.length,
                  itemBuilder: (ctx, i) {
                    final expense = expenses[i];
                    return ExpenseCard(
                      expense: expense,
                      members: members,
                      onEdit: () => context.push(
                              '/group/${widget.groupId}/add-expense',
                              extra: expense),
                      onDelete: () {
                        final deleted = expense;
                        ref
                            .read(expenseProvider.notifier)
                            .deleteExpense(expense.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Expense deleted'),
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () {
                                ref
                                    .read(expenseProvider.notifier)
                                    .addExpense(deleted);
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String? category) {
    final selected = _filterCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) =>
            setState(() => _filterCategory = category),
        selectedColor: const Color(0xFF00897B),
        labelStyle: TextStyle(
          color: selected ? Colors.white : null,
          fontSize: 12,
        ),
      ),
    );
  }
}



