import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/wallet_transaction_model.dart';
import '../services/firestore_service.dart';
import 'group_provider.dart';

// ─── Wallet Transactions (real-time Firestore stream) ─────────────────────────
class WalletNotifier extends StateNotifier<List<WalletTransactionModel>> {
  WalletNotifier() : super([]) {
    _subscription =
        FirestoreService.instance.walletTxsStream().listen((txs) {
      state = txs;
    });
  }

  StreamSubscription<List<WalletTransactionModel>>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> addTransaction(WalletTransactionModel tx) =>
      FirestoreService.instance.saveWalletTransaction(tx);

  Future<void> deleteTransaction(String id) =>
      FirestoreService.instance.deleteWalletTransaction(id);

  void refresh() {} // no-op: Firestore stream auto-updates
}

final walletProvider =
    StateNotifierProvider<WalletNotifier, List<WalletTransactionModel>>((ref) {
  return WalletNotifier();
});

final walletTxsByGroupProvider =
    Provider.family<List<WalletTransactionModel>, String>((ref, groupId) {
  return ref
      .watch(walletProvider)
      .where((t) => t.groupId == groupId)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
});

// Per member balance: credits - debits
final memberWalletBalanceProvider =
    Provider.family<double, ({String groupId, String memberId})>((ref, args) {
  final txs = ref.watch(walletTxsByGroupProvider(args.groupId));
  final memberTxs = txs.where((t) => t.memberId == args.memberId);
  double balance = 0;
  for (final tx in memberTxs) {
    if (tx.type == 'credit') {
      balance += tx.amount;
    } else {
      balance -= tx.amount;
    }
  }
  return balance;
});

// All member balances for a group: Map<memberId, balance>
final allMemberWalletBalancesProvider =
    Provider.family<Map<String, double>, String>((ref, groupId) {
  final group = ref.watch(groupByIdProvider(groupId));
  if (group == null) return {};
  final Map<String, double> balances = {};
  for (final memberId in group.memberIds) {
    balances[memberId] = ref.watch(
        memberWalletBalanceProvider((groupId: groupId, memberId: memberId)));
  }
  return balances;
});

final totalGroupWalletBalanceProvider =
    Provider.family<double, String>((ref, groupId) {
  final balances = ref.watch(allMemberWalletBalancesProvider(groupId));
  return balances.values.fold(0.0, (sum, b) => sum + b);
});

final walletTxsByMemberProvider = Provider.family<List<WalletTransactionModel>,
    ({String groupId, String memberId})>((ref, args) {
  return ref
      .watch(walletTxsByGroupProvider(args.groupId))
      .where((t) => t.memberId == args.memberId)
      .toList();
});
