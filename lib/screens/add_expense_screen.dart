import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../models/expense_model.dart';
import '../models/member_model.dart';
import '../providers/expense_provider.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';
import '../widgets/member_avatar.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String groupId;
  final ExpenseModel? existingExpense;

  const AddExpenseScreen({
    super.key,
    required this.groupId,
    this.existingExpense,
  });

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  final _uuid = const Uuid();

  String _selectedCategory = 'other';
  String? _paidByMemberId;
  List<String> _splitAmongIds = [];
  String _splitType = AppConstants.equalSplit;
  DateTime _selectedDate = DateTime.now();
  final Map<String, TextEditingController> _customControllers = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingExpense != null) {
      final e = widget.existingExpense!;
      _amountController.text = e.amount.toString();
      _descController.text = e.description;
      _selectedCategory = e.category;
      _paidByMemberId = e.paidByMemberId;
      _splitAmongIds = List.from(e.splitAmongMemberIds);
      _splitType = e.splitType;
      _selectedDate = e.date;
      e.customSplitAmounts.forEach((k, v) {
        _customControllers[k] = TextEditingController(text: v.toString());
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    for (final c in _customControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // unused - members loaded via ref.watch in build()

  void _toggleSplitMember(String memberId) {
    setState(() {
      if (_splitAmongIds.contains(memberId)) {
        _splitAmongIds.remove(memberId);
        _customControllers.remove(memberId);
      } else {
        _splitAmongIds.add(memberId);
        _customControllers[memberId] = TextEditingController();
      }
    });
  }

  Map<String, double> get _previewSplit {
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (_splitAmongIds.isEmpty) return {};

    if (_splitType == AppConstants.equalSplit) {
      final share = amount / _splitAmongIds.length;
      return {for (final id in _splitAmongIds) id: share};
    } else if (_splitType == AppConstants.customSplit) {
      return {
        for (final id in _splitAmongIds)
          id: double.tryParse(_customControllers[id]?.text ?? '') ?? 0,
      };
    } else {
      // percentage
      return {
        for (final id in _splitAmongIds)
          id: amount *
              (double.tryParse(_customControllers[id]?.text ?? '') ?? 0) /
              100,
      };
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_paidByMemberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select who paid')),
      );
      return;
    }
    if (_splitAmongIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select members to split among')),
      );
      return;
    }

    final amount = double.parse(_amountController.text);

    // Validate custom split amounts
    if (_splitType == AppConstants.customSplit) {
      final sumCustom = _splitAmongIds.fold(
          0.0,
          (s, id) =>
              s + (double.tryParse(_customControllers[id]?.text ?? '') ?? 0));
      if ((sumCustom - amount).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Custom amounts total ${Helpers.formatCurrency(sumCustom)} must equal expense amount ${Helpers.formatCurrency(amount)}'),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 4),
        ));
        return;
      }
    }

    // Validate percentage split
    if (_splitType == AppConstants.percentageSplit) {
      final totalPct = _splitAmongIds.fold(
          0.0,
          (s, id) =>
              s + (double.tryParse(_customControllers[id]?.text ?? '') ?? 0));
      if ((totalPct - 100).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Percentages must add up to 100% (current: ${totalPct.toStringAsFixed(1)}%)'),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 4),
        ));
        return;
      }
    }

    setState(() => _isLoading = true);
    final customAmounts = <String, double>{};
    if (_splitType != AppConstants.equalSplit) {
      for (final id in _splitAmongIds) {
        customAmounts[id] =
            double.tryParse(_customControllers[id]?.text ?? '') ?? 0;
      }
    }

    final expense = ExpenseModel(
      id: widget.existingExpense?.id ?? _uuid.v4(),
      groupId: widget.groupId,
      description: _descController.text.trim(),
      amount: amount,
      paidByMemberId: _paidByMemberId!,
      splitAmongMemberIds: _splitAmongIds,
      customSplitAmounts: customAmounts,
      splitType: _splitType,
      date: _selectedDate,
      category: _selectedCategory,
    );

    if (widget.existingExpense != null) {
      await ref.read(expenseProvider.notifier).updateExpense(expense);
    } else {
      await ref.read(expenseProvider.notifier).addExpense(expense);
    }

    setState(() => _isLoading = false);

    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = ref.watch(membersByGroupProvider(widget.groupId));

    // Initialize split among to all members if new expense
    if (_splitAmongIds.isEmpty && widget.existingExpense == null && members.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _splitAmongIds = members.map((m) => m.id).toList();
          for (final m in members) {
            _customControllers[m.id] = TextEditingController();
          }
        });
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingExpense != null ? 'Edit Expense' : 'Add Expense'),
        leading: IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
          icon: const Icon(Icons.close),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _save,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Amount
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.currency_rupee),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter amount';
                if (double.tryParse(v) == null || double.parse(v) <= 0) {
                  return 'Enter valid amount';
                }
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(Icons.notes),
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter description' : null,
            ),
            const SizedBox(height: 16),

            // Category
            Text('Category', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppConstants.categories.map((cat) {
                final selected = _selectedCategory == cat;
                final color = AppConstants.categoryColor(cat);
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppConstants.categoryIcon(cat),
                          size: 14,
                          color: selected ? Colors.white : color),
                      const SizedBox(width: 4),
                      Text(cat,
                          style: TextStyle(
                              color: selected ? Colors.white : color)),
                    ],
                  ),
                  selected: selected,
                  onSelected: (_) =>
                      setState(() => _selectedCategory = cat),
                  selectedColor: color,
                  backgroundColor: color.withAlpha(20),
                  side: BorderSide.none,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Date'),
              subtitle: Text(Helpers.formatDate(_selectedDate)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) setState(() => _selectedDate = date);
              },
            ),
            const Divider(),

            // Paid By
            Text('Paid By', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: members.map((member) {
                final selected = _paidByMemberId == member.id;
                final color = AppConstants.colorFromHex(member.colorHex);
                return GestureDetector(
                  onTap: () =>
                      setState(() => _paidByMemberId = member.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? color : color.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                      border: selected
                          ? null
                          : Border.all(color: color.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MemberAvatar(
                          name: member.name,
                          colorHex: member.colorHex,
                          size: 22,
                          fontSize: 9,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          member.name,
                          style: TextStyle(
                            color: selected ? Colors.white : color,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Split Among
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Split Among', style: theme.textTheme.titleSmall),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_splitAmongIds.length == members.length) {
                        _splitAmongIds.clear();
                        _customControllers.clear();
                      } else {
                        _splitAmongIds = members.map((m) => m.id).toList();
                        for (final m in members) {
                          _customControllers[m.id] ??=
                              TextEditingController();
                        }
                      }
                    });
                  },
                  child: Text(
                    _splitAmongIds.length == members.length
                        ? 'Deselect All'
                        : 'Select All',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: members.map((member) {
                final selected = _splitAmongIds.contains(member.id);
                final color = AppConstants.colorFromHex(member.colorHex);
                return GestureDetector(
                  onTap: () => _toggleSplitMember(member.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? color.withAlpha(30) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: selected ? color : Colors.grey[300]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MemberAvatar(
                          name: member.name,
                          colorHex: member.colorHex,
                          size: 22,
                          fontSize: 9,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          member.name,
                          style: TextStyle(
                            color: selected ? color : Colors.grey[600],
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.check, size: 14, color: color),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Split Type
            Text('Split Type', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                AppConstants.equalSplit,
                AppConstants.customSplit,
                AppConstants.percentageSplit,
              ].map((type) {
                final selected = _splitType == type;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _splitType = type),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF00897B)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          _splitTypeLabel(type),
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.grey[700],
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            // Custom split inputs
            if (_splitType != AppConstants.equalSplit &&
                _splitAmongIds.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _splitType == AppConstants.percentageSplit
                    ? 'Percentage per member'
                    : 'Amount per member',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ...members
                  .where((m) => _splitAmongIds.contains(m.id))
                  .map((member) {
                _customControllers[member.id] ??= TextEditingController();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      MemberAvatar(
                        name: member.name,
                        colorHex: member.colorHex,
                        size: 32,
                        fontSize: 12,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _customControllers[member.id],
                          decoration: InputDecoration(
                            labelText: member.name,
                            prefixText: _splitType ==
                                    AppConstants.percentageSplit
                                ? ''
                                : '₹ ',
                            suffixText: _splitType ==
                                    AppConstants.percentageSplit
                                ? '%'
                                : null,
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],

            // Preview
            if (_amountController.text.isNotEmpty &&
                _splitAmongIds.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text('Split Preview', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ..._previewSplit.entries.map((entry) {
                final member = members.firstWhereOrNull((m) => m.id == entry.key)
                    ?? MemberModel(
                        id: '', name: 'Unknown', colorHex: 'FF000000', createdAt: DateTime.now());
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      MemberAvatar(
                        name: member.name,
                        colorHex: member.colorHex,
                        size: 28,
                        fontSize: 10,
                      ),
                      const SizedBox(width: 8),
                      Text(member.name),
                      const Spacer(),
                      Text(
                        Helpers.formatCurrency(entry.value),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }),
              // Mismatch warning
              Builder(builder: (context) {
                final totalAmount = double.tryParse(_amountController.text) ?? 0;
                if (_splitType == AppConstants.customSplit) {
                  final sumCustom = _previewSplit.values.fold(0.0, (s, v) => s + v);
                  final diff = (sumCustom - totalAmount).abs();
                  if (diff > 0.01) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.red.shade600, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Total entered: ${Helpers.formatCurrency(sumCustom)} — must equal ${Helpers.formatCurrency(totalAmount)}',
                                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                } else if (_splitType == AppConstants.percentageSplit) {
                  final totalPct = _splitAmongIds.fold(
                      0.0,
                      (s, id) =>
                          s + (double.tryParse(_customControllers[id]?.text ?? '') ?? 0));
                  if ((totalPct - 100).abs() > 0.01) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.red.shade600, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Percentages total: ${totalPct.toStringAsFixed(1)}% — must equal 100%',
                                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                }
                return const SizedBox.shrink();
              }),
            ],

            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _save,
              child: Text(widget.existingExpense != null
                  ? 'Update Expense'
                  : 'Add Expense'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _splitTypeLabel(String type) {
    switch (type) {
      case AppConstants.equalSplit:
        return 'Equal';
      case AppConstants.customSplit:
        return 'Custom';
      case AppConstants.percentageSplit:
        return 'Percentage';
      default:
        return type;
    }
  }
}





