import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/contribution_model.dart';
import '../models/group_model.dart';
import '../models/member_model.dart';
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
import '../widgets/empty_state.dart';

class MemberScreen extends ConsumerStatefulWidget {
  final String groupId;
  final bool embedded;

  const MemberScreen({
    super.key,
    required this.groupId,
    this.embedded = false,
  });

  @override
  ConsumerState<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends ConsumerState<MemberScreen> {
  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersByGroupProvider(widget.groupId));
    final group = ref.watch(groupByIdProvider(widget.groupId));
    final theme = Theme.of(context);

    // No remove option for pool fund groups
    final isPoolFund = group?.type == AppConstants.poolFund;

    final content = members.isEmpty
        ? EmptyState(
            icon: Icons.person_add,
            title: 'No Members',
            subtitle: 'Add members to this group',
            actionLabel: 'Add Member',
            onAction: () => _showAddMemberDialog(context, ref, group),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: members.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${members.length} Member${members.length != 1 ? 's' : ''}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                _showAddFromContactsDialog(context, ref, group),
                            icon: const Icon(Icons.contacts, size: 16),
                            label: const Text('Contacts'),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _showAddMemberDialog(context, ref, group),
                            icon: const Icon(Icons.person_add, size: 16),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }
              final member = members[i - 1];
              return _MemberTile(
                member: member,
                groupId: widget.groupId,
                // No remove option for pool fund
                onRemove: (!isPoolFund && group != null)
                    ? () => _removeMember(context, ref, member, group)
                    : null,
              );
            },
          );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: content,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddMemberDialog(context, ref, group),
        child: const Icon(Icons.person_add),
      ),
    );
  }

  void _showAddMemberDialog(
      BuildContext context, WidgetRef ref, GroupModel? group) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedColor = AppConstants.avatarColors[0];
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Member'),
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
                    child: Text('Color',
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
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: selectedColor == hex
                                ? Border.all(
                                    color: Colors.black, width: 2)
                                : null,
                          ),
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
                  final existing =
                      await FirestoreService.instance.getMemberByEmail(email);
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

                // Add to group
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
                      final newClosedMonths = List<String>.from(
                          currentGroup.poolContributionClosedMonths)
                        ..remove(monthKey);
                      updatedGroup = updatedGroup.copyWith(
                          poolContributionClosedMonths: newClosedMonths);
                    }
                  }

                  await ref
                      .read(groupProvider.notifier)
                      .updateGroup(updatedGroup);
                }

                // Send invite if new unregistered member
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
                  await _showPoolNewMemberPrompt(
                      context, ref, name, memberId);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows a prompt offering to add the same contribution amount as existing
  /// pool fund members have contributed this month.
  Future<void> _showPoolNewMemberPrompt(
      BuildContext context, WidgetRef ref, String memberName, String memberId) async {
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
              child: Text(
                  'Add ${Helpers.formatCurrency(typicalAmount)}'),
            ),
        ],
      ),
    );
  }

  /// Shows the contacts picker and adds selected contacts to the group.
  void _showAddFromContactsDialog(
      BuildContext context, WidgetRef ref, GroupModel? group) {
    final existingMembers = ref.read(membersByGroupProvider(widget.groupId));
    final existingEmails = existingMembers
        .where((m) => m.email.isNotEmpty)
        .map((m) => m.email)
        .toList();

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

              // Pool fund contribution prompt for each added member
              if (context.mounted &&
                  group?.type == AppConstants.poolFund) {
                await _showPoolNewMemberPrompt(
                    context, ref, contact.name, memberId);
              }
            }
          }

          if (context.mounted && addedCount > 0) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '$addedCount member(s) added from contacts'),
            ));
          }
        },
      ),
    );
  }

  Future<void> _removeMember(BuildContext context, WidgetRef ref,
      MemberModel member, GroupModel group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.name} from this group?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final updatedMemberIds =
          List<String>.from(group.memberIds)..remove(member.id);
      await ref.read(groupProvider.notifier).updateGroup(
            group.copyWith(memberIds: updatedMemberIds),
          );
    }
  }
}

class _MemberTile extends ConsumerWidget {
  final MemberModel member;
  final String groupId;
  final VoidCallback? onRemove;

  const _MemberTile({
    required this.member,
    required this.groupId,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesByGroupProvider(groupId));
    final balances = Helpers.calculateBalances(expenses);
    final balance = balances[member.id] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: MemberAvatar(
          name: member.name,
          colorHex: member.colorHex,
          size: 44,
          fontSize: 16,
        ),
        title: Text(member.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (member.email.isNotEmpty)
              Text(member.email,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            if (member.phone.isNotEmpty)
              Text(member.phone,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (balance >= 0 ? '+' : '') +
                  Helpers.formatCurrency(balance),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: balance >= 0
                    ? const Color(0xFF43A047)
                    : const Color(0xFFE53935),
                fontSize: 13,
              ),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.remove_circle_outline,
                    color: Colors.red, size: 20),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
