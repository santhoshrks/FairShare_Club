class ExpenseModel {
  final String id;
  final String groupId;
  final String description;
  final double amount;
  final String paidByMemberId;
  final List<String> splitAmongMemberIds;
  final Map<String, double> customSplitAmounts;
  final String splitType; // equal / custom / percentage
  final DateTime date;
  final String category; // food/travel/shopping/rent/other

  ExpenseModel({
    required this.id,
    required this.groupId,
    required this.description,
    required this.amount,
    required this.paidByMemberId,
    required this.splitAmongMemberIds,
    this.customSplitAmounts = const {},
    this.splitType = 'equal',
    required this.date,
    this.category = 'other',
  });

  ExpenseModel copyWith({
    String? id,
    String? groupId,
    String? description,
    double? amount,
    String? paidByMemberId,
    List<String>? splitAmongMemberIds,
    Map<String, double>? customSplitAmounts,
    String? splitType,
    DateTime? date,
    String? category,
  }) {
    return ExpenseModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      paidByMemberId: paidByMemberId ?? this.paidByMemberId,
      splitAmongMemberIds: splitAmongMemberIds ?? this.splitAmongMemberIds,
      customSplitAmounts: customSplitAmounts ?? this.customSplitAmounts,
      splitType: splitType ?? this.splitType,
      date: date ?? this.date,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'description': description,
      'amount': amount,
      'paidByMemberId': paidByMemberId,
      'splitAmongMemberIds': splitAmongMemberIds,
      'customSplitAmounts': customSplitAmounts,
      'splitType': splitType,
      'date': date.toIso8601String(),
      'category': category,
    };
  }

  factory ExpenseModel.fromJson(Map<dynamic, dynamic> json) {
    final rawCustom = json['customSplitAmounts'];
    Map<String, double> customSplit = {};
    if (rawCustom != null) {
      (rawCustom as Map).forEach((k, v) {
        customSplit[k.toString()] = (v as num).toDouble();
      });
    }
    return ExpenseModel(
      id: json['id'] as String,
      groupId: json['groupId'] as String,
      description: json['description'] as String,
      amount: (json['amount'] as num).toDouble(),
      paidByMemberId: json['paidByMemberId'] as String,
      splitAmongMemberIds: List<String>.from(json['splitAmongMemberIds'] as List),
      customSplitAmounts: customSplit,
      splitType: json['splitType'] as String? ?? 'equal',
      date: DateTime.parse(json['date'] as String),
      category: json['category'] as String? ?? 'other',
    );
  }
}

