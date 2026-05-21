import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'FairShare Club';
  static const String currencySymbol = '₹';

  // Group Types
  static const String expenseSplit = 'expenseSplit';
  static const String poolFund = 'poolFund';
  static const String walletSplit = 'walletSplit';

  // Split Types
  static const String equalSplit = 'equal';
  static const String customSplit = 'custom';
  static const String percentageSplit = 'percentage';

  // Transaction Types
  static const String credit = 'credit';
  static const String debit = 'debit';

  // Hive Box Names
  static const String groupsBox = 'groups';
  static const String membersBox = 'members';
  static const String expensesBox = 'expenses';
  static const String contributionsBox = 'contributions';
  static const String walletTransactionsBox = 'wallet_transactions';
  static const String settingsBox = 'settings';

  // Settings Keys
  static const String themeKey = 'theme_mode';
  static const String notificationsKey = 'notifications_enabled';
  static const String firstLaunchKey = 'first_launch';

  // Categories
  static const List<String> categories = [
    'food',
    'travel',
    'shopping',
    'rent',
    'entertainment',
    'other',
  ];

  static IconData categoryIcon(String category) {
    switch (category) {
      case 'food':
        return Icons.restaurant;
      case 'travel':
        return Icons.directions_car;
      case 'shopping':
        return Icons.shopping_bag;
      case 'rent':
        return Icons.home;
      case 'entertainment':
        return Icons.movie;
      default:
        return Icons.receipt;
    }
  }

  static Color categoryColor(String category) {
    switch (category) {
      case 'food':
        return const Color(0xFFFF7043);
      case 'travel':
        return const Color(0xFF29B6F6);
      case 'shopping':
        return const Color(0xFFAB47BC);
      case 'rent':
        return const Color(0xFF66BB6A);
      case 'entertainment':
        return const Color(0xFFFFCA28);
      default:
        return const Color(0xFF78909C);
    }
  }

  // Avatar Colors (10 distinct colors)
  static const List<String> avatarColors = [
    'FF1976D2', // Blue
    'FFE53935', // Red
    'FF388E3C', // Green
    'FFF57C00', // Orange
    'FF7B1FA2', // Purple
    'FF00838F', // Cyan
    'FFC62828', // Dark Red
    'FF00695C', // Teal
    'FF4527A0', // Deep Purple
    'FF558B2F', // Light Green
  ];

  static Color colorFromHex(String hex) {
    return Color(int.parse(hex, radix: 16));
  }

  static String groupTypeLabel(String type) {
    switch (type) {
      case expenseSplit:
        return 'Expense Split';
      case poolFund:
        return 'Pool Fund';
      case walletSplit:
        return 'Wallet Split';
      default:
        return 'Unknown';
    }
  }

  static Color groupTypeColor(String type) {
    switch (type) {
      case expenseSplit:
        return const Color(0xFF1976D2);
      case poolFund:
        return const Color(0xFF00897B);
      case walletSplit:
        return const Color(0xFF7B1FA2);
      default:
        return const Color(0xFF78909C);
    }
  }

  static IconData groupTypeIcon(String type) {
    switch (type) {
      case expenseSplit:
        return Icons.receipt_long;
      case poolFund:
        return Icons.savings;
      case walletSplit:
        return Icons.account_balance_wallet;
      default:
        return Icons.group;
    }
  }
}

