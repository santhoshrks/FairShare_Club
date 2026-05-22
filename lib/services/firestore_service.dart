import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/group_model.dart';
import '../models/member_model.dart';
import '../models/expense_model.dart';
import '../models/contribution_model.dart';
import '../models/wallet_transaction_model.dart';
import '../models/settlement_model.dart';

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
  CollectionReference<Map<String, dynamic>> get _settlements =>
      _db.collection('settlements');

  // ─── GROUPS (filtered by current user — by uid OR by email) ─────────────────
  Stream<List<GroupModel>> groupsStream() {
    final uid = currentUid;
    final email = (_auth.currentUser?.email ?? '').toLowerCase();
    if (uid == null) return const Stream.empty();

    // Stream 1: groups where the user's UID is already in memberIds
    final byUid = _groups
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .map((s) => s.docs.map((d) => GroupModel.fromJson(d.data())).toList());

    if (email.isEmpty) {
      return byUid.map((list) =>
          list..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    }

    // Stream 2: groups where the user's email is in memberEmails
    // (covers invited-but-not-yet-migrated members)
    final byEmail = _groups
        .where('memberEmails', arrayContains: email)
        .snapshots()
        .map((s) => s.docs.map((d) => GroupModel.fromJson(d.data())).toList());

    // Merge both streams, deduplicate by group id
    return _mergeGroupStreams(byUid, byEmail);
  }

  Stream<List<GroupModel>> _mergeGroupStreams(
    Stream<List<GroupModel>> a,
    Stream<List<GroupModel>> b,
  ) {
    final controller = StreamController<List<GroupModel>>();
    List<GroupModel> latestA = [];
    List<GroupModel> latestB = [];

    void emit() {
      final merged = {
        for (final g in [...latestA, ...latestB]) g.id: g
      }.values.toList()
        ..sort((x, y) => y.createdAt.compareTo(x.createdAt));
      if (!controller.isClosed) controller.add(merged);
    }

    StreamSubscription? subA, subB;
    subA = a.listen((list) { latestA = list; emit(); },
        onError: controller.addError);
    subB = b.listen((list) { latestB = list; emit(); },
        onError: controller.addError);

    controller.onCancel = () {
      subA?.cancel();
      subB?.cancel();
    };
    return controller.stream;
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
  /// If a placeholder member (created via invite before registration) exists
  /// with the same email, it is automatically linked to the real Auth UID
  /// and all group memberships / expenses / contributions are migrated.
  Future<MemberModel> getOrCreateCurrentUserProfile({
    required String name,
    required String colorHex,
  }) async {
    final user = _auth.currentUser!;
    final doc = await _members.doc(user.uid).get();
    if (doc.exists) {
      // Profile exists — still check for any NEW pending invites
      await linkPendingInvites();
      return MemberModel.fromJson(doc.data()!);
    }

    // New user — check for a placeholder created when they were invited
    final email = (user.email ?? '').toLowerCase();
    MemberModel? placeholder;
    if (email.isNotEmpty) {
      final snap = await _members
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty && snap.docs.first.id != user.uid) {
        placeholder = MemberModel.fromJson(snap.docs.first.data());
      }
    }

    final member = MemberModel(
      id: user.uid,
      name: placeholder != null ? placeholder.name : name,
      email: email,
      phone: placeholder?.phone ?? '',
      colorHex: placeholder != null ? placeholder.colorHex : colorHex,
      createdAt: placeholder?.createdAt ?? DateTime.now(),
    );
    await saveMember(member);

    // Migrate placeholder data to the real Auth UID
    if (placeholder != null) {
      await _migratePlaceholder(oldId: placeholder.id, newId: user.uid);
    }

    return member;
  }

  /// Check for ANY placeholder members matching the current user's email
  /// (created after their registration) and migrate them.
  /// Safe to call on every login — no-op if nothing to migrate.
  Future<void> linkPendingInvites() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final email = (user.email ?? '').toLowerCase();
    if (email.isEmpty) return;

    // Find groups where the user's email is listed (invited but not yet linked)
    // This query is allowed by Firestore rules via memberEmails field.
    final groupSnap = await _groups
        .where('memberEmails', arrayContains: email)
        .get();

    if (groupSnap.docs.isEmpty) return;

    // Find placeholder member with same email but different ID
    final memberSnap = await _members
        .where('email', isEqualTo: email)
        .get();
    final placeholders =
        memberSnap.docs.where((d) => d.id != user.uid).toList();

    for (final gdoc in groupSnap.docs) {
      final data = Map<String, dynamic>.from(gdoc.data());
      final ids = List<String>.from(data['memberIds'] as List? ?? []);
      final emails = List<String>.from(data['memberEmails'] as List? ?? []);
      bool changed = false;

      // Replace any placeholder UUID with the real UID
      for (final ph in placeholders) {
        final idx = ids.indexOf(ph.id);
        if (idx >= 0) {
          ids[idx] = user.uid;
          changed = true;
        }
      }

      // Ensure real UID is in memberIds
      if (!ids.contains(user.uid)) {
        ids.add(user.uid);
        changed = true;
      }

      // Remove email from memberEmails (UID is now properly set)
      final emailIdx = emails.indexOf(email);
      if (emailIdx >= 0) {
        emails.removeAt(emailIdx);
        changed = true;
      }

      if (changed) {
        await gdoc.reference
            .update({'memberIds': ids, 'memberEmails': emails});
      }
    }

    // Migrate related data (expenses, contributions, etc.) for each placeholder
    for (final ph in placeholders) {
      await _migratePlaceholder(oldId: ph.id, newId: user.uid);
    }
  }

  /// Replace every occurrence of [oldId] with [newId] across all collections.
  Future<void> _migratePlaceholder({
    required String oldId,
    required String newId,
  }) async {
    // 1. Groups — update memberIds arrays
    final groupSnap =
        await _groups.where('memberIds', arrayContains: oldId).get();
    for (final gdoc in groupSnap.docs) {
      final data = gdoc.data();
      final ids = List<String>.from(data['memberIds'] as List);
      final idx = ids.indexOf(oldId);
      if (idx >= 0) ids[idx] = newId;
      await gdoc.reference.update({'memberIds': ids});
    }

    // 2. Expenses — query by paidByMemberId and by splitAmongMemberIds
    if (groupSnap.docs.isNotEmpty) {
      final paidBySnap = await _expenses
          .where('paidByMemberId', isEqualTo: oldId)
          .get();
      final splitSnap = await _expenses
          .where('splitAmongMemberIds', arrayContains: oldId)
          .get();
      // Merge unique docs
      final expDocs = {
        for (final d in [...paidBySnap.docs, ...splitSnap.docs]) d.id: d
      }.values;
      for (final edoc in expDocs) {
        final data = Map<String, dynamic>.from(edoc.data());
        bool changed = false;
        if (data['paidByMemberId'] == oldId) {
          data['paidByMemberId'] = newId;
          changed = true;
        }
        final splits =
            List<String>.from(data['splitAmongMemberIds'] as List? ?? []);
        final idx = splits.indexOf(oldId);
        if (idx >= 0) {
          splits[idx] = newId;
          data['splitAmongMemberIds'] = splits;
          changed = true;
        }
        final custom = Map<String, dynamic>.from(
            data['customSplitAmounts'] as Map? ?? {});
        if (custom.containsKey(oldId)) {
          custom[newId] = custom.remove(oldId);
          data['customSplitAmounts'] = custom;
          changed = true;
        }
        if (changed) await edoc.reference.update(data);
      }
    }

    // 3. Contributions
    final contribSnap =
        await _contributions.where('memberId', isEqualTo: oldId).get();
    for (final cdoc in contribSnap.docs) {
      await cdoc.reference.update({'memberId': newId});
    }

    // 4. Wallet transactions
    final walletSnap =
        await _walletTxs.where('memberId', isEqualTo: oldId).get();
    for (final wdoc in walletSnap.docs) {
      await wdoc.reference.update({'memberId': newId});
    }

    // 5. Settlements
    final settleFromSnap =
        await _settlements.where('fromMemberId', isEqualTo: oldId).get();
    for (final sdoc in settleFromSnap.docs) {
      await sdoc.reference.update({'fromMemberId': newId});
    }
    final settleToSnap =
        await _settlements.where('toMemberId', isEqualTo: oldId).get();
    for (final sdoc in settleToSnap.docs) {
      await sdoc.reference.update({'toMemberId': newId});
    }

    // 6. Delete the old placeholder member document
    await _members.doc(oldId).delete();
  }

  // ─── EXPENSES ────────────────────────────────────────────────────────────

  /// Global stream (all expenses) — kept for backwards compat / migration.
  Stream<List<ExpenseModel>> expensesStream() {
    return _expenses.snapshots().map((snap) =>
        snap.docs.map((d) => ExpenseModel.fromJson(d.data())).toList()
          ..sort((a, b) => b.date.compareTo(a.date)));
  }

  /// Per-group real-time stream. Filters at the Firestore level so every
  /// member of the group gets instant push updates when any expense changes.
  Stream<List<ExpenseModel>> expensesByGroupStream(String groupId) {
    return _expenses
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snap) =>
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

  /// Per-group real-time contributions stream.
  Stream<List<ContributionModel>> contributionsByGroupStream(String groupId) {
    return _contributions
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snap) =>
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

  /// Per-group real-time wallet transactions stream.
  Stream<List<WalletTransactionModel>> walletTxsByGroupStream(String groupId) {
    return _walletTxs
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => WalletTransactionModel.fromJson(d.data()))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date)));
  }

  Future<void> saveWalletTransaction(WalletTransactionModel tx) =>
      _walletTxs.doc(tx.id).set(tx.toJson());

  Future<void> deleteWalletTransaction(String id) =>
      _walletTxs.doc(id).delete();

  // ─── SETTLEMENTS ──────────────────────────────────────────────────────────

  Stream<List<SettlementModel>> settlementsStream() {
    return _settlements.snapshots().map((snap) => snap.docs
        .map((d) => SettlementModel.fromJson(d.data()))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date)));
  }

  /// Per-group real-time settlements stream.
  Stream<List<SettlementModel>> settlementsByGroupStream(String groupId) {
    return _settlements
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => SettlementModel.fromJson(d.data()))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date)));
  }

  Future<void> saveSettlement(SettlementModel s) =>
      _settlements.doc(s.id).set(s.toJson());

  Future<void> deleteSettlement(String id) => _settlements.doc(id).delete();

  // ─── USER CONTACTS ──────────────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> _contactsCol(String uid) =>
      _db.collection('user_contacts').doc(uid).collection('contacts');

  /// Save/update a member as a contact for the currently signed-in user.
  Future<void> saveUserContact(MemberModel contact) async {
    final uid = currentUid;
    if (uid == null) return;
    final docId = contact.email.isNotEmpty ? contact.email : contact.id;
    await _contactsCol(uid).doc(docId).set(contact.toJson());
  }

  /// Real-time stream of the current user's saved contacts, sorted by name.
  Stream<List<MemberModel>> userContactsStream() {
    final uid = currentUid;
    if (uid == null) return const Stream.empty();
    return _contactsCol(uid).snapshots().map(
          (s) => s.docs
              .map((d) => MemberModel.fromJson(d.data()))
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name)),
        );
  }

  /// Delete ALL groups (and their expenses/contributions/etc.) for the
  /// currently logged-in user. Used by "Clear All Data" in Settings.
  Future<void> clearAllUserData() async {
    final uid = currentUid;
    if (uid == null) return;

    // Find every group this user is in (by UID or by email)
    final email = (_auth.currentUser?.email ?? '').toLowerCase();
    final byUid =
        await _groups.where('memberIds', arrayContains: uid).get();
    final byEmail = email.isNotEmpty
        ? await _groups.where('memberEmails', arrayContains: email).get()
        : null;

    final allGroupIds = {
      for (final d in byUid.docs) d.id,
      if (byEmail != null)
        for (final d in byEmail.docs) d.id,
    };

    // Delete each group and all its sub-data
    for (final groupId in allGroupIds) {
      await deleteGroupData(groupId);
    }
  }
  /// Deletes the group document immediately, then cleans up all associated
  /// sub-data (expenses, contributions, wallet-txs, settlements) in a
  /// best-effort batch so that a transient permission error on sub-data
  /// never blocks the group from being removed from the UI.
  Future<void> deleteGroupData(String groupId) async {
    // 1. Delete the group document first — triggers real-time stream instantly
    await _groups.doc(groupId).delete();

    // 2. Best-effort: remove all sub-data (ignore individual failures)
    try {
      final results = await Future.wait([
        _expenses.where('groupId', isEqualTo: groupId).get(),
        _contributions.where('groupId', isEqualTo: groupId).get(),
        _walletTxs.where('groupId', isEqualTo: groupId).get(),
        _settlements.where('groupId', isEqualTo: groupId).get(),
      ]);
      final allDocs = results.expand((s) => s.docs).toList();
      // Firestore batch limit is 500 ops — chunk if necessary
      for (var i = 0; i < allDocs.length; i += 490) {
        final batch = _db.batch();
        final chunk = allDocs.sublist(
            i, (i + 490).clamp(0, allDocs.length));
        for (final doc in chunk) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (_) {
      // Sub-data cleanup failure is non-critical — group is already deleted
    }
  }
}
