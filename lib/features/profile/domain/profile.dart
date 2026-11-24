import 'dart:convert';
import 'dart:typed_data';

/// Public part of the profile. The secret key is never in here: the Rust core keeps it.
class Profile {
  const Profile({required this.name, required this.npub, required this.createdAt, this.picture, this.backedUp = false});

  final String name;

  /// Square avatar (PNG bytes); stays on this device.
  final Uint8List? picture;
  final String npub;

  /// Whether the user confirmed they saved the secret key.
  final bool backedUp;
  final int createdAt;

  Profile copyWith({String? name, Uint8List? picture, bool clearPicture = false, bool? backedUp}) => Profile(
    name: name ?? this.name,
    npub: npub,
    createdAt: createdAt,
    picture: clearPicture ? null : (picture ?? this.picture),
    backedUp: backedUp ?? this.backedUp,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'npub': npub,
    'createdAt': createdAt,
    'backedUp': backedUp,
    if (picture != null) 'picture': base64Encode(picture!),
  };

  static Profile? tryParse(String text) {
    try {
      final j = jsonDecode(text) as Map<String, Object?>;
      return Profile(
        name: j['name'] as String,
        npub: j['npub'] as String,
        createdAt: (j['createdAt'] as num).toInt(),
        backedUp: j['backedUp'] == true,
        picture: j['picture'] is String ? base64Decode(j['picture'] as String) : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// `npub1x8f3…k2q9`, for places where the full key does not fit.
String shortNpub(String npub) =>
    npub.length > 16 ? '${npub.substring(0, 10)}…${npub.substring(npub.length - 4)}' : npub;

/// True when importing failed because the text is not a secret key.
bool isInvalidSecretKey(Object error) => '$error'.contains('invalid secret key');
