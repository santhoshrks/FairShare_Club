import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/expense_provider.dart';
import '../providers/group_provider.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';
import '../widgets/empty_state.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String? _filterGroupId;
  String? _filterCategory;
  final _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var expenses = ref.watch(expenseProvider);
    final groups = ref.watch(activeGroupsProvider);
    final members = ref.watch(memberProvider);
    final theme = Theme.of(context);

    // Apply filters
    if (_filterGroupId != null) {
      expenses =
          expenses.where((e) => e.groupId == _filterGroupId).toList();
    }
    if (_filterCategory != null) {
      expenses = expenses
          .where((e) => e.category == _filterCategory)
          .toList();
    }
    if (_searchController.text.isNotEmpty) {
      final q = _searchController.text.toLowerCase();
      expenses = expenses
          .where((e) => e.description.toLowerCase().contains(q))
          .toList();
    }
    if (_startDate != null) {
      expenses = expenses
          .where((e) => !e.date.isBefore(_startDate!))
          .toList();
    }
    if (_endDate != null) {
      expenses = expenses
          .where((e) => !e.date.isAfter(_endDate!))
          .toList();
    }

    // Sort by date
    expenses.sort((a, b) => b.date.compareTo(a.date));

    final totalShown = expenses.fold(0.0, (s, e) => s + e.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense History'),
        actions: [
          IconButton(
            onPressed: _showFilterOptions,
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search
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

          // Category filter
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip('All', null, _filterCategory),
                ...AppConstants.categories
                    .map((c) => _chip(c, c, _filterCategory)),
              ],
            ),
          ),

          // Active filters + total
          if (_filterGroupId != null ||
              _startDate != null ||
              _endDate != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  if (_filterGroupId != null)
                    Chip(
                      label: Text(groups
                          .firstWhere(
                            (g) => g.id == _filterGroupId,
                            orElse: () => groups.first,
                          )
                          .name),
                      onDeleted: () =>
                          setState(() => _filterGroupId = null),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('Clear Filters'),
                  ),
                ],
              ),
            ),

          // Total
          Container(
            color: const Color(0xFF00897B).withAlpha(15),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text('${expenses.length} expenses',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey[600])),
                const Spacer(),
                Text('Total: ${Helpers.formatCurrency(totalShown)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00897B))),
              ],
            ),
          ),

          // Expense list
          Expanded(
            child: expenses.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long,
                    title: 'No Expenses Found',
                    subtitle: 'Try adjusting your filters',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: expenses.length,
                    itemBuilder: (ctx, i) {
                      final expense = expenses[i];
                      final group = groups.firstWhereOrNull(
                        (g) => g.id == expense.groupId,
                      );
                      final payer = members.firstWhereOrNull(
                        (m) => m.id == expense.paidByMemberId,
                      );
                      if (group == null || payer == null) return const SizedBox.shrink();
                      final catColor = AppConstants.categoryColor(expense.category);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () =>
                              context.push('/group/${expense.groupId}'),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: catColor.withAlpha(25),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                      AppConstants.categoryIcon(
                                          expense.category),
                                      color: catColor,
                                      size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(expense.description,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w500),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      Text(
                                        '${group.name} • ${payer.name} • ${Helpers.formatDate(expense.date)}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: Colors.grey[600]),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  Helpers.formatCurrency(expense.amount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF00897B)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String? cat, String? current) {
    final selected = current == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => setState(() => _filterCategory = cat),
        selectedColor: const Color(0xFF00897B).withAlpha(40),
        checkmarkColor: const Color(0xFF00897B),
      ),
    );
  }

  void _showFilterOptions() {
    final groups = ref.read(activeGroupsProvider);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filter by Group',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('All Groups'),
                  selected: _filterGroupId == null,
                  onSelected: (_) {
                    setState(() => _filterGroupId = null);
                    Navigator.of(ctx).pop();
                  },
                ),
                ...groups.map((g) => FilterChip(
                      label: Text(g.name),
                      selected: _filterGroupId == g.id,
                      onSelected: (_) {
                        setState(() => _filterGroupId = g.id);
                        Navigator.of(ctx).pop();
                      },
                    )),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _startDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _startDate = date);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      }
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_startDate != null
                        ? Helpers.formatDateShort(_startDate!)
                        : 'From Date'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _endDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _endDate = date);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      }
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_endDate != null
                        ? Helpers.formatDateShort(_endDate!)
                        : 'To Date'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _filterGroupId = null;
      _filterCategory = null;
      _startDate = null;
      _endDate = null;
      _searchController.clear();
    });
  }
}

