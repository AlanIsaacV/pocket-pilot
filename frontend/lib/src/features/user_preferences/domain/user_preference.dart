import 'package:pocket_pilot/src/generated/pocket_pilot/v1/user_preferences_service.pbgrpc.dart'
    as pb;

class UserPreferenceModel {
  final String prefKey;
  final String prefValue;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const UserPreferenceModel({
    required this.prefKey,
    required this.prefValue,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory UserPreferenceModel.fromProto(pb.UserPreference proto) {
    return UserPreferenceModel(
      prefKey: proto.prefKey,
      prefValue: proto.prefValue,
      createdAt: proto.createdAt.toDateTime().toUtc(),
      updatedAt: proto.updatedAt.toDateTime().toUtc(),
      deletedAt: proto.hasDeletedAt()
          ? proto.deletedAt.toDateTime().toUtc()
          : null,
    );
  }

  factory UserPreferenceModel.fromMap(Map<String, dynamic> map) {
    return UserPreferenceModel(
      prefKey: map['pref_key'] as String,
      prefValue: map['pref_value'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'pref_key': prefKey,
      'pref_value': prefValue,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toServerMap() => toMap();
}
