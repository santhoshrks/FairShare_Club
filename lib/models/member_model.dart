class MemberModel {
  final String id;
  final String name;
  final String email; // used for login & member lookup
  final String phone;
  final String colorHex;
  final DateTime createdAt;

  MemberModel({
    required this.id,
    required this.name,
    this.email = '',
    this.phone = '',
    required this.colorHex,
    required this.createdAt,
  });

  MemberModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? colorHex,
    DateTime? createdAt,
  }) {
    return MemberModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'colorHex': colorHex,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MemberModel.fromJson(Map<dynamic, dynamic> json) {
    return MemberModel(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      colorHex: json['colorHex'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
