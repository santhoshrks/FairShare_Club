import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/group_model.dart';
import '../providers/auth_provider.dart';
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
    final currentUser = ref.watch(currentUserProvider);
    final allMembers = ref.watch(memberProvider);

    // Resolve display name: prefer Firestore member profile, fall back to
    // Firebase Auth displayName, then email prefix, then empty string.
    final memberProfile = currentUser != null
        ? allMembers.firstWhereOrNull((m) => m.id == currentUser.uid)
        : null;
    final rawName = memberProfile?.name.isNotEmpty == true
        ? memberProfile!.name
        : (currentUser?.displayName?.isNotEmpty == true
            ? currentUser!.displayName!
            : (currentUser?.email?.split('@').first ?? ''));
    final displayName = rawName.isNotEmpty
        ? rawName[0].toUpperCase() + rawName.substring(1)
        : '';

    // Time-of-day greeting
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    // "Sunday, 25 May 2026"
    final now = DateTime.now();
    final dayName = DateFormat('EEEE').format(now);   // e.g. Sunday
    final dateStr = DateFormat('d MMMM y').format(now); // e.g. 25 May 2026

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(groupProvider.notifier).refresh();
          await Future.delayed(const Duration(milliseconds: 800));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              floating: true,
              backgroundColor: const Color(0xFF00897B),
              toolbarHeight: 80,
              titleSpacing: 16,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Day + date row
                  Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          color: Colors.white70, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        '$dayName, $dateStr',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Greeting + name
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                      children: [
                        TextSpan(text: '$greeting${displayName.isNotEmpty ? ", " : ""}'),
                        if (displayName.isNotEmpty)
                          TextSpan(
                            text: displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        const TextSpan(text: ' 👋'),
                      ],
                    ),
                  ),
                ],
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


