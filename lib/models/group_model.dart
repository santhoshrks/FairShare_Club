class GroupModel {
  final String id;
  final String name;
  final String type; // expenseSplit / poolFund / walletSplit
  final List<String> memberIds;
  final DateTime createdAt;
  final bool isArchived;
  final String description;

  GroupModel({
    required this.id,
    required this.name,
    required this.type,
    required this.memberIds,
    required this.createdAt,
    this.isArchived = false,
    this.description = '',
  });

  GroupModel copyWith({
    String? id,
    String? name,
    String? type,
    List<String>? memberIds,
    DateTime? createdAt,
    bool? isArchived,
    String? description,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt ?? this.createdAt,
      isArchived: isArchived ?? this.isArchived,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'memberIds': memberIds,
      'createdAt': createdAt.toIso8601String(),
      'isArchived': isArchived,
      'description': description,
    };
  }

  factory GroupModel.fromJson(Map<dynamic, dynamic> json) {
    return GroupModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      memberIds: List<String>.from(json['memberIds'] as List),
      createdAt: DateTime.parse(json['createdAt'] as String),
      isArchived: json['isArchived'] as bool? ?? false,
      description: json['description'] as String? ?? '',
    );
  }
}

