import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../models/group_model.dart';
import '../models/member_model.dart';
import '../models/contribution_model.dart';
import '../models/wallet_transaction_model.dart';
import '../providers/group_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/pool_provider.dart';
import '../providers/wallet_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../services/invite_service.dart';
import '../utils/constants.dart';

class AddGroupScreen extends ConsumerStatefulWidget {
  const AddGroupScreen({super.key});

  @override
  ConsumerState<AddGroupScreen> createState() => _AddGroupScreenState();
}

class _AddGroupScreenState extends ConsumerState<AddGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedType = AppConstants.expenseSplit;
  final List<_TempMember> _members = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _addMember() {
    showDialog(
      context: context,
      builder: (ctx) => _AddMemberDialog(
        onAdd: (name, email, phone, colorHex) {
          setState(() {
            _members.add(_TempMember(
              name: name,
              email: email,
              phone: phone,
              colorHex: colorHex,
              initialAmount: 0,
            ));
          });
        },
      ),
    );
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one member')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final currentUser = ref.read(currentUserProvider);
    final uuid = const Uuid();
    final groupId = uuid.v4();
    final memberIds = <String>[];
    // Track members who are NOT registered yet — to send invites
    final List<_TempMember> membersToInvite = [];
    String inviterName = 'Someone';

    // Auto-add the current logged-in user as first member
    if (currentUser != null) {
      final myProfile =
          await FirestoreService.instance.getOrCreateCurrentUserProfile(
        name: currentUser.displayName ?? currentUser.email ?? 'Me',
        colorHex: AppConstants.avatarColors[0],
      );
      memberIds.add(myProfile.id);
      inviterName = myProfile.name;
    }

    // Add each invited member by email lookup
    for (final tm in _members) {
      if (tm.email.isNotEmpty) {
        final existing =
            await FirestoreService.instance.getMemberByEmail(tm.email);
        if (existing != null) {
          if (!memberIds.contains(existing.id)) memberIds.add(existing.id);
          // Already registered — no invite needed
        } else {
          // Not registered yet — create placeholder & queue invite
          final memberId = uuid.v4();
          await FirestoreService.instance.saveMember(MemberModel(
            id: memberId,
            name: tm.name,
            email: tm.email.toLowerCase(),
            phone: tm.phone,
            colorHex: tm.colorHex,
            createdAt: DateTime.now(),
          ));
          memberIds.add(memberId);
          membersToInvite.add(tm); // send invite email
        }
      } else {
        // No email — create offline member
        final memberId = uuid.v4();
        await FirestoreService.instance.saveMember(MemberModel(
          id: memberId,
          name: tm.name,
          phone: tm.phone,
          colorHex: tm.colorHex,
          createdAt: DateTime.now(),
        ));
        memberIds.add(memberId);
      }
    }

    final group = GroupModel(
      id: groupId,
      name: _nameController.text.trim(),
      type: _selectedType,
      memberIds: memberIds,
      createdAt: DateTime.now(),
      description: _descController.text.trim(),
    );

    await ref.read(groupProvider.notifier).addGroup(group);

    // Handle initial amounts for pool/wallet
    if (_selectedType == AppConstants.poolFund) {
      for (int i = 0; i < _members.length; i++) {
        final amount = _members[i].initialAmount;
        // offset by 1 if current user was auto-added
        final idx = currentUser != null ? i + 1 : i;
        if (idx < memberIds.length && amount > 0) {
          await FirestoreService.instance.saveContribution(
            ContributionModel(
              id: uuid.v4(),
              groupId: groupId,
              memberId: memberIds[idx],
              amount: amount,
              date: DateTime.now(),
              note: 'Initial contribution',
            ),
          );
        }
      }
    } else if (_selectedType == AppConstants.walletSplit) {
      for (int i = 0; i < _members.length; i++) {
        final amount = _members[i].initialAmount;
        final idx = currentUser != null ? i + 1 : i;
        if (idx < memberIds.length && amount > 0) {
          await FirestoreService.instance.saveWalletTransaction(
            WalletTransactionModel(
              id: uuid.v4(),
              groupId: groupId,
              memberId: memberIds[idx],
              amount: amount,
              type: AppConstants.credit,
              description: 'Initial wallet balance',
              date: DateTime.now(),
            ),
          );
        }
      }
    }

    setState(() => _isLoading = false);
    if (!mounted) return;

    // Send invite emails to unregistered members
    if (membersToInvite.isNotEmpty) {
      final groupName = _nameController.text.trim();
      await _showInviteDialog(
          context, membersToInvite, groupName, inviterName);
    }

    if (mounted) context.go('/group/$groupId');
  }

  Future<void> _showInviteDialog(
    BuildContext context,
    List<_TempMember> members,
    String groupName,
    String inviterName,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.mail_outline, color: Color(0xFF00897B)),
            SizedBox(width: 8),
            Text('Send Invites'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${members.length} member(s) are not registered yet. '
              'Send them an invite to join FairShare Club!',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...members.map((m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('${m.name} (${m.email})',
                              style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Skip'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.share, size: 16),
            label: const Text('Share Invite'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              for (final m in members) {
                await InviteService.instance.shareInvite(
                  toEmail: m.email,
                  toName: m.name,
                  groupName: groupName,
                  inviterName: inviterName,
                );
              }
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.email_outlined, size: 16),
            label: const Text('Send Email'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              for (final m in members) {
                await InviteService.instance.sendEmailInvite(
                  toEmail: m.email,
                  toName: m.name,
                  groupName: groupName,
                  inviterName: inviterName,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Group'),
        leading: IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Group Name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Group Name',
                prefixIcon: Icon(Icons.group),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter group name' : null,
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Group Type
            Text('Group Type', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ...[
              AppConstants.expenseSplit,
              AppConstants.poolFund,
              AppConstants.walletSplit,
            ].map(
              (type) => RadioListTile<String>(
                value: type,
                groupValue: _selectedType,
                onChanged: (v) => setState(() => _selectedType = v!),
                title: Text(AppConstants.groupTypeLabel(type)),
                subtitle: Text(_typeDescription(type)),
                secondary: Icon(
                  AppConstants.groupTypeIcon(type),
                  color: _selectedType == type
                      ? AppConstants.groupTypeColor(type)
                      : null,
                ),
                activeColor: AppConstants.groupTypeColor(type),
              ),
            ),
            const SizedBox(height: 16),

            // Members
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Members (${_members.length})',
                    style: theme.textTheme.titleSmall),
                TextButton.icon(
                  onPressed: _addMember,
                  icon: const Icon(Icons.person_add, size: 16),
                  label: const Text('Add Member'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_members.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: const Center(
                  child: Text('No members added yet',
                      style: TextStyle(color: Colors.grey)),
                ),
              ),
            ..._members.asMap().entries.map((entry) {
              final i = entry.key;
              final member = entry.value;
              return _MemberTile(
                member: member,
                showAmountField:
                    _selectedType != AppConstants.expenseSplit,
                amountLabel: _selectedType == AppConstants.poolFund
                    ? 'Initial contribution (₹)'
                    : 'Wallet balance (₹)',
                onAmountChanged: (val) {
                  setState(() {
                    _members[i] = member.copyWith(initialAmount: val);
                  });
                },
                onRemove: () => setState(() => _members.removeAt(i)),
              );
            }),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _createGroup,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Create Group'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _typeDescription(String type) {
    switch (type) {
      case AppConstants.expenseSplit:
        return 'Track and split shared expenses among members';
      case AppConstants.poolFund:
        return 'Pool money together and track group spending';
      case AppConstants.walletSplit:
        return 'Each member has a personal wallet, expenses deduct from it';
      default:
        return '';
    }
  }
}

class _TempMember {
  final String name;
  final String email;
  final String phone;
  final String colorHex;
  final double initialAmount;

  _TempMember({
    required this.name,
    this.email = '',
    required this.phone,
    required this.colorHex,
    required this.initialAmount,
  });

  _TempMember copyWith({double? initialAmount}) {
    return _TempMember(
      name: name,
      email: email,
      phone: phone,
      colorHex: colorHex,
      initialAmount: initialAmount ?? this.initialAmount,
    );
  }
}

class _MemberTile extends StatelessWidget {
  final _TempMember member;
  final bool showAmountField;
  final String amountLabel;
  final ValueChanged<double> onAmountChanged;
  final VoidCallback onRemove;

  const _MemberTile({
    required this.member,
    required this.showAmountField,
    required this.amountLabel,
    required this.onAmountChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppConstants.colorFromHex(member.colorHex);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color,
              radius: 18,
              child: Text(
                member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (member.phone.isNotEmpty)
                    Text(member.phone,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  if (showAmountField) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: member.initialAmount > 0
                          ? member.initialAmount.toString()
                          : '',
                      decoration: InputDecoration(
                        labelText: amountLabel,
                        prefixText: '₹ ',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) =>
                          onAmountChanged(double.tryParse(v) ?? 0),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMemberDialog extends StatefulWidget {
  final Function(String name, String email, String phone, String colorHex) onAdd;

  const _AddMemberDialog({required this.onAdd});

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedColor = AppConstants.avatarColors[0];
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Member'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email (optional)',
                hintText: 'member@example.com',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Avatar Color',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppConstants.avatarColors.map((hex) {
                final color = AppConstants.colorFromHex(hex);
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = hex),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: _selectedColor == hex
                          ? Border.all(color: Colors.black, width: 2)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              widget.onAdd(
                _nameController.text.trim(),
                _emailController.text.trim(),
                _phoneController.text.trim(),
                _selectedColor,
              );
              Navigator.of(context).pop();
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}





