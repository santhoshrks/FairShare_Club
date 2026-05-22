import 'package:flutter/material.dart';
import '../models/member_model.dart';
import '../utils/helpers.dart';
import 'member_avatar.dart';

class BalanceCard extends StatelessWidget {
  final MemberModel member;
  final double balance;
  final VoidCallback? onSettleUp;

  const BalanceCard({
    super.key,
    required this.member,
    required this.balance,
    this.onSettleUp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSettled = balance.abs() < 0.01;
    final isPositive = balance > 0.01;
    final color = isSettled
        ? Colors.grey
        : isPositive
            ? const Color(0xFF43A047)
            : const Color(0xFFE53935);
    final bgColor = isSettled
        ? Colors.grey.withAlpha(20)
        : isPositive
            ? const Color(0xFF43A047).withAlpha(15)
            : const Color(0xFFE53935).withAlpha(15);
    final label = isSettled ? 'Settled' : isPositive ? 'Gets back' : 'Owes';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Row(
          children: [
            MemberAvatar(
              name: member.name,
              colorHex: member.colorHex,
              size: 44,
              fontSize: 16,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isSettled
                      ? Helpers.formatCurrency(0)
                      : (isPositive ? '+' : '') +
                          Helpers.formatCurrency(balance.abs()),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                if (!isSettled && !isPositive && onSettleUp != null) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: onSettleUp,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00897B),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Settle Up',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
