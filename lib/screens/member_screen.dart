import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/member_model.dart';
import '../providers/group_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../services/invite_service.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';
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

    final content = members.isEmpty
        ? EmptyState(
            icon: Icons.person_add,
            title: 'No Members',
            subtitle: 'Add members to this group',
            actionLabel: 'Add Member',
            onAction: () => _showAddMemberDialog(context, ref),
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
                      TextButton.icon(
                        onPressed: () =>
                            _showAddMemberDialog(context, ref),
                        icon: const Icon(Icons.person_add, size: 16),
                        label: const Text('Add Member'),
                      ),
                    ],
                  ),
                );
              }
              final member = members[i - 1];
              return _MemberTile(
                member: member,
                groupId: widget.groupId,
                onRemove: group != null
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
        onPressed: () => _showAddMemberDialog(context, ref),
        child: const Icon(Icons.person_add),
      ),
    );
  }

  void _showAddMemberDialog(BuildContext context, WidgetRef ref) {
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
                      labelText: 'Email (recommended)',
                      hintText: 'member@example.com',
                      helperText: 'They need this email to see the group',
                    ),
                    keyboardType: TextInputType.emailAddress,
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
                  // Look up by email first
                  final existing =
                      await FirestoreService.instance.getMemberByEmail(email);
                  if (existing != null) {
                    memberId = existing.id;
                  } else {
                    // Not registered yet — create placeholder
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
                  // No email — offline member
                  memberId = const Uuid().v4();
                  await FirestoreService.instance.saveMember(MemberModel(
                    id: memberId,
                    name: name,
                    phone: phoneController.text.trim(),
                    colorHex: selectedColor,
                    createdAt: DateTime.now(),
                  ));
                }

                // Add to group
                final group = ref.read(groupByIdProvider(widget.groupId));
                if (group != null &&
                    !group.memberIds.contains(memberId)) {
                  await ref.read(groupProvider.notifier).updateGroup(
                        group.copyWith(
                            memberIds: [...group.memberIds, memberId]),
                      );
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
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeMember(BuildContext context, WidgetRef ref,
      MemberModel member, group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content:
            Text('Remove ${member.name} from this group?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red),
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


