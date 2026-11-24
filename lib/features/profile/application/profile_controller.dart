import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/rust/api/identity.dart' as nostr;
import '../../../core/settings/settings.dart';
import '../domain/profile.dart';

const _storageKey = 'pania.profile';

/// The person's Nostr identity: the profile record lives in preferences, the secret key only in
/// the Rust core (and the Android Keystore under it).
class ProfileController extends Notifier<Profile?> {
  @override
  Profile? build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_storageKey);
    return saved == null ? null : Profile.tryParse(saved);
  }

  void _set(Profile? profile) {
    final prefs = ref.read(sharedPreferencesProvider);
    if (profile == null) {
      prefs.remove(_storageKey);
    } else {
      prefs.setString(_storageKey, jsonEncode(profile.toJson()));
    }
    state = profile;
  }

  String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception(I18n.t('profile.nameRequired'));
    return trimmed;
  }

  /// Creates a new Nostr key pair and the profile that owns it.
  Future<Profile> createProfile(String name, Uint8List? picture) async {
    final valid = _validName(name);
    final npub = await nostr.nostrCreateIdentity();
    final profile = Profile(
      name: valid,
      npub: npub,
      picture: picture,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _set(profile);
    return profile;
  }

  /// Uses an existing `nsec` / hex secret key instead of generating one.
  Future<Profile> importProfile(String secret, String name) async {
    final valid = _validName(name);
    final String npub;
    try {
      npub = await nostr.nostrImportIdentity(secret: secret);
    } catch (e) {
      throw isInvalidSecretKey(e) ? Exception(I18n.t('profile.importInvalid')) : e;
    }
    // An imported key was backed up somewhere already, or the user would not have it.
    final profile = Profile(
      name: valid,
      npub: npub,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      backedUp: true,
      picture: null,
    );
    _set(profile);
    return profile;
  }

  void updateProfile(String name, Uint8List? picture) {
    final current = state;
    if (current == null) return;
    final valid = _validName(name);
    _set(
      picture == null
          ? current.copyWith(name: valid, clearPicture: true)
          : current.copyWith(name: valid, picture: picture),
    );
  }

  /// Reads the secret key from secure storage, only to show it for a backup.
  Future<String?> revealSecretKey() => nostr.nostrExportSecret();

  /// Whether this device still has the key that belongs to the profile.
  Future<bool> hasSecretKey() async => (await nostr.nostrIdentityNpub()) != null;

  void markBackedUp() {
    final current = state;
    if (current != null) _set(current.copyWith(backedUp: true));
  }

  /// Deletes the secret key and the profile from this device.
  Future<void> removeProfile() async {
    await nostr.nostrRemoveIdentity();
    _set(null);
  }
}

final profileProvider = NotifierProvider<ProfileController, Profile?>(ProfileController.new);
