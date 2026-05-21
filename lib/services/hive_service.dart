import 'package:hive_flutter/hive_flutter.dart';
import '../models/group_model.dart';
import '../models/member_model.dart';
import '../models/expense_model.dart';
import '../models/contribution_model.dart';
import '../models/wallet_transaction_model.dart';
import '../utils/constants.dart';

class HiveService {
  // Groups
  Box<dynamic> get _groupsBox => Hive.box(AppConstants.groupsBox);
  Box<dynamic> get _membersBox => Hive.box(AppConstants.membersBox);
  Box<dynamic> get _expensesBox => Hive.box(AppConstants.expensesBox);
  Box<dynamic> get _contributionsBox => Hive.box(AppConstants.contributionsBox);
  Box<dynamic> get _walletBox => Hive.box(AppConstants.walletTransactionsBox);
  Box<dynamic> get _settingsBox => Hive.box(AppConstants.settingsBox);

  // ======= GROUPS =======
  Future<void> saveGroup(GroupModel group) async {
    await _groupsBox.put(group.id, group.toJson());
  }

  List<GroupModel> getAllGroups() {
    return _groupsBox.values
        .map((v) => GroupModel.fromJson(v as Map))
        .toList();
  }

  GroupModel? getGroup(String id) {
    final data = _groupsBox.get(id);
    if (data == null) return null;
    return GroupModel.fromJson(data as Map);
  }

  Future<void> deleteGroup(String id) async {
    await _groupsBox.delete(id);
  }

  // ======= MEMBERS =======
  Future<void> saveMember(MemberModel member) async {
    await _membersBox.put(member.id, member.toJson());
  }

  List<MemberModel> getAllMembers() {
    return _membersBox.values
        .map((v) => MemberModel.fromJson(v as Map))
        .toList();
  }

  MemberModel? getMember(String id) {
    final data = _membersBox.get(id);
    if (data == null) return null;
    return MemberModel.fromJson(data as Map);
  }

  List<MemberModel> getMembersByIds(List<String> ids) {
    return ids
        .map((id) => getMember(id))
        .where((m) => m != null)
        .cast<MemberModel>()
        .toList();
  }

  Future<void> deleteMember(String id) async {
    await _membersBox.delete(id);
  }

  // ======= EXPENSES =======
  Future<void> saveExpense(ExpenseModel expense) async {
    await _expensesBox.put(expense.id, expense.toJson());
  }

  List<ExpenseModel> getAllExpenses() {
    return _expensesBox.values
        .map((v) => ExpenseModel.fromJson(v as Map))
        .toList();
  }

  List<ExpenseModel> getExpensesByGroup(String groupId) {
    return _expensesBox.values
        .where((v) => (v as Map)['groupId'] == groupId)
        .map((v) => ExpenseModel.fromJson(v as Map))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  ExpenseModel? getExpense(String id) {
    final data = _expensesBox.get(id);
    if (data == null) return null;
    return ExpenseModel.fromJson(data as Map);
  }

  Future<void> deleteExpense(String id) async {
    await _expensesBox.delete(id);
  }

  // ======= CONTRIBUTIONS =======
  Future<void> saveContribution(ContributionModel contribution) async {
    await _contributionsBox.put(contribution.id, contribution.toJson());
  }

  List<ContributionModel> getAllContributions() {
    return _contributionsBox.values
        .map((v) => ContributionModel.fromJson(v as Map))
        .toList();
  }

  List<ContributionModel> getContributionsByGroup(String groupId) {
    return _contributionsBox.values
        .where((v) => (v as Map)['groupId'] == groupId)
        .map((v) => ContributionModel.fromJson(v as Map))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> deleteContribution(String id) async {
    await _contributionsBox.delete(id);
  }

  // ======= WALLET TRANSACTIONS =======
  Future<void> saveWalletTransaction(WalletTransactionModel tx) async {
    await _walletBox.put(tx.id, tx.toJson());
  }

  List<WalletTransactionModel> getAllWalletTransactions() {
    return _walletBox.values
        .map((v) => WalletTransactionModel.fromJson(v as Map))
        .toList();
  }

  List<WalletTransactionModel> getWalletTransactionsByGroup(String groupId) {
    return _walletBox.values
        .where((v) => (v as Map)['groupId'] == groupId)
        .map((v) => WalletTransactionModel.fromJson(v as Map))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<WalletTransactionModel> getWalletTransactionsByMember(
      String groupId, String memberId) {
    return _walletBox.values
        .where((v) =>
            (v as Map)['groupId'] == groupId && (v)['memberId'] == memberId)
        .map((v) => WalletTransactionModel.fromJson(v as Map))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> deleteWalletTransaction(String id) async {
    await _walletBox.delete(id);
  }

  // ======= SETTINGS =======
  dynamic getSetting(String key, {dynamic defaultValue}) {
    return _settingsBox.get(key, defaultValue: defaultValue);
  }

  Future<void> saveSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  // ======= CLEANUP =======
  Future<void> deleteGroupData(String groupId) async {
    // Delete all expenses for the group
    final expenseKeys = _expensesBox.keys
        .where((k) => (_expensesBox.get(k) as Map?)?['groupId'] == groupId)
        .toList();
    for (final key in expenseKeys) {
      await _expensesBox.delete(key);
    }

    // Delete all contributions for the group
    final contribKeys = _contributionsBox.keys
        .where((k) =>
            (_contributionsBox.get(k) as Map?)?['groupId'] == groupId)
        .toList();
    for (final key in contribKeys) {
      await _contributionsBox.delete(key);
    }

    // Delete all wallet transactions for the group
    final walletKeys = _walletBox.keys
        .where((k) => (_walletBox.get(k) as Map?)?['groupId'] == groupId)
        .toList();
    for (final key in walletKeys) {
      await _walletBox.delete(key);
    }

    await deleteGroup(groupId);
  }
}

