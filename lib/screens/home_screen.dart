import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/group_model.dart';
import '../providers/group_provider.dart';
import '../providers/expense_provider.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';
import '../widgets/member_avatar.dart';
import '../widgets/empty_state.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(activeGroupsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () async {
          // Re-check for pending group invites (e.g. added to a group by
          // another user while this device was offline / in background).
          ref.read(groupProvider.notifier).refresh();
          await Future.delayed(const Duration(milliseconds: 800));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            backgroundColor: const Color(0xFF00897B),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title: Row(
                children: [
                  const Icon(Icons.account_balance_wallet,
                      color: Colors.white, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'FairShare Club',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                onPressed: () => context.push('/settings'),
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
              ),
            ],
          ),
          if (groups.isEmpty)
            SliverFillRemaining(
              child: EmptyState(
                icon: Icons.group_add,
                title: 'No Groups Yet',
                subtitle:
                    'Create a group to start splitting expenses or managing a shared pool.',
                actionLabel: 'Create Group',
                onAction: () => context.push('/add-group'),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Active Groups',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/groups'),
                      child: const Text('See All'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return _GroupCard(group: groups[index]);
                  },
                  childCount: groups.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  'Recent Activity',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const _RecentActivityList(),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ],
        ),  // CustomScrollView
      ),    // RefreshIndicator
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add-group'),
        icon: const Icon(Icons.add),
        label: const Text('New Group'),
      ),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  final GroupModel group;

  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final members = ref.watch(membersByGroupProvider(group.id));
    final typeColor = AppConstants.groupTypeColor(group.type);
    final typeIcon = AppConstants.groupTypeIcon(group.type);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/group/${group.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: typeColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(typeIcon, color: typeColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        if (group.description.isNotEmpty)
                          Text(
                            group.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: typeColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      AppConstants.groupTypeLabel(group.type),
                      style: TextStyle(
                        fontSize: 10,
                        color: typeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (members.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    MemberAvatarStack(
                      members: members
                          .map((m) => (name: m.name, colorHex: m.colorHex))
                          .toList(),
                    ),
                    Row(
                      children: [
                        Icon(Icons.people_alt_outlined,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          '${members.length} member${members.length != 1 ? 's' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      Helpers.formatDateShort(group.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentActivityList extends ConsumerWidget {
  const _RecentActivityList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allExpenses = ref.watch(expenseProvider);
    final allMembers = ref.watch(memberProvider);
    final allGroups = ref.watch(groupProvider);

    final recent = allExpenses.take(5).toList();

    if (recent.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('No recent activity',
                style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final expense = recent[index];
            final theme = Theme.of(context);
            final payer = allMembers.firstWhereOrNull(
                (m) => m.id == expense.paidByMemberId);
            final group = allGroups.firstWhereOrNull(
                (g) => g.id == expense.groupId);
            final catColor = AppConstants.categoryColor(expense.category);

            return ListTile(
              contentPadding: EdgeInsets.zero,
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
                  '${group?.name ?? ''} • ${payer?.name ?? 'Unknown'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey[600])),
              trailing: Text(
                Helpers.formatCurrency(expense.amount),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF00897B)),
              ),
              onTap: () {
                if (group != null) {
                  context.push('/group/${group.id}');
                }
              },
            );
          },
          childCount: recent.length,
        ),
      ),
    );
  }
}


