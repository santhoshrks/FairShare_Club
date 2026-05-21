import 'package:flutter/material.dart';
import '../models/member_model.dart';
import '../utils/helpers.dart';
import 'member_avatar.dart';

class WalletCard extends StatelessWidget {
  final MemberModel member;
  final double balance;
  final VoidCallback? onRecharge;
  final VoidCallback? onTap;

  const WalletCard({
    super.key,
    required this.member,
    required this.balance,
    this.onRecharge,
    this.onTap,
  });

  Color get _balanceColor {
    if (balance > 0) return const Color(0xFF43A047);
    if (balance == 0) return Colors.orange;
    return const Color(0xFFE53935);
  }

  bool get _needsRecharge => balance <= 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Stack(
                children: [
                  MemberAvatar(
                    name: member.name,
                    colorHex: member.colorHex,
                    size: 48,
                    fontSize: 18,
                  ),
                  if (_needsRecharge)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE53935),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
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
                    if (_needsRecharge)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935).withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '⚡ Recharge Needed',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFE53935),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Text(
                        'Balance',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Helpers.formatCurrency(balance),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _balanceColor,
                    ),
                  ),
                  if (onRecharge != null) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: onRecharge,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00897B),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '+ Recharge',
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
      ),
    );
  }
}

