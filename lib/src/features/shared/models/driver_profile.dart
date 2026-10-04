class DriverProfile {
  const DriverProfile({
    required this.name,
    required this.email,
    this.id,
    this.phone,
    this.role,
    this.createdAt,
  });

  final String? id;
  final String name;
  final String email;
  final String? phone;
  final String? role;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'email': email,
      if (phone != null) 'phone': phone,
      if (role != null) 'role': role,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory DriverProfile.fromJson(
    Map<String, dynamic> json, {
    String? fallbackEmail,
    String? fallbackName,
    String? fallbackPhone,
  }) {
    DateTime? parsedCreatedAt;
    if (json['created_at'] != null) {
      parsedCreatedAt = DateTime.tryParse(json['created_at'].toString());
    }

    final firstName = json['first_name']?.toString().trim();
    final lastName = json['last_name']?.toString().trim();
    final composedName = [
      if (firstName != null && firstName.isNotEmpty) firstName,
      if (lastName != null && lastName.isNotEmpty) lastName,
    ].join(' ').trim();

    final resolvedName = _resolveFirstNonEmpty([
      json['name']?.toString(),
      json['full_name']?.toString(),
      if (composedName.isNotEmpty) composedName,
      json['display_name']?.toString(),
      json['username']?.toString(),
      fallbackName,
    ]);

    final resolvedEmail = _resolveFirstNonEmpty([
      json['email']?.toString(),
      json['user_email']?.toString(),
      json['email_address']?.toString(),
      fallbackEmail,
    ]);

    final resolvedPhone = _resolveFirstNonEmpty([
      json['phone']?.toString(),
      json['mobile']?.toString(),
      json['mobile_number']?.toString(),
      json['phone_number']?.toString(),
      json['telephone']?.toString(),
      fallbackPhone,
    ]);

    final finalEmail = resolvedEmail ?? '';
    final finalName = (resolvedName != null && resolvedName.isNotEmpty)
        ? resolvedName
        : (finalEmail.contains('@') ? _formatNameFromEmail(finalEmail) : 'Driver');

    return DriverProfile(
      id: json['id']?.toString(),
      name: finalName,
      email: finalEmail,
      phone: resolvedPhone,
      role: json['role'] as String? ?? 'driver',
      createdAt: parsedCreatedAt,
    );
  }

  static String? _resolveFirstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  static String _formatNameFromEmail(String email) {
    final prefix = email.split('@').first.replaceAll(RegExp(r'[._\-]'), ' ').trim();
    if (prefix.isEmpty) return 'Driver';
    return prefix
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }
}
