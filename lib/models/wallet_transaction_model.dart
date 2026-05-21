class WalletTransactionModel {
  final String id;
  final String groupId;
  final String memberId;
  final double amount;
  final String type; // credit / debit
  final String description;
  final DateTime date;

  WalletTransactionModel({
    required this.id,
    required this.groupId,
    required this.memberId,
    required this.amount,
    required this.type,
    required this.description,
    required this.date,
  });

  WalletTransactionModel copyWith({
    String? id,
    String? groupId,
    String? memberId,
    double? amount,
    String? type,
    String? description,
    DateTime? date,
  }) {
    return WalletTransactionModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      memberId: memberId ?? this.memberId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      description: description ?? this.description,
      date: date ?? this.date,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'memberId': memberId,
      'amount': amount,
      'type': type,
      'description': description,
      'date': date.toIso8601String(),
    };
  }

  factory WalletTransactionModel.fromJson(Map<dynamic, dynamic> json) {
    return WalletTransactionModel(
      id: json['id'] as String,
      groupId: json['groupId'] as String,
      memberId: json['memberId'] as String,
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] as String,
      description: json['description'] as String,
      date: DateTime.parse(json['date'] as String),
    );
  }
}

