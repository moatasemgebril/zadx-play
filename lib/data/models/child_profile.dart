import 'dart:math';

import 'package:flutter/foundation.dart';

/// Built-in avatars. Children never upload photos (COPPA / GDPR-K data minimisation).
enum ChildAvatar { star, moon, sun, rocket, flower, kitten }

/// A child in the family. Deliberately minimal: an opaque id, a nickname and a
/// built-in avatar. No birthdate, photo, last name or any other personal data.
@immutable
class ChildProfile {
  const ChildProfile({required this.id, required this.nickname, this.avatar = ChildAvatar.star});

  /// Id of the first child. Existing single-child data (local and in Firestore
  /// under `children/child-1`) belongs to this child.
  static const defaultId = 'child-1';

  static const maxNicknameLength = 20;

  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,40}$');
  static final _controlChars = RegExp(r'[\u0000-\u001F\u007F-\u009F​-‏‪-‮⁦-⁩]');
  static final _spaces = RegExp(r'\s+');
  static final _longNumber = RegExp(r'\d{4,}');

  final String id;

  /// May be empty only for the migrated default child; the UI then shows a
  /// localized fallback ("My child").
  final String nickname;
  final ChildAvatar avatar;

  static bool isValidId(String id) => _idPattern.hasMatch(id);

  /// Returns a cleaned nickname, or null when it is empty or looks like
  /// contact details (e-mail, phone number) that we must not collect.
  static String? cleanNickname(String raw) {
    final collapsed = raw.replaceAll(_controlChars, '').replaceAll(_spaces, ' ').trim();
    if (collapsed.isEmpty) return null;
    if (collapsed.contains('@') || _longNumber.hasMatch(collapsed)) return null;
    final runes = collapsed.runes.toList();
    if (runes.length <= maxNicknameLength) return collapsed;
    return String.fromCharCodes(runes.take(maxNicknameLength)).trim();
  }

  static ChildAvatar avatarByName(String? name) =>
      ChildAvatar.values.where((a) => a.name == name).firstOrNull ?? ChildAvatar.star;

  /// Random, non-guessable id that carries no personal information.
  static String newId([Random? random]) {
    final r = random ?? Random.secure();
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return 'c${List.generate(12, (_) => alphabet[r.nextInt(alphabet.length)]).join()}';
  }

  ChildProfile copyWith({String? nickname, ChildAvatar? avatar}) =>
      ChildProfile(id: id, nickname: nickname ?? this.nickname, avatar: avatar ?? this.avatar);

  Map<String, dynamic> toJson() => {'id': id, 'nickname': nickname, 'avatar': avatar.name};

  /// Returns null for malformed entries instead of throwing.
  static ChildProfile? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String || !isValidId(id)) return null;
    final rawName = j['nickname'];
    final nickname = rawName is String ? (cleanNickname(rawName) ?? '') : '';
    return ChildProfile(id: id, nickname: nickname, avatar: avatarByName(j['avatar'] as String?));
  }

  @override
  bool operator ==(Object other) =>
      other is ChildProfile && other.id == id && other.nickname == nickname && other.avatar == avatar;

  @override
  int get hashCode => Object.hash(id, nickname, avatar);
}

/// Plan limit check (Basic = 2, Plus = 5 — see `PlanPricing.maxChildren`).
bool canAddChild({required int currentCount, required int maxChildren}) => currentCount < maxChildren;
