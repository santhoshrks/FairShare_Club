class SettlementModel {
  final String id;
  final String groupId;
  final String fromMemberId; // who paid (debtor)
  final String toMemberId;   // who received (creditor)
  final double amount;
  final DateTime date;

  SettlementModel({
    required this.id,
    required this.groupId,
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'fromMemberId': fromMemberId,
        'toMemberId': toMemberId,
        'amount': amount,
        'date': date.toIso8601String(),
      };

  factory SettlementModel.fromJson(Map<dynamic, dynamic> json) =>
      SettlementModel(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        fromMemberId: json['fromMemberId'] as String,
        toMemberId: json['toMemberId'] as String,
        amount: (json['amount'] as num).toDouble(),
        date: DateTime.parse(json['date'] as String),
      );
}

