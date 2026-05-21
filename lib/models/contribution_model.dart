class ContributionModel {
  final String id;
  final String groupId;
  final String memberId;
  final double amount;
  final DateTime date;
  final String note;

  ContributionModel({
    required this.id,
    required this.groupId,
    required this.memberId,
    required this.amount,
    required this.date,
    this.note = '',
  });

  ContributionModel copyWith({
    String? id,
    String? groupId,
    String? memberId,
    double? amount,
    DateTime? date,
    String? note,
  }) {
    return ContributionModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      memberId: memberId ?? this.memberId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'memberId': memberId,
      'amount': amount,
      'date': date.toIso8601String(),
      'note': note,
    };
  }

  factory ContributionModel.fromJson(Map<dynamic, dynamic> json) {
    return ContributionModel(
      id: json['id'] as String,
      groupId: json['groupId'] as String,
      memberId: json['memberId'] as String,
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date'] as String),
      note: json['note'] as String? ?? '',
    );
  }
}

