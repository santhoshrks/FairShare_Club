import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'models/expense_model.dart';
import 'screens/home_screen.dart';
import 'screens/group_detail_screen.dart';
import 'screens/add_group_screen.dart';
import 'screens/add_expense_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'providers/group_provider.dart';
import 'providers/auth_provider.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';
import 'utils/constants.dart';
import 'utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (real-time sync across all devices)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize Hive (used only for device-local settings)
  await Hive.initFlutter();

  // Open all Hive boxes
  await Future.wait([
    Hive.openBox<dynamic>(AppConstants.groupsBox),
    Hive.openBox<dynamic>(AppConstants.membersBox),
    Hive.openBox<dynamic>(AppConstants.expensesBox),
    Hive.openBox<dynamic>(AppConstants.contributionsBox),
    Hive.openBox<dynamic>(AppConstants.walletTransactionsBox),
    Hive.openBox<dynamic>(AppConstants.settingsBox),
  ]);

  // Initialize notifications
  await NotificationService().initialize();

  // Check first launch - request notification permission
  final settingsBox = Hive.box<dynamic>(AppConstants.settingsBox);
  final isFirstLaunch =
      settingsBox.get(AppConstants.firstLaunchKey, defaultValue: true) as bool;
  if (isFirstLaunch) {
    await NotificationService().requestPermission();
    await settingsBox.put(AppConstants.firstLaunchKey, false);
  }

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    const ProviderScope(
      child: _AuthGate(),
    ),
  );
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return MainScaffold(child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HomeScreen(),
          ),
        ),
        GoRoute(
          path: '/groups',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: _AllGroupsScreen(),
          ),
        ),
        GoRoute(
          path: '/history',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HistoryScreen(),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/add-group',
      builder: (context, state) => const AddGroupScreen(),
    ),
    GoRoute(
      path: '/group/:id',
      builder: (context, state) {
        final groupId = state.pathParameters['id']!;
        return GroupDetailScreen(groupId: groupId);
      },
    ),
    GoRoute(
      path: '/group/:id/add-expense',
      builder: (context, state) {
        final groupId = state.pathParameters['id']!;
        final expense = state.extra as ExpenseModel?;
        return AddExpenseScreen(groupId: groupId, existingExpense: expense);
      },
    ),
  ],
);

class FairShareClubApp extends ConsumerWidget {
  const FairShareClubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'FairShare Club',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}

// ─── Auth Gate ───────────────────────────────────────────────────────────────
class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  bool _showLogin = true;
  bool _invitesLinked = false; // run once per app session

  /// Creates (or loads) the current user's member profile and links any
  /// pending group invites.  Resets [_invitesLinked] on failure so the
  /// next build cycle will retry automatically.
  Future<void> _initUserProfile(String displayName) async {
    try {
      await FirestoreService.instance.getOrCreateCurrentUserProfile(
        name: displayName,
        colorHex: AppConstants.avatarColors[0],
      );
    } catch (e) {
      debugPrint('[AuthGate] getOrCreateCurrentUserProfile failed: $e');
      if (mounted) setState(() => _invitesLinked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error: $e')),
      ),
      data: (user) {
        if (user != null) {
          // Ensure pending invites are linked every time the user is active
          if (!_invitesLinked) {
            _invitesLinked = true;
            // Profile creation + invite linking — best-effort with retry.
            _initUserProfile(
              user.displayName ?? user.email?.split('@').first ?? 'User',
            );
          }
          // Logged in — show main app via router
          return MaterialApp.router(
            title: 'FairShare Club',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme(),
            darkTheme: AppTheme.darkTheme(),
            themeMode: ref.watch(themeModeProvider),
            routerConfig: _router,
          );
        }
        // Not logged in — reset so next login re-runs the link
        _invitesLinked = false;
        // Wrap auth screens in MaterialApp
        return MaterialApp(
          title: 'FairShare Club',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          themeMode: ref.watch(themeModeProvider),
          home: _showLogin
              ? LoginScreen(
                  onGoToRegister: () => setState(() => _showLogin = false))
              : RegisterScreen(
                  onGoToLogin: () => setState(() => _showLogin = true)),
        );
      },
    );
  }
}

class MainScaffold extends ConsumerStatefulWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  int _selectedIndex = 0;

  static const _tabs = ['/', '/groups', '/history', '/settings'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
          context.go(_tabs[index]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Groups',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// All Groups screen showing both active and archived
class _AllGroupsScreen extends ConsumerWidget {
  const _AllGroupsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeGroups = ref.watch(activeGroupsProvider);
    final archivedGroups = ref.watch(archivedGroupsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Groups'),
        actions: [
          IconButton(
            onPressed: () => context.push('/add-group'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (activeGroups.isNotEmpty) ...[
            Text('Active (${activeGroups.length})',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 8),
            ...activeGroups.map((g) => _GroupListTile(group: g)),
          ],
          if (archivedGroups.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Archived (${archivedGroups.length})',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 8),
            ...archivedGroups.map((g) => _GroupListTile(group: g, archived: true)),
          ],
          if (activeGroups.isEmpty && archivedGroups.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text('No groups yet',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add-group'),
        icon: const Icon(Icons.add),
        label: const Text('New Group'),
      ),
    );
  }
}

class _GroupListTile extends ConsumerWidget {
  final group;
  final bool archived;

  const _GroupListTile({required this.group, this.archived = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeColor = AppConstants.groupTypeColor(group.type as String);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: typeColor.withAlpha(25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(AppConstants.groupTypeIcon(group.type as String),
              color: typeColor, size: 20),
        ),
        title: Text(group.name as String,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: archived ? TextDecoration.lineThrough : null,
              color: archived ? Colors.grey : null,
            )),
        subtitle: Text(AppConstants.groupTypeLabel(group.type as String),
            style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (archived)
              TextButton(
                onPressed: () => ref
                    .read(groupProvider.notifier)
                    .unarchiveGroup(group.id as String),
                child: const Text('Unarchive',
                    style: TextStyle(fontSize: 12)),
              ),
            const Icon(Icons.arrow_forward_ios, size: 14),
          ],
        ),
        onTap: () => context.push('/group/${group.id}'),
      ),
    );
  }
}
