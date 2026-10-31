/// Data models for SafeHer entities.

// ──── User Model ────
class UserModel {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? profileImage;
  final List<EmergencyContact> emergencyContacts;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.profileImage,
    this.emergencyContacts = const [],
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final email = (json['email'] ?? json['_email'] ?? '') as String;
    final rawName = json['name'] as String?;
    final fallbackName = email.isNotEmpty && email.contains('@')
        ? email.split('@').first
        : 'SafeHer User';

    return UserModel(
      id: json['id'] ?? json['_id'] ?? '',
      name: (rawName != null && rawName.trim().isNotEmpty) ? rawName.trim() : fallbackName,
      email: email,
      phone: json['phone'],
      profileImage: json['profileImage'],
      emergencyContacts: (json['emergencyContacts'] as List<dynamic>?)
              ?.map((e) => EmergencyContact.fromJson(e))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'phone': phone,
    'profileImage': profileImage,
  };
}

// ──── Emergency Contact ────
class EmergencyContact {
  final String? id;
  final String name;
  final String phone;
  final String? relation;

  EmergencyContact({
    this.id,
    required this.name,
    required this.phone,
    this.relation,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] ?? json['_id'],
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      relation: json['relation'],
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'relation': relation,
  };
}

// ──── Alert Model ────
class AlertModel {
  final String id;
  final String userId;
  final String type;
  final AlertLocation location;
  final String status;
  final double? confidence;
  final List<String> evidenceUrls;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  AlertModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.location,
    required this.status,
    this.confidence,
    this.evidenceUrls = const [],
    required this.createdAt,
    this.resolvedAt,
  });

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    final rawEvidences = json['evidenceUrls'] ?? json['evidence_urls'];
    List<String> evidences = [];
    if (rawEvidences is List) {
      evidences = rawEvidences.map((e) => e.toString()).toList();
    }

    final rawCreatedAt = json['createdAt'] ?? json['created_at'];
    DateTime created;
    if (rawCreatedAt != null) {
      try {
        created = DateTime.parse(rawCreatedAt.toString());
      } catch (_) {
        created = DateTime.now();
      }
    } else {
      created = DateTime.now();
    }

    final rawResolvedAt = json['resolvedAt'] ?? json['resolved_at'];
    DateTime? resolved;
    if (rawResolvedAt != null) {
      try {
        resolved = DateTime.parse(rawResolvedAt.toString());
      } catch (_) {}
    }

    return AlertModel(
      id: json['id'] ?? json['_id'] ?? '',
      userId: json['userId'] ?? json['user_id'] ?? '',
      type: json['type'] ?? '',
      location: AlertLocation.fromJson(json['location'] ?? {}),
      status: json['status'] ?? 'triggered',
      confidence: (json['confidence'] as num?)?.toDouble(),
      evidenceUrls: evidences,
      createdAt: created,
      resolvedAt: resolved,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'type': type,
    'location': location.toJson(),
    'status': status,
    'confidence': confidence,
    'evidenceUrls': evidenceUrls,
    'createdAt': createdAt.toIso8601String(),
    if (resolvedAt != null) 'resolvedAt': resolvedAt!.toIso8601String(),
  };

  /// Human-readable alert type
  String get typeLabel {
    switch (type) {
      case 'scream': return 'Scream Detected';
      case 'fall': return 'Fall Detected';
      case 'panic_button': return 'Panic Button';
      case 'emotion': return 'Distress Emotion';
      default: return 'Manual SOS';
    }
  }

  /// Icon for alert type
  String get typeEmoji {
    switch (type) {
      case 'scream': return '🔊';
      case 'fall': return '⚠️';
      case 'panic_button': return '🆘';
      case 'emotion': return '😰';
      default: return '🚨';
    }
  }
}

// ──── Location sub-model ────
class AlertLocation {
  final double latitude;
  final double longitude;
  final String? address;

  AlertLocation({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  factory AlertLocation.fromJson(Map<String, dynamic> json) {
    return AlertLocation(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      address: json['address'],
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'address': address,
  };

  /// Google Maps link for sharing
  String get mapsLink =>
      'https://maps.google.com/?q=$latitude,$longitude';
}
