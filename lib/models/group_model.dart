class GroupModel {
  final String id;
  final String name;
  final String type; // expenseSplit / poolFund / walletSplit
  final List<String> memberIds;
  /// Emails of invited members — used so a user can find groups by email
  /// before their UID is properly linked (e.g. invited before registration).
  final List<String> memberEmails;
  final DateTime createdAt;
  final bool isArchived;
  final String description;
  /// List of "YYYY-MM" month keys where contributions are closed (pool fund only).
  final List<String> poolContributionClosedMonths;

  GroupModel({
    required this.id,
    required this.name,
    required this.type,
    required this.memberIds,
    this.memberEmails = const [],
    required this.createdAt,
    this.isArchived = false,
    this.description = '',
    this.poolContributionClosedMonths = const [],
  });

  GroupModel copyWith({
    String? id,
    String? name,
    String? type,
    List<String>? memberIds,
    List<String>? memberEmails,
    DateTime? createdAt,
    bool? isArchived,
    String? description,
    List<String>? poolContributionClosedMonths,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      memberIds: memberIds ?? this.memberIds,
      memberEmails: memberEmails ?? this.memberEmails,
      createdAt: createdAt ?? this.createdAt,
      isArchived: isArchived ?? this.isArchived,
      description: description ?? this.description,
      poolContributionClosedMonths:
          poolContributionClosedMonths ?? this.poolContributionClosedMonths,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'memberIds': memberIds,
      'memberEmails': memberEmails,
      'createdAt': createdAt.toIso8601String(),
      'isArchived': isArchived,
      'description': description,
      'poolContributionClosedMonths': poolContributionClosedMonths,
    };
  }

  factory GroupModel.fromJson(Map<dynamic, dynamic> json) {
    return GroupModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      memberIds: List<String>.from(json['memberIds'] as List),
      memberEmails: List<String>.from(json['memberEmails'] as List? ?? []),
      createdAt: DateTime.parse(json['createdAt'] as String),
      isArchived: json['isArchived'] as bool? ?? false,
      description: json['description'] as String? ?? '',
      poolContributionClosedMonths:
          List<String>.from(json['poolContributionClosedMonths'] as List? ?? []),
    );
  }
}
