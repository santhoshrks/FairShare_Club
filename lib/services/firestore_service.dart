import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/group_model.dart';
import '../models/member_model.dart';
import '../models/expense_model.dart';
import '../models/contribution_model.dart';
import '../models/wallet_transaction_model.dart';

class FirestoreService {
  static final FirestoreService instance = FirestoreService._();
  FirestoreService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get currentUid => _auth.currentUser?.uid;

  // ─── Collection references ───────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('groups');
  CollectionReference<Map<String, dynamic>> get _members =>
      _db.collection('members');
  CollectionReference<Map<String, dynamic>> get _expenses =>
      _db.collection('expenses');
  CollectionReference<Map<String, dynamic>> get _contributions =>
      _db.collection('contributions');
  CollectionReference<Map<String, dynamic>> get _walletTxs =>
      _db.collection('wallet_transactions');

  // ─── GROUPS (filtered by current user) ───────────────────────────────────
  Stream<List<GroupModel>> groupsStream() {
    final uid = currentUid;
    if (uid == null) return const Stream.empty();
    return _groups
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => GroupModel.fromJson(d.data())).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Future<void> saveGroup(GroupModel group) =>
      _groups.doc(group.id).set(group.toJson());

  Future<void> deleteGroup(String id) => _groups.doc(id).delete();

  // ─── MEMBERS ─────────────────────────────────────────────────────────────
  Stream<List<MemberModel>> membersStream() {
    return _members.snapshots().map((snap) =>
        snap.docs.map((d) => MemberModel.fromJson(d.data())).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
  }

  Future<void> saveMember(MemberModel member) =>
      _members.doc(member.id).set(member.toJson());

  Future<void> deleteMember(String id) => _members.doc(id).delete();

  /// Look up a member by email. Returns null if not registered yet.
  Future<MemberModel?> getMemberByEmail(String email) async {
    final snap = await _members
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return MemberModel.fromJson(snap.docs.first.data());
  }

  /// Get or create the profile for the currently logged-in user.
  Future<MemberModel> getOrCreateCurrentUserProfile({
    required String name,
    required String colorHex,
  }) async {
    final user = _auth.currentUser!;
    final doc = await _members.doc(user.uid).get();
    if (doc.exists) return MemberModel.fromJson(doc.data()!);
    final member = MemberModel(
      id: user.uid,
      name: name,
      email: (user.email ?? '').toLowerCase(),
      colorHex: colorHex,
      createdAt: DateTime.now(),
    );
    await saveMember(member);
    return member;
  }

  // ─── EXPENSES ────────────────────────────────────────────────────────────
  Stream<List<ExpenseModel>> expensesStream() {
    return _expenses.snapshots().map((snap) =>
        snap.docs.map((d) => ExpenseModel.fromJson(d.data())).toList()
          ..sort((a, b) => b.date.compareTo(a.date)));
  }

  Future<void> saveExpense(ExpenseModel expense) =>
      _expenses.doc(expense.id).set(expense.toJson());

  Future<void> deleteExpense(String id) => _expenses.doc(id).delete();

  // ─── CONTRIBUTIONS ────────────────────────────────────────────────────────
  Stream<List<ContributionModel>> contributionsStream() {
    return _contributions.snapshots().map((snap) =>
        snap.docs.map((d) => ContributionModel.fromJson(d.data())).toList()
          ..sort((a, b) => b.date.compareTo(a.date)));
  }

  Future<void> saveContribution(ContributionModel contribution) =>
      _contributions.doc(contribution.id).set(contribution.toJson());

  Future<void> deleteContribution(String id) =>
      _contributions.doc(id).delete();

  // ─── WALLET TRANSACTIONS ──────────────────────────────────────────────────
  Stream<List<WalletTransactionModel>> walletTxsStream() {
    return _walletTxs.snapshots().map((snap) =>
        snap.docs
            .map((d) => WalletTransactionModel.fromJson(d.data()))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date)));
  }

  Future<void> saveWalletTransaction(WalletTransactionModel tx) =>
      _walletTxs.doc(tx.id).set(tx.toJson());

  Future<void> deleteWalletTransaction(String id) =>
      _walletTxs.doc(id).delete();

  // ─── CLEANUP ─────────────────────────────────────────────────────────────
  Future<void> deleteGroupData(String groupId) async {
    final futures = await Future.wait([
      _expenses.where('groupId', isEqualTo: groupId).get(),
      _contributions.where('groupId', isEqualTo: groupId).get(),
      _walletTxs.where('groupId', isEqualTo: groupId).get(),
    ]);
    final batch = _db.batch();
    for (final snap in futures) {
      for (final doc in snap.docs) batch.delete(doc.reference);
    }
    batch.delete(_groups.doc(groupId));
    await batch.commit();
  }
}
