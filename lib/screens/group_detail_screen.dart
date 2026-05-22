import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/contribution_model.dart';
import '../models/group_model.dart';
import '../models/member_model.dart';
import '../models/expense_model.dart';
import '../providers/group_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/pool_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../services/invite_service.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';
import '../widgets/contacts_picker_dialog.dart';
import '../widgets/member_avatar.dart';
import '../screens/expense_split_screen.dart';
import '../screens/pool_fund_screen.dart';
import '../screens/wallet_split_screen.dart';
import '../screens/member_screen.dart';
import 'package:uuid/uuid.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() =>
      _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _currentTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(groupByIdProvider(widget.groupId));
    final members = ref.watch(membersByGroupProvider(widget.groupId));

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group')),
        body: const Center(child: Text('Group not found')),
      );
    }

    final typeColor = AppConstants.groupTypeColor(group.type);
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 160,
              pinned: true,
              backgroundColor: typeColor,
              leading: IconButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/');
                  }
                },
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) async {
                    if (value == 'add_member') {
                      // Switch to Members tab and trigger add dialog
                      _tabController.animateTo(2);
                      setState(() => _currentTab = 2);
                      await Future.delayed(
                          const Duration(milliseconds: 300));
                      if (context.mounted) {
                        _showAddMemberFromDetail(context);
                      }
                    } else if (value == 'add_from_contacts') {
                      _tabController.animateTo(2);
                      setState(() => _currentTab = 2);
                      await Future.delayed(
                          const Duration(milliseconds: 300));
                      if (context.mounted) {
                        _showAddFromContactsFromDetail(context);
                      }
                    } else if (value == 'archive') {
                        await ref
                            .read(groupProvider.notifier)
                            .archiveGroup(group.id);
                        if (context.mounted) {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/');
                          }
                        }
                    } else if (value == 'delete') {
                      _confirmDelete(context, ref, group);
                    } else if (value == 'export') {
                      context.push('/group/${group.id}/export');
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'add_member',
                        child: Row(children: [
                          Icon(Icons.person_add, size: 18),
                          SizedBox(width: 8),
                          Text('Add Member'),
                        ])),
                    const PopupMenuItem(
                        value: 'add_from_contacts',
                        child: Row(children: [
                          Icon(Icons.contacts, size: 18),
                          SizedBox(width: 8),
                          Text('Add from Contacts'),
                        ])),
                    const PopupMenuItem(
                        value: 'archive', child: Text('Archive Group')),
                    const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete Group',
                            style: TextStyle(color: Colors.red))),
                  ],
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  color: typeColor,
                  padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(AppConstants.groupTypeIcon(group.type),
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(30),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              AppConstants.groupTypeLabel(group.type),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        group.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      MemberAvatarStack(
                        members: members
                            .map((m) =>
                                (name: m.name, colorHex: m.colorHex))
                            .toList(),
                        size: 28,
                      ),
                    ],
                  ),
                ),
              ),
              bottom: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(text: 'Dashboard'),
                  Tab(text: 'Expenses'),
                  Tab(text: 'Members'),
                ],
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            // Dashboard
            _buildDashboard(group),

            // Expenses
            _ExpensesTab(groupId: widget.groupId),

            // Members
            MemberScreen(groupId: widget.groupId, embedded: true),
          ],
        ),
      ),
      floatingActionButton: () {
        // Pool Fund: no FAB at all — pool fund has its own inline action
        // buttons and members can be added via the member list's own button.
        if (group.type == AppConstants.poolFund) return null;
        // Members tab (non-pool-fund groups): Add Member FAB
        if (_currentTab == 2) {
          return FloatingActionButton.extended(
            onPressed: () => _showAddMemberFromDetail(context),
            icon: const Icon(Icons.person_add),
            label: const Text('Add Member'),
          );
        }
        // All other groups on non-Members tabs: Add Expense FAB
        return FloatingActionButton(
          onPressed: () =>
              context.push('/group/${widget.groupId}/add-expense'),
          child: const Icon(Icons.add),
        );
      }(),
    );
  }

  Widget _buildDashboard(GroupModel group) {
    switch (group.type) {
      case AppConstants.expenseSplit:
        return ExpenseSplitScreen(groupId: widget.groupId);
      case AppConstants.poolFund:
        return PoolFundScreen(groupId: widget.groupId);
      case AppConstants.walletSplit:
        return WalletSplitScreen(groupId: widget.groupId);
      default:
        return const Center(child: Text('Unknown group type'));
    }
  }

  void _showAddMemberFromDetail(BuildContext context) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedColor = AppConstants.avatarColors[0];
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.person_add, color: Color(0xFF00897B)),
            SizedBox(width: 8),
            Text('Add Member'),
          ]),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Enter name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email *',
                      hintText: 'member@example.com',
                      helperText:
                          'Required — they register with this email to see all history',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Email is required';
                      }
                      if (!v.trim().contains('@')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                        labelText: 'Phone (optional)'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Avatar Color',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AppConstants.avatarColors.map((hex) {
                      final color = AppConstants.colorFromHex(hex);
                      return GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedColor = hex),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: selectedColor == hex
                                ? Border.all(
                                    color: Colors.black, width: 2)
                                : null,
                          ),
                          child: selectedColor == hex
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 16)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.of(ctx).pop();

                final email = emailController.text.trim().toLowerCase();
                final name = nameController.text.trim();
                String memberId;
                bool needsInvite = false;

                if (email.isNotEmpty) {
                  final existing = await FirestoreService.instance
                      .getMemberByEmail(email);
                  if (existing != null) {
                    memberId = existing.id;
                  } else {
                    memberId = const Uuid().v4();
                    await FirestoreService.instance.saveMember(MemberModel(
                      id: memberId,
                      name: name,
                      email: email,
                      phone: phoneController.text.trim(),
                      colorHex: selectedColor,
                      createdAt: DateTime.now(),
                    ));
                    needsInvite = true;
                  }
                } else {
                  memberId = const Uuid().v4();
                  await FirestoreService.instance.saveMember(MemberModel(
                    id: memberId,
                    name: name,
                    email: '',
                    phone: phoneController.text.trim(),
                    colorHex: selectedColor,
                    createdAt: DateTime.now(),
                  ));
                }

                // Save to contacts
                await FirestoreService.instance.saveUserContact(MemberModel(
                  id: memberId,
                  name: name,
                  email: email,
                  phone: phoneController.text.trim(),
                  colorHex: selectedColor,
                  createdAt: DateTime.now(),
                ));

                final group =
                    ref.read(groupByIdProvider(widget.groupId));
                if (group != null &&
                    !group.memberIds.contains(memberId)) {
                  final updatedEmails = email.isNotEmpty &&
                          !group.memberEmails.contains(email)
                      ? [...group.memberEmails, email]
                      : group.memberEmails;

                  GroupModel updatedGroup = group.copyWith(
                    memberIds: [...group.memberIds, memberId],
                    memberEmails: updatedEmails,
                  );

                  if (group.type == AppConstants.poolFund) {
                    final now = DateTime.now();
                    final monthKey =
                        '${now.year}-${now.month.toString().padLeft(2, '0')}';
                    if (group.poolContributionClosedMonths
                        .contains(monthKey)) {
                      final newClosed = List<String>.from(
                          group.poolContributionClosedMonths)
                        ..remove(monthKey);
                      updatedGroup = updatedGroup.copyWith(
                          poolContributionClosedMonths: newClosed);
                    }
                  }

                  await ref
                      .read(groupProvider.notifier)
                      .updateGroup(updatedGroup);
                }

                if (needsInvite && context.mounted) {
                  final currentUser = ref.read(currentUserProvider);
                  final myProfile = await FirestoreService.instance
                      .getOrCreateCurrentUserProfile(
                    name: currentUser?.email ?? 'Someone',
                    colorHex: AppConstants.avatarColors[0],
                  );
                  await InviteService.instance.shareInvite(
                    toEmail: email,
                    toName: name,
                    groupName: group?.name ?? 'the group',
                    inviterName: myProfile.name,
                  );
                }

                // Show pool fund new member contribution prompt
                if (context.mounted &&
                    group?.type == AppConstants.poolFund) {
                  await _showPoolNewMemberPromptDetail(
                      context, name, memberId);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  /// Pool fund contribution prompt — offers to add the same amount as existing members.
  Future<void> _showPoolNewMemberPromptDetail(
      BuildContext context, String memberName, String memberId) async {
    final now = DateTime.now();
    final allContribs = ref
        .read(contributionsByGroupProvider(widget.groupId))
        .where((c) =>
            c.date.year == now.year &&
            c.date.month == now.month &&
            c.memberId != memberId)
        .toList();

    double typicalAmount = 0;
    if (allContribs.isNotEmpty) {
      final Map<String, double> memberTotals = {};
      for (final c in allContribs) {
        memberTotals[c.memberId] = (memberTotals[c.memberId] ?? 0) + c.amount;
      }
      if (memberTotals.isNotEmpty) {
        final freq = <double, int>{};
        for (final v in memberTotals.values) {
          freq[v] = (freq[v] ?? 0) + 1;
        }
        typicalAmount =
            freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }
    }

    await showDialog(
      context: context,
      builder: (alertCtx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.person_add, color: Color(0xFF00897B)),
          SizedBox(width: 8),
          Text('Member Added'),
        ]),
        content: typicalAmount > 0
            ? Text(
                '$memberName has been added to the pool fund.\n\n'
                'Other members contributed ${Helpers.formatCurrency(typicalAmount)} this month.\n\n'
                'Add the same amount for $memberName?',
              )
            : Text(
                '$memberName has been added to the pool fund.\n\n'
                'Add a contribution for $memberName when ready.\n\n'
                'Click "Close Contribution" to lock contributions for this month.',
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(alertCtx).pop(),
            child: Text(typicalAmount > 0 ? 'Skip' : 'Got it'),
          ),
          if (typicalAmount > 0)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.of(alertCtx).pop();
                await FirestoreService.instance.saveContribution(
                  ContributionModel(
                    id: const Uuid().v4(),
                    groupId: widget.groupId,
                    memberId: memberId,
                    amount: typicalAmount,
                    date: DateTime.now(),
                    note: 'Initial contribution',
                  ),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        '✅ ${Helpers.formatCurrency(typicalAmount)} added for $memberName'),
                    backgroundColor: const Color(0xFF00897B),
                  ));
                }
              },
              child: Text('Add ${Helpers.formatCurrency(typicalAmount)}'),
            ),
        ],
      ),
    );
  }

  /// Shows the contacts picker and adds selected contacts to the group.
  void _showAddFromContactsFromDetail(BuildContext context) {
    final existingMembers = ref.read(membersByGroupProvider(widget.groupId));
    final existingEmails = existingMembers
        .where((m) => m.email.isNotEmpty)
        .map((m) => m.email)
        .toList();
    final group = ref.read(groupByIdProvider(widget.groupId));

    showDialog(
      context: context,
      builder: (ctx) => ContactsPickerDialog(
        excludeEmails: existingEmails,
        onSelected: (contacts) async {
          int addedCount = 0;
          for (final contact in contacts) {
            final email = contact.email.toLowerCase();
            String memberId;

            final existing =
                await FirestoreService.instance.getMemberByEmail(email);
            if (existing != null) {
              memberId = existing.id;
            } else {
              memberId = const Uuid().v4();
              await FirestoreService.instance.saveMember(MemberModel(
                id: memberId,
                name: contact.name,
                email: email,
                phone: contact.phone,
                colorHex: contact.colorHex,
                createdAt: DateTime.now(),
              ));
            }

            final currentGroup =
                ref.read(groupByIdProvider(widget.groupId));
            if (currentGroup != null &&
                !currentGroup.memberIds.contains(memberId)) {
              final updatedEmails = email.isNotEmpty &&
                      !currentGroup.memberEmails.contains(email)
                  ? [...currentGroup.memberEmails, email]
                  : currentGroup.memberEmails;

              GroupModel updatedGroup = currentGroup.copyWith(
                memberIds: [...currentGroup.memberIds, memberId],
                memberEmails: updatedEmails,
              );

              if (currentGroup.type == AppConstants.poolFund) {
                final now = DateTime.now();
                final monthKey =
                    '${now.year}-${now.month.toString().padLeft(2, '0')}';
                if (currentGroup.poolContributionClosedMonths
                    .contains(monthKey)) {
                  final newClosed = List<String>.from(
                      currentGroup.poolContributionClosedMonths)
                    ..remove(monthKey);
                  updatedGroup = updatedGroup.copyWith(
                      poolContributionClosedMonths: newClosed);
                }
              }

              await ref
                  .read(groupProvider.notifier)
                  .updateGroup(updatedGroup);
              addedCount++;

              // Pool fund contribution prompt for each contact added
              if (context.mounted &&
                  group?.type == AppConstants.poolFund) {
                await _showPoolNewMemberPromptDetail(
                    context, contact.name, memberId);
              }
            }
          }

          if (context.mounted && addedCount > 0) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('$addedCount member(s) added from contacts'),
            ));
          }
        },
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, GroupModel group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text(
            'Are you sure you want to delete "${group.name}"? This will permanently delete all expenses and data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref
                    .read(groupProvider.notifier)
                    .deleteGroup(group.id);
                if (context.mounted) context.go('/');
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete group: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete'),
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
  bool _showOverall = false;

  static final _kMinMonth = DateTime(2026, 1);
  DateTime _selectedMonth = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }();

  DateTime get _maxMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  String _fmtMonth(DateTime dt) => DateFormat('MMM yyyy').format(dt);

  @override
  Widget build(BuildContext context) {
    List<ExpenseModel> expenses;
    if (_showOverall) {
      expenses = ref.watch(expensesByGroupProvider(widget.groupId));
    } else {
      final p = GroupMonthParam(
          groupId: widget.groupId,
          year: _selectedMonth.year,
          month: _selectedMonth.month);
      expenses = ref.watch(expensesByGroupMonthProvider(p));
    }

    final members = ref.watch(membersByGroupProvider(widget.groupId));

    if (_filterCategory != null) {
      expenses =
          expenses.where((e) => e.category == _filterCategory).toList();
    }

    return Column(
      children: [
        // Month selector + Overall toggle row
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
                          'Overall — All Time',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF00897B),
                              fontWeight: FontWeight.w500),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left, size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: (_selectedMonth.isAfter(_kMinMonth) ||
                                    (_selectedMonth.year ==
                                            _kMinMonth.year &&
                                        _selectedMonth.month >
                                            _kMinMonth.month))
                                ? () => setState(() => _selectedMonth =
                                    DateTime(_selectedMonth.year,
                                        _selectedMonth.month - 1))
                                : null,
                            color: (_selectedMonth.isAfter(_kMinMonth) ||
                                    (_selectedMonth.year ==
                                            _kMinMonth.year &&
                                        _selectedMonth.month >
                                            _kMinMonth.month))
                                ? const Color(0xFF00897B)
                                : Colors.grey[300],
                          ),
                          Text(
                            _fmtMonth(_selectedMonth),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right,
                                size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: (_selectedMonth.year ==
                                        _maxMonth.year &&
                                    _selectedMonth.month ==
                                        _maxMonth.month)
                                ? null
                                : () => setState(() => _selectedMonth =
                                    DateTime(_selectedMonth.year,
                                        _selectedMonth.month + 1)),
                            color: (_selectedMonth.year == _maxMonth.year &&
                                    _selectedMonth.month ==
                                        _maxMonth.month)
                                ? Colors.grey[300]
                                : const Color(0xFF00897B),
                          ),
                        ],
                      ),
              ),
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
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              _chip('All', null),
              ...AppConstants.categories.map((c) => _chip(c, c)),
            ],
          ),
        ),
        Expanded(
          child: expenses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'Nothing is here',
                        style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _showOverall
                            ? 'No expenses recorded yet'
                            : 'No expenses for this month',
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: expenses.length,
                  itemBuilder: (ctx, i) {
                    final e = expenses[i];
                    return _SimpleExpenseTile(
                      expense: e,
                      members: members,
                      onDelete: () {
                        final deleted = e;
                        ref
                            .read(expenseProvider.notifier)
                            .deleteExpense(e.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Expense deleted'),
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () => ref
                                  .read(expenseProvider.notifier)
                                  .addExpense(deleted),
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

  Widget _chip(String label, String? cat) {
    final selected = _filterCategory == cat;
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
}

class _SimpleExpenseTile extends StatelessWidget {
  final ExpenseModel expense;
  final List<MemberModel> members;
  final VoidCallback onDelete;

  const _SimpleExpenseTile({
    required this.expense,
    required this.members,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final payer = members.firstWhereOrNull(
        (m) => m.id == expense.paidByMemberId);
    final catColor = AppConstants.categoryColor(expense.category);

    return Dismissible(
      key: Key(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: catColor.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
                AppConstants.categoryIcon(expense.category),
                color: catColor,
                size: 20),
          ),
          title: Text(expense.description,
              style: const TextStyle(fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${payer?.name ?? 'Unknown'} • ${Helpers.formatDateShort(expense.date)}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Text(
            Helpers.formatCurrency(expense.amount),
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF00897B),
                fontSize: 15),
          ),
        ),
      ),
    );
  }
}



