import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/group_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) {
  final hive = ref.watch(hiveServiceProvider);
  final stored = hive.getSetting(AppConstants.themeKey, defaultValue: 'system');
  switch (stored) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _SectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('App Theme'),
            subtitle: Text(_themeModeLabel(themeMode)),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode, size: 16)),
                ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.auto_mode, size: 16)),
                ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode, size: 16)),
              ],
              selected: {themeMode},
              onSelectionChanged: (modes) async {
                final mode = modes.first;
                ref.read(themeModeProvider.notifier).state = mode;
                final hive = ref.read(hiveServiceProvider);
                final modeStr = mode == ThemeMode.light
                    ? 'light'
                    : mode == ThemeMode.dark
                        ? 'dark'
                        : 'system';
                await hive.saveSetting(AppConstants.themeKey, modeStr);
              },
              style: const ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),

          _SectionHeader('Notifications'),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Enable Notifications'),
            subtitle: const Text('Pool balance alerts, reminders'),
            trailing: Switch(
              value: _getNotificationsEnabled(ref),
              onChanged: (v) async {
                final hive = ref.read(hiveServiceProvider);
                await hive.saveSetting(AppConstants.notificationsKey, v);
                if (v) {
                  await NotificationService().requestPermission();
                  await NotificationService().scheduleMonthlyReminder();
                } else {
                  await NotificationService().cancelAll();
                }
                // Force rebuild
                ref.invalidate(hiveServiceProvider);
              },
            ),
          ),

          _SectionHeader('Data'),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Export All Data'),
            subtitle: const Text('Download backup of all groups'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () => _showExportOptions(context),
          ),
          ListTile(
            leading:
                const Icon(Icons.delete_forever_outlined, color: Colors.red),
            title: const Text('Clear All Data',
                style: TextStyle(color: Colors.red)),
            subtitle: const Text('Delete all groups and expenses'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () => _confirmClearData(context, ref),
          ),

          _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outlined),
            title: const Text('Version'),
            trailing: const Text('1.0.0', style: TextStyle(color: Colors.grey)),
          ),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: const Text('Rate App'),
            subtitle: const Text('Leave a review on Play Store'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Opening Play Store...')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () {},
          ),

          const SizedBox(height: 20),
          // Logged-in user info + logout
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.account_circle, color: Color(0xFF00897B)),
                title: Text(
                  FirebaseAuth.instance.currentUser?.email ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Logged in account'),
                trailing: TextButton.icon(
                  onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
                  icon: const Icon(Icons.logout, size: 16, color: Colors.red),
                  label: const Text('Logout',
                      style: TextStyle(color: Colors.red)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Icon(Icons.account_balance_wallet,
                    size: 40, color: Color(0xFF00897B)),
                const SizedBox(height: 8),
                Text(
                  'FairShare Club',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF00897B),
                  ),
                ),
                Text(
                  'Smart Group Expense & Pooling',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  bool _getNotificationsEnabled(WidgetRef ref) {
    final hive = ref.read(hiveServiceProvider);
    return hive.getSetting(AppConstants.notificationsKey,
            defaultValue: true) as bool;
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      default:
        return 'System default';
    }
  }

  void _showExportOptions(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Open a specific group to export its data as PDF')),
    );
  }

  void _confirmClearData(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
            'This will permanently delete ALL groups, members, and expenses. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                // Show loading indicator
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(children: [
                        SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 12),
                        Text('Deleting all data...'),
                      ]),
                      duration: Duration(seconds: 10),
                    ),
                  );
                }
                // Delete from Firestore (real database)
                await FirestoreService.instance.clearAllUserData();
                // Also clear Hive local cache – ignore errors if boxes are not open
                try { await Hive.box(AppConstants.groupsBox).clear(); } catch (_) {}
                try { await Hive.box(AppConstants.membersBox).clear(); } catch (_) {}
                try { await Hive.box(AppConstants.expensesBox).clear(); } catch (_) {}
                try { await Hive.box(AppConstants.contributionsBox).clear(); } catch (_) {}
                try { await Hive.box(AppConstants.walletTransactionsBox).clear(); } catch (_) {}
                if (context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('✅ All data deleted successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF00897B),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}




