import 'package:flutter/material.dart';
import '../utils/helpers.dart';

class PoolProgressBar extends StatelessWidget {
  final double balance;
  final double totalContributed;
  final double percentage;

  const PoolProgressBar({
    super.key,
    required this.balance,
    required this.totalContributed,
    required this.percentage,
  });

  Color get _barColor {
    if (percentage > 50) return const Color(0xFF43A047);
    if (percentage > 20) return const Color(0xFFFB8C00);
    return const Color(0xFFE53935);
  }

  String get _statusLabel {
    if (percentage > 50) return 'Healthy';
    if (percentage > 20) return 'Running Low';
    return 'Critical';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pool Balance',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _barColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: _barColor),
                      const SizedBox(width: 4),
                      Text(
                        _statusLabel,
                        style: TextStyle(
                          color: _barColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              Helpers.formatCurrency(balance),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: _barColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'of ${Helpers.formatCurrency(totalContributed)} contributed',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: percentage / 100),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation(_barColor),
                    minHeight: 12,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${percentage.toStringAsFixed(1)}% remaining',
                  style: TextStyle(
                    fontSize: 12,
                    color: _barColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Spent: ${Helpers.formatCurrency(totalContributed - balance)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

