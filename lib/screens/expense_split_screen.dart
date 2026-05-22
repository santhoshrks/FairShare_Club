import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/settlement_model.dart';
import '../models/member_model.dart';
import '../providers/expense_provider.dart';
import '../providers/settlement_provider.dart';
import '../utils/helpers.dart';
import '../utils/constants.dart';
import '../widgets/balance_card.dart';
import '../widgets/expense_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/member_avatar.dart';

// ---------------------------------------------------------------------------
// Main screen — 3 tabs: Balances | Payments | Expenses
// ---------------------------------------------------------------------------
class ExpenseSplitScreen extends ConsumerWidget {
  final String groupId;
  const ExpenseSplitScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 3,
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
                Tab(text: 'Payments'),
                Tab(text: 'Expenses'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _BalancesTab(groupId: groupId),
                _PaymentsTab(groupId: groupId),
                _ExpensesTab(groupId: groupId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared settle-up dialog — saves SettlementModel, does NOT create an expense
// ---------------------------------------------------------------------------
void _showSettleUpDialog(
  BuildContext context,
  WidgetRef ref, {
  required String groupId,
  required MemberModel fromMember,
  required MemberModel toMember,
  required double amount,
}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.check_circle_outline, color: Color(0xFF00897B)),
        SizedBox(width: 8),
        Text('Confirm Settlement'),
      ]),
      content: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style.copyWith(fontSize: 15),
          children: [
            TextSpan(
                text: fromMember.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const TextSpan(text: ' paid '),
            TextSpan(
                text: toMember.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const TextSpan(text: ' '),
            TextSpan(
                text: Helpers.formatCurrency(amount),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF00897B))),
            const TextSpan(text: '\n\nThis marks the balance as settled.'),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00897B),
              foregroundColor: Colors.white),
          onPressed: () async {
            Navigator.of(ctx).pop();
            await ref.read(settlementProvider.notifier).addSettlement(
                  SettlementModel(
                    id: const Uuid().v4(),
                    groupId: groupId,
                    fromMemberId: fromMember.id,
                    toMemberId: toMember.id,
                    amount: amount,
                    date: DateTime.now(),
                  ),
                );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    '✅ ${fromMember.name} settled with ${toMember.name} — ${Helpers.formatCurrency(amount)}'),
                backgroundColor: const Color(0xFF00897B),
              ));
            }
          },
          child: const Text('Mark as Paid'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Tab 1 — Balances (with month selector)
// ---------------------------------------------------------------------------
class _BalancesTab extends ConsumerStatefulWidget {
  final String groupId;
  const _BalancesTab({required this.groupId});

  @override
  ConsumerState<_BalancesTab> createState() => _BalancesTabState();
}

class _BalancesTabState extends ConsumerState<_BalancesTab> {
  static final _kMinMonth = DateTime(2026, 1);

  DateTime get _maxMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  DateTime _selectedMonth = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }();

  String _formatMonth(DateTime dt) => DateFormat('MMMM yyyy').format(dt);

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersByGroupProvider(widget.groupId));
    final currentUserId = ref.watch(currentUserMemberIdProvider);

    final p = GroupMonthParam(
        groupId: widget.groupId,
        year: _selectedMonth.year,
        month: _selectedMonth.month);

    final monthExpenses = ref.watch(expensesByGroupMonthProvider(p));
    final totalSpent =
        monthExpenses.fold(0.0, (s, e) => s + e.amount);

    // Compute pairwise debts for the selected month only
    final settlements = ref.watch(settlementsByGroupProvider(widget.groupId));
    final monthBalances =
        ref.watch(balancesByGroupMonthProvider(p));
    final monthPairwiseDebts =
        Helpers.calculatePairwiseDebts(monthExpenses, settlements);

    // Build current-user debts for selected month
    final youOwe = <({String memberId, double amount})>[];
    final owedToYou = <({String memberId, double amount})>[];
    if (currentUserId != null) {
      final myDebts = monthPairwiseDebts[currentUserId] ?? {};
      myDebts.forEach((creditorId, amount) {
        if (amount > 0.01) youOwe.add((memberId: creditorId, amount: amount));
      });
      monthPairwiseDebts.forEach((debtorId, creditors) {
        if (debtorId == currentUserId) return;
        final amount = creditors[currentUserId] ?? 0;
        if (amount > 0.01) {
          owedToYou.add((memberId: debtorId, amount: amount));
        }
      });
    }

    final youOweTotal = youOwe.fold(0.0, (s, d) => s + d.amount);
    final owedTotal = owedToYou.fold(0.0, (s, d) => s + d.amount);
    final net = owedTotal - youOweTotal;

    if (members.isEmpty) {
      return const EmptyState(
        icon: Icons.people_alt_outlined,
        title: 'No Members',
        subtitle: 'Add members to track balances',
      );
    }

    final me = members.firstWhereOrNull((m) => m.id == currentUserId);

    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(expensesByGroupProvider(widget.groupId)),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Month selector
          _MonthSelectorSimple(
            selectedMonth: _selectedMonth,
            minMonth: _kMinMonth,
            maxMonth: _maxMonth,
            onChanged: (m) => setState(() => _selectedMonth = m),
          ),
          const SizedBox(height: 12),

          // ── Add Expense button ─────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () =>
                  context.push('/group/${widget.groupId}/add-expense'),
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Add Expense'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // No records for this month
          if (monthExpenses.isEmpty) ...[
            const EmptyState(
              icon: Icons.receipt_long,
              title: 'Nothing is here',
              subtitle: 'No expenses recorded for this month.',
            ),
          ] else ...[
            // Summary
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
                          Text(
                            'Total Spend — ${_formatMonth(_selectedMonth)}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
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
                      child: const Icon(Icons.receipt_long,
                          color: Colors.white, size: 30),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Your balance
            if (me != null) ...[
              _YourBalanceCard(
                  member: me,
                  net: net,
                  youOweTotal: youOweTotal,
                  owedToYouTotal: owedTotal),
              const SizedBox(height: 16),
            ],

            // You owe
            if (youOwe.isNotEmpty) ...[
              _SectionHeader(
                  title: 'You Owe', color: Colors.red.shade700),
              const SizedBox(height: 8),
              ...youOwe.map((d) {
                final m =
                    members.firstWhereOrNull((x) => x.id == d.memberId);
                if (m == null || me == null) return const SizedBox.shrink();
                return _PersonDebtTile(
                  otherMember: m,
                  amount: d.amount,
                  isYouOwe: true,
                  onSettle: () => _showSettleUpDialog(context, ref,
                      groupId: widget.groupId,
                      fromMember: me,
                      toMember: m,
                      amount: d.amount),
                );
              }),
              const SizedBox(height: 16),
            ],

            // Owed to you
            if (owedToYou.isNotEmpty) ...[
              _SectionHeader(
                  title: 'Owed to You', color: Colors.green.shade700),
              const SizedBox(height: 8),
              ...owedToYou.map((d) {
                final m =
                    members.firstWhereOrNull((x) => x.id == d.memberId);
                if (m == null || me == null) return const SizedBox.shrink();
                return _PersonDebtTile(
                  otherMember: m,
                  amount: d.amount,
                  isYouOwe: false,
                  onSettle: () => _showSettleUpDialog(context, ref,
                      groupId: widget.groupId,
                      fromMember: m,
                      toMember: me,
                      amount: d.amount),
                );
              }),
              const SizedBox(height: 16),
            ],

            // All settled banner (for selected month)
            if (youOwe.isEmpty && owedToYou.isEmpty && totalSpent > 0) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Colors.green.shade600, size: 48),
                    const SizedBox(height: 8),
                    Text('All settled up!',
                        style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                        'No outstanding balances for ${_formatMonth(_selectedMonth)}.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.green.shade600, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // All member balances for selected month
            _SectionHeader(
                title: 'All Member Balances',
                color: Colors.grey.shade700),
            const SizedBox(height: 8),
            ...members.map((member) {
              final bal = monthBalances[member.id] ?? 0.0;
              return BalanceCard(member: member, balance: bal);
            }),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — Payments (all pairwise one-on-one + settlement history)
// ---------------------------------------------------------------------------
class _PaymentsTab extends ConsumerWidget {
  final String groupId;
  const _PaymentsTab({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final members = ref.watch(membersByGroupProvider(groupId));
    final pairwiseDebts = ref.watch(pairwiseDebtsProvider(groupId));
    final currentUserId = ref.watch(currentUserMemberIdProvider);
    final history = ref.watch(settlementsByGroupProvider(groupId));

    final debtList = <({String debtorId, String creditorId, double amount})>[];
    pairwiseDebts.forEach((debtorId, creditors) {
      creditors.forEach((creditorId, amount) {
        if (amount > 0.01) {
          debtList
              .add((debtorId: debtorId, creditorId: creditorId, amount: amount));
        }
      });
    });
    debtList.sort((a, b) {
      final aMe = a.debtorId == currentUserId || a.creditorId == currentUserId;
      final bMe = b.debtorId == currentUserId || b.creditorId == currentUserId;
      if (aMe && !bMe) return -1;
      if (!aMe && bMe) return 1;
      return b.amount.compareTo(a.amount);
    });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (debtList.isEmpty) ...[
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.handshake_rounded,
                    color: Colors.green.shade600, size: 56),
                const SizedBox(height: 12),
                Text('All Settled!',
                    style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const SizedBox(height: 6),
                Text('Everyone in this group is even.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.green.shade600, fontSize: 13)),
              ],
            ),
          ),
        ] else ...[
          _SectionHeader(
              title: 'Outstanding Payments (${debtList.length})',
              color: Colors.orange.shade800),
          const SizedBox(height: 4),
          Text('Tap "Paid" after the payment is made.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
          const SizedBox(height: 12),
          ...debtList.map((d) {
            final debtor =
                members.firstWhereOrNull((m) => m.id == d.debtorId);
            final creditor =
                members.firstWhereOrNull((m) => m.id == d.creditorId);
            if (debtor == null || creditor == null) return const SizedBox.shrink();
            return _PairwiseDebtCard(
              debtor: debtor,
              creditor: creditor,
              amount: d.amount,
              highlightCurrentUser: d.debtorId == currentUserId ||
                  d.creditorId == currentUserId,
              currentUserId: currentUserId,
              onSettle: () => _showSettleUpDialog(context, ref,
                  groupId: groupId,
                  fromMember: debtor,
                  toMember: creditor,
                  amount: d.amount),
            );
          }),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionHeader(
              title: 'Settlement History (${history.length})',
              color: Colors.blueGrey.shade600),
          const SizedBox(height: 8),
          ...history.map((s) {
            final from = members.firstWhereOrNull((m) => m.id == s.fromMemberId);
            final to = members.firstWhereOrNull((m) => m.id == s.toMemberId);
            return _SettlementHistoryTile(
              fromName: from?.name ?? 'Unknown',
              toName: to?.name ?? 'Unknown',
              amount: s.amount,
              date: s.date,
            );
          }),
        ],
        const SizedBox(height: 80),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3 — Expenses list
// ---------------------------------------------------------------------------
class _ExpensesTab extends ConsumerStatefulWidget {
  final String groupId;
  const _ExpensesTab({required this.groupId});

  @override
  ConsumerState<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends ConsumerState<_ExpensesTab> {
  String? _filterCategory;
  bool _showOverall = false;
  final _searchController = TextEditingController();

  static final _kMinMonth = DateTime(2026, 1);
  DateTime _selectedMonth = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }();

  DateTime get _maxMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersByGroupProvider(widget.groupId));

    List expenses;
    if (_showOverall) {
      expenses = ref.watch(expensesByGroupProvider(widget.groupId));
    } else {
      final p = GroupMonthParam(
          groupId: widget.groupId,
          year: _selectedMonth.year,
          month: _selectedMonth.month);
      expenses = ref.watch(expensesByGroupMonthProvider(p));
    }

    if (_filterCategory != null) {
      expenses = expenses.where((e) => e.category == _filterCategory).toList();
    }
    if (_searchController.text.isNotEmpty) {
      final q = _searchController.text.toLowerCase();
      expenses =
          expenses.where((e) => e.description.toLowerCase().contains(q)).toList();
    }

    return Column(
      children: [
        // Month selector + Overall toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _showOverall
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00897B).withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Overall — All Time Expenses',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF00897B),
                              fontWeight: FontWeight.w500),
                        ),
                      )
                    : _MonthSelectorSimple(
                        selectedMonth: _selectedMonth,
                        minMonth: _kMinMonth,
                        maxMonth: _maxMonth,
                        onChanged: (m) =>
                            setState(() => _selectedMonth = m),
                      ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () =>
                    setState(() => _showOverall = !_showOverall),
                child: Text(
                  _showOverall ? 'Monthly' : 'Overall',
                  style: const TextStyle(color: Color(0xFF00897B)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
              _chip('All', null),
              ...AppConstants.categories.map((cat) => _chip(cat, cat)),
            ],
          ),
        ),
        Expanded(
          child: expenses.isEmpty
              ? EmptyState(
                  icon: Icons.receipt_long,
                  title: 'Nothing is here',
                  subtitle: _showOverall
                      ? 'No expenses recorded yet'
                      : 'No expenses for this month',
                  actionLabel: 'Add Expense',
                  onAction: () =>
                      context.push('/group/${widget.groupId}/add-expense'),
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
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: const Text('Expense deleted'),
                          action: SnackBarAction(
                            label: 'Undo',
                            onPressed: () => ref
                                .read(expenseProvider.notifier)
                                .addExpense(deleted),
                          ),
                        ));
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _chip(String label, String? category) {
    final selected = _filterCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filterCategory = category),
        selectedColor: const Color(0xFF00897B),
        labelStyle:
            TextStyle(color: selected ? Colors.white : null, fontSize: 12),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable small widgets
// ---------------------------------------------------------------------------

/// Compact month navigator used in expense-split tabs.
class _MonthSelectorSimple extends StatelessWidget {
  final DateTime selectedMonth;
  final DateTime minMonth;
  final DateTime maxMonth;
  final ValueChanged<DateTime> onChanged;

  const _MonthSelectorSimple({
    required this.selectedMonth,
    required this.minMonth,
    required this.maxMonth,
    required this.onChanged,
  });

  String _fmt(DateTime dt) => DateFormat('MMM yyyy').format(dt);

  @override
  Widget build(BuildContext context) {
    final canPrev = selectedMonth.isAfter(minMonth) ||
        (selectedMonth.year == minMonth.year &&
            selectedMonth.month > minMonth.month);
    final isAtMax = selectedMonth.year == maxMonth.year &&
        selectedMonth.month == maxMonth.month;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: canPrev
              ? () => onChanged(DateTime(
                  selectedMonth.year, selectedMonth.month - 1))
              : null,
          color: canPrev ? const Color(0xFF00897B) : Colors.grey[300],
        ),
        Text(
          _fmt(selectedMonth),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: isAtMax
              ? null
              : () => onChanged(DateTime(
                  selectedMonth.year, selectedMonth.month + 1)),
          color: isAtMax ? Colors.grey[300] : const Color(0xFF00897B),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) => Text(title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.bold, color: color));
}

class _YourBalanceCard extends StatelessWidget {
  final MemberModel member;
  final double net, youOweTotal, owedToYouTotal;
  const _YourBalanceCard(
      {required this.member,
      required this.net,
      required this.youOweTotal,
      required this.owedToYouTotal});

  @override
  Widget build(BuildContext context) {
    final settled = net.abs() < 0.01;
    final positive = net > 0.01;
    final bg = settled
        ? Colors.green.shade600
        : positive
            ? Colors.green.shade700
            : Colors.red.shade700;

    return Card(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MemberAvatar(
                    name: member.name, colorHex: member.colorHex, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your Balance',
                          style: TextStyle(
                              color: Colors.white.withAlpha(180), fontSize: 12)),
                      Text(
                        settled
                            ? 'All settled up!'
                            : positive
                                ? '+${Helpers.formatCurrency(net)} owed to you'
                                : '${Helpers.formatCurrency(net.abs())} you owe',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!settled) ...[
              const SizedBox(height: 12),
              const Divider(color: Colors.white30, height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      child: _stat('You Owe', youOweTotal, Colors.red.shade200)),
                  Container(width: 1, height: 32, color: Colors.white30),
                  Expanded(
                      child: _stat(
                          'Owed to You', owedToYouTotal, Colors.green.shade200)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, double v, Color c) => Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withAlpha(180), fontSize: 11)),
          const SizedBox(height: 2),
          Text(Helpers.formatCurrency(v),
              style:
                  TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      );
}

class _PersonDebtTile extends StatelessWidget {
  final MemberModel otherMember;
  final double amount;
  final bool isYouOwe;
  final VoidCallback onSettle;
  const _PersonDebtTile(
      {required this.otherMember,
      required this.amount,
      required this.isYouOwe,
      required this.onSettle});

  @override
  Widget build(BuildContext context) {
    final accent = isYouOwe ? Colors.red.shade600 : Colors.green.shade600;
    final bg = isYouOwe ? Colors.red.shade50 : Colors.green.shade50;
    final border = isYouOwe ? Colors.red.shade200 : Colors.green.shade200;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            MemberAvatar(
                name: otherMember.name, colorHex: otherMember.colorHex, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(otherMember.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    isYouOwe
                        ? 'You owe ${otherMember.name}'
                        : '${otherMember.name} owes you',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Helpers.formatCurrency(amount),
                    style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 4),
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(fontSize: 11),
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onSettle,
                    child: const Text('Settle Up'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PairwiseDebtCard extends StatelessWidget {
  final MemberModel debtor, creditor;
  final double amount;
  final bool highlightCurrentUser;
  final String? currentUserId;
  final VoidCallback onSettle;
  const _PairwiseDebtCard(
      {required this.debtor,
      required this.creditor,
      required this.amount,
      required this.highlightCurrentUser,
      required this.currentUserId,
      required this.onSettle});

  @override
  Widget build(BuildContext context) {
    final dLabel = debtor.id == currentUserId ? 'You' : debtor.name;
    final cLabel = creditor.id == currentUserId ? 'you' : creditor.name;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: highlightCurrentUser
            ? const BorderSide(color: Color(0xFF00897B), width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            MemberAvatar(
                name: debtor.name, colorHex: debtor.colorHex, size: 38),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                          child: Text(dLabel,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward_rounded,
                            color: Colors.orange.shade600, size: 18),
                      ),
                      Flexible(
                          child: Text(cLabel,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(Helpers.formatCurrency(amount),
                      style: const TextStyle(
                          color: Color(0xFFE53935),
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MemberAvatar(
                name: creditor.name, colorHex: creditor.colorHex, size: 38),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 12),
                backgroundColor: const Color(0xFF00897B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: onSettle,
              child: const Text('Paid'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettlementHistoryTile extends StatelessWidget {
  final String fromName, toName;
  final double amount;
  final DateTime date;
  const _SettlementHistoryTile(
      {required this.fromName,
      required this.toName,
      required this.amount,
      required this.date});

  @override
  Widget build(BuildContext context) {
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
                  color: Colors.green.withAlpha(25),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.check_circle,
                  color: Color(0xFF43A047), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                            text: fromName,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const TextSpan(text: ' paid '),
                        TextSpan(
                            text: toName,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Text(Helpers.formatDate(date),
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            Text(Helpers.formatCurrency(amount),
                style: const TextStyle(
                    color: Color(0xFF43A047),
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

