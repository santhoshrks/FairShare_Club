import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/wallet_transaction_model.dart';
import '../models/member_model.dart';
import '../providers/wallet_provider.dart';
import '../providers/expense_provider.dart';
import '../utils/helpers.dart';
import '../utils/constants.dart';
import '../widgets/wallet_card.dart';
import '../widgets/empty_state.dart';

class WalletSplitScreen extends ConsumerWidget {
  final String groupId;

  const WalletSplitScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersByGroupProvider(groupId));
    final walletBalances = ref.watch(allMemberWalletBalancesProvider(groupId));
    final totalBalance = ref.watch(totalGroupWalletBalanceProvider(groupId));
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Total balance card
        Card(
          color: const Color(0xFF7B1FA2),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Group Balance',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        Helpers.formatCurrency(totalBalance),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${members.length} member${members.length != 1 ? 's' : ''}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
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
                  child: const Icon(Icons.account_balance_wallet,
                      color: Colors.white, size: 30),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () =>
                    _showAddExpenseDialog(context, ref, members),
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('Add Expense'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _showRechargeAllDialog(context, ref, members),
                icon: const Icon(Icons.people_alt, size: 18),
                label: const Text('Recharge All'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Member wallets
        Text(
          'Member Wallets',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (members.isEmpty)
          const EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No Members',
            subtitle: 'Add members to manage wallets',
          )
        else
          ...members.map((member) {
            final balance = walletBalances[member.id] ?? 0;
            return WalletCard(
              member: member,
              balance: balance,
              onRecharge: () =>
                  _showRechargeDialog(context, ref, member.id, member.name),
              onTap: () => _showMemberTransactions(context, ref, member.id,
                  member.name, member.colorHex),
            );
          }),

        const SizedBox(height: 80),
      ],
    );
  }

  void _showAddExpenseDialog(
      BuildContext context, WidgetRef ref, List<MemberModel> members) {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    String? payerMemberId =
        members.isNotEmpty ? members.first.id : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Wallet Expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹)',
                    prefixText: '₹ ',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descController,
                  decoration:
                      const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: payerMemberId,
                  decoration: const InputDecoration(labelText: 'Paid By'),
                  items: members
                      .map<DropdownMenuItem<String>>((m) =>
                          DropdownMenuItem(
                              value: m.id,
                              child: Text(m.name)))
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => payerMemberId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text);
                if (amount == null ||
                    amount <= 0 ||
                    descController.text.isEmpty ||
                    payerMemberId == null) return;

                final share = amount / members.length;
                final uuid = const Uuid();

                // Debit payer the full amount paid
                await ref.read(walletProvider.notifier).addTransaction(
                      WalletTransactionModel(
                        id: uuid.v4(),
                        groupId: groupId,
                        memberId: payerMemberId!,
                        amount: amount,
                        type: AppConstants.debit,
                        description: descController.text.trim(),
                        date: DateTime.now(),
                      ),
                    );

                // Credit payer back their share (payer only pays their split)
                // Debit everyone else their share
                for (final m in members) {
                  if (m.id != payerMemberId) {
                    await ref
                        .read(walletProvider.notifier)
                        .addTransaction(
                          WalletTransactionModel(
                            id: uuid.v4(),
                            groupId: groupId,
                            memberId: m.id,
                            amount: share,
                            type: AppConstants.debit,
                            description:
                                'Share: ${descController.text.trim()}',
                            date: DateTime.now(),
                          ),
                        );
                  }
                }

                // Credit back payer's share that others owe
                final othersCount = members.length - 1;
                if (othersCount > 0) {
                  await ref.read(walletProvider.notifier).addTransaction(
                        WalletTransactionModel(
                          id: uuid.v4(),
                          groupId: groupId,
                          memberId: payerMemberId!,
                          amount: share * othersCount,
                          type: AppConstants.credit,
                          description:
                              'Reimbursement: ${descController.text.trim()}',
                          date: DateTime.now(),
                        ),
                      );
                }

                Navigator.of(ctx).pop();
              },
              child: const Text('Add Expense'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRechargeDialog(
      BuildContext context, WidgetRef ref, String memberId, String memberName) {
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Recharge $memberName\'s Wallet'),
        content: TextFormField(
          controller: amountController,
          decoration: const InputDecoration(
            labelText: 'Amount (₹)',
            prefixText: '₹ ',
          ),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text);
              if (amount == null || amount <= 0) return;

              await ref.read(walletProvider.notifier).addTransaction(
                    WalletTransactionModel(
                      id: const Uuid().v4(),
                      groupId: groupId,
                      memberId: memberId,
                      amount: amount,
                      type: AppConstants.credit,
                      description: 'Wallet recharge',
                      date: DateTime.now(),
                    ),
                  );
              Navigator.of(ctx).pop();
            },
            child: const Text('Recharge'),
          ),
        ],
      ),
    );
  }

  void _showRechargeAllDialog(
      BuildContext context, WidgetRef ref, List<MemberModel> members) {
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recharge All Wallets'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Set the same recharge amount for all members:'),
            const SizedBox(height: 12),
            TextFormField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Amount per member (₹)',
                prefixText: '₹ ',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text);
              if (amount == null || amount <= 0) return;
              final uuid = const Uuid();

              for (final m in members) {
                await ref.read(walletProvider.notifier).addTransaction(
                      WalletTransactionModel(
                        id: uuid.v4(),
                        groupId: groupId,
                        memberId: m.id,
                        amount: amount,
                        type: AppConstants.credit,
                        description: 'Group recharge',
                        date: DateTime.now(),
                      ),
                    );
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Recharge All'),
          ),
        ],
      ),
    );
  }

  void _showMemberTransactions(BuildContext context, WidgetRef ref,
      String memberId, String memberName, String colorHex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) =>
            _MemberTransactionSheet(
          groupId: groupId,
          memberId: memberId,
          memberName: memberName,
          colorHex: colorHex,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _MemberTransactionSheet extends ConsumerWidget {
  final String groupId;
  final String memberId;
  final String memberName;
  final String colorHex;
  final ScrollController scrollController;

  const _MemberTransactionSheet({
    required this.groupId,
    required this.memberId,
    required this.memberName,
    required this.colorHex,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(walletTxsByMemberProvider(
        (groupId: groupId, memberId: memberId)));
    final balance = ref.watch(memberWalletBalanceProvider(
        (groupId: groupId, memberId: memberId)));
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '$memberName\'s Wallet',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                Helpers.formatCurrency(balance),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: balance >= 0
                      ? const Color(0xFF43A047)
                      : const Color(0xFFE53935),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: txs.isEmpty
                ? const EmptyState(
                    icon: Icons.history,
                    title: 'No Transactions',
                    subtitle: 'Transactions will appear here',
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: txs.length,
                    itemBuilder: (ctx, i) {
                      final tx = txs[i];
                      final isCredit = tx.type == AppConstants.credit;
                      final color = isCredit
                          ? const Color(0xFF43A047)
                          : const Color(0xFFE53935);
                      return ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color.withAlpha(25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isCredit
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: color,
                            size: 18,
                          ),
                        ),
                        title: Text(tx.description,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          Helpers.formatDate(tx.date),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                        trailing: Text(
                          '${isCredit ? '+' : '-'}${Helpers.formatCurrency(tx.amount)}',
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}


