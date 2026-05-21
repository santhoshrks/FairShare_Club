import 'package:flutter/material.dart';
import '../models/expense_model.dart';
import '../models/member_model.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';
import 'member_avatar.dart';

class ExpenseCard extends StatelessWidget {
  final ExpenseModel expense;
  final List<MemberModel> members;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ExpenseCard({
    super.key,
    required this.expense,
    required this.members,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  MemberModel? _getMember(String id) {
    return members.firstWhereOrNull((m) => m.id == id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payer = _getMember(expense.paidByMemberId);
    final categoryColor = AppConstants.categoryColor(expense.category);
    final categoryIcon = AppConstants.categoryIcon(expense.category);

    return Dismissible(
      key: Key(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Colors.white),
            SizedBox(height: 4),
            Text('Delete', style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        if (onDelete != null) {
          onDelete!();
          return false; // Let the callback handle deletion
        }
        return false;
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: categoryColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(categoryIcon, color: categoryColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.description,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (payer != null) ...[
                            MemberAvatar(
                              name: payer.name,
                              colorHex: payer.colorHex,
                              size: 18,
                              fontSize: 8,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              payer.name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            Helpers.formatDate(expense.date),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: [
                          _buildChip(
                            context,
                            expense.category,
                            categoryColor,
                          ),
                          _buildChip(
                            context,
                            '${expense.splitAmongMemberIds.length} members',
                            Colors.blue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Helpers.formatCurrency(expense.amount),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF00897B),
                      ),
                    ),
                    if (onEdit != null)
                      GestureDetector(
                        onTap: onEdit,
                        child: const Icon(Icons.edit_outlined,
                            size: 16, color: Colors.grey),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

