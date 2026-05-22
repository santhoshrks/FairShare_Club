import 'package:intl/intl.dart';
import '../models/expense_model.dart';
import '../models/member_model.dart';
import '../models/settlement_model.dart';

/// Parameter class for providers that need both a group ID and a specific month.
class GroupMonthParam {
  final String groupId;
  final int year;
  final int month;

  const GroupMonthParam({required this.groupId, required this.year, required this.month});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupMonthParam &&
          other.groupId == groupId &&
          other.year == year &&
          other.month == month);

  @override
  int get hashCode => Object.hash(groupId, year, month);

  /// e.g. "2026-05"
  String get key => '$year-${month.toString().padLeft(2, '0')}';
}

extension IterableExtension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

class Helpers {
  static String formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  static String formatCurrencyCompact(double amount) {
    if (amount >= 10000000) {
      return '₹${(amount / 10000000).toStringAsFixed(1)}Cr';
    } else if (amount >= 100000) {
      return '₹${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '₹${(amount / 1000).toStringAsFixed(1)}K';
    }
    return formatCurrency(amount);
  }

  static String formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  static String formatDateShort(DateTime date) {
    return DateFormat('dd MMM').format(date);
  }

  static String formatDateFull(DateTime date) {
    return DateFormat('EEEE, dd MMMM yyyy').format(date);
  }

  static String formatTime(DateTime date) {
    return DateFormat('hh:mm a').format(date);
  }

  static String getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  /// Calculate net balance for each member.
  /// Positive = owed money (gets back), Negative = owes money (needs to pay)
  static Map<String, double> calculateBalances(
    List<ExpenseModel> expenses, [
    List<SettlementModel> settlements = const [],
  ]) {
    final Map<String, double> balances = {};

    for (final expense in expenses) {
      final payer = expense.paidByMemberId;
      final splitMembers = expense.splitAmongMemberIds;
      if (splitMembers.isEmpty) continue;

      balances[payer] = (balances[payer] ?? 0) + expense.amount;

      if (expense.splitType == 'equal') {
        final share = expense.amount / splitMembers.length;
        for (final memberId in splitMembers) {
          balances[memberId] = (balances[memberId] ?? 0) - share;
        }
      } else if (expense.splitType == 'custom' ||
          expense.splitType == 'percentage') {
        for (final memberId in splitMembers) {
          double share = expense.customSplitAmounts[memberId] ?? 0;
          if (expense.splitType == 'percentage') {
            share = expense.amount * share / 100;
          }
          balances[memberId] = (balances[memberId] ?? 0) - share;
        }
      }
    }

    // Apply settlements: payer's balance goes up (they paid), receiver's goes down
    for (final s in settlements) {
      balances[s.fromMemberId] = (balances[s.fromMemberId] ?? 0) + s.amount;
      balances[s.toMemberId] = (balances[s.toMemberId] ?? 0) - s.amount;
    }

    return balances;
  }

  static double _getShare(ExpenseModel expense, String memberId) {
    if (expense.splitType == 'equal') {
      return expense.amount / expense.splitAmongMemberIds.length;
    } else if (expense.splitType == 'custom') {
      return expense.customSplitAmounts[memberId] ?? 0;
    } else if (expense.splitType == 'percentage') {
      return expense.amount *
          (expense.customSplitAmounts[memberId] ?? 0) /
          100;
    }
    return expense.amount / expense.splitAmongMemberIds.length;
  }

  /// Calculate pairwise net debts between members.
  /// Returns Map<debtorId, Map<creditorId, netAmount>>
  static Map<String, Map<String, double>> calculatePairwiseDebts(
    List<ExpenseModel> expenses, [
    List<SettlementModel> settlements = const [],
  ]) {
    // rawDebt[A][B] = raw amount A currently "owes" B (can go negative after settlements)
    final Map<String, Map<String, double>> rawDebt = {};

    for (final expense in expenses) {
      final payer = expense.paidByMemberId;
      final splitMembers = expense.splitAmongMemberIds;
      if (splitMembers.isEmpty) continue;

      for (final memberId in splitMembers) {
        if (memberId == payer) continue;
        final share = _getShare(expense, memberId);
        rawDebt[memberId] ??= {};
        rawDebt[memberId]![payer] =
            (rawDebt[memberId]![payer] ?? 0) + share;
      }
    }

    // Apply settlements: reduce debtor's raw debt to creditor
    for (final s in settlements) {
      rawDebt[s.fromMemberId] ??= {};
      rawDebt[s.fromMemberId]![s.toMemberId] =
          (rawDebt[s.fromMemberId]![s.toMemberId] ?? 0) - s.amount;
    }

    // Collect all member IDs seen
    final Set<String> allIds = {};
    rawDebt.forEach((a, creditors) {
      allIds.add(a);
      creditors.forEach((b, _) => allIds.add(b));
    });

    // Net each pair and build result
    final Map<String, Map<String, double>> netDebts = {};
    final Set<String> processed = {};

    for (final a in allIds) {
      for (final b in allIds) {
        if (a == b) continue;
        final ids = [a, b]..sort();
        final key = '${ids[0]}_${ids[1]}';
        if (processed.contains(key)) continue;
        processed.add(key);

        final aOwesB = rawDebt[a]?[b] ?? 0;
        final bOwesA = rawDebt[b]?[a] ?? 0;
        final net = aOwesB - bOwesA;

        if (net > 0.01) {
          netDebts[a] ??= {};
          netDebts[a]![b] = net;
        } else if (net < -0.01) {
          netDebts[b] ??= {};
          netDebts[b]![a] = -net;
        }
      }
    }

    return netDebts;
  }

  /// Simplify debts: returns list of {from, to, amount}
  static List<Map<String, dynamic>> simplifyDebts(Map<String, double> balances) {
    final List<Map<String, dynamic>> settlements = [];
    final creditors = <String, double>{};
    final debtors = <String, double>{};

    balances.forEach((memberId, balance) {
      if (balance > 0.01) {
        creditors[memberId] = balance;
      } else if (balance < -0.01) {
        debtors[memberId] = -balance;
      }
    });

    while (creditors.isNotEmpty && debtors.isNotEmpty) {
      final creditor = creditors.entries.first;
      final debtor = debtors.entries.first;

      final amount = creditor.value < debtor.value ? creditor.value : debtor.value;

      settlements.add({
        'from': debtor.key,
        'to': creditor.key,
        'amount': amount,
      });

      if (creditor.value - amount < 0.01) {
        creditors.remove(creditor.key);
      } else {
        creditors[creditor.key] = creditor.value - amount;
      }

      if (debtor.value - amount < 0.01) {
        debtors.remove(debtor.key);
      } else {
        debtors[debtor.key] = debtor.value - amount;
      }
    }

    return settlements;
  }

  static String getMemberName(String memberId, List<MemberModel> members) {
    try {
      return members.firstWhere((m) => m.id == memberId).name;
    } catch (_) {
      return 'Unknown';
    }
  }

  static String timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 30) {
      return formatDate(date);
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
