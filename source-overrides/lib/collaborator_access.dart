import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'music_access.dart';

abstract interface class CollaboratorCodeStore {
  Future<String?> readHash();
  Future<void> writeHash(String value);
  Future<void> clear();
}

class SharedPreferencesCollaboratorCodeStore implements CollaboratorCodeStore {
  static const String _key = 'rpa.collaborator.code_hash.v1';
  @override
  Future<String?> readHash() async => (await SharedPreferences.getInstance()).getString(_key);
  @override
  Future<void> writeHash(String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(_key, value)) {
      throw StateError('Unable to save collaborator access');
    }
  }
  @override
  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}

/// Access offered by the radio, as requested: no account or server dependency.
/// Hashes avoid publishing the owner's list in plain text. Four-digit local
/// codes are not a security boundary and can be reused on multiple devices.
class CollaboratorAccessController extends ChangeNotifier implements MusicAccessPort {
  CollaboratorAccessController({required CollaboratorCodeStore store, Set<String>? acceptedHashes})
      : _store = store, _acceptedHashes = acceptedHashes ?? _builtInHashes;

  static const Set<String> _builtInHashes = <String>{
    '3dd993106edced7f9113b7c1ded0ca6c663988781f37857781d94c450640e406',
    'b35d537a9944098b67370db7598b5110b9776ec78ec8a354e1d9f0d53d86c885',
    'a2f4daa4e96b656b0e8b3303a4f80b2bdb46ffa492a2b019402dbd8a2a5c1540',
    'a03cdf8716fd211ecb3d4825fe226e7965ad8ff1bf89b1c5736e68ac4bb63fc7',
    '9bbf7a2c2940b4c95ea485f65a8731a1372aee56edca6ed31e66e7eb0f47e28b',
    '3ed69525e7786aea123072900caf9bdcd64d97af9bd8dab106ab6cf06fc0f5e2',
    'e78b541c01a9ef618e791024edc6ff082d46ae701f9e3cba5259330fe135a84b',
    '727350de59be2e3c8ba1ea001e81a8d86e3931813e915dbb384e405c142912e3',
    '8e0f513c882b1c074fc2dec3436ce46ae0fdf63f21562e2736aa0d07d3b6b355',
    '6c4c237fa6808f1c64a0a64254a296c0b006ede809a804447cd6dc06b46cb192',
  };
  final CollaboratorCodeStore _store;
  final Set<String> _acceptedHashes;
  final StreamController<bool> _changes = StreamController<bool>.broadcast(sync: true);
  bool _active = false;
  bool _disposed = false;
  String? _message;

  @override
  bool get hasMusicAccess => _active;
  @override
  Stream<bool> get musicAccessChanges => _changes.stream;
  String? get message => _message;

  Future<void> load() async {
    try {
      final String? saved = await _store.readHash();
      _setActive(saved != null && _acceptedHashes.contains(saved));
      if (!_active && saved != null) await _store.clear();
    } on Object {
      _setActive(false);
    }
  }

  Future<bool> activate(String code) async {
    if (_disposed) return false;
    if (!RegExp(r'^[0-9]{4}$').hasMatch(code)) {
      _message = 'Introduz um código de quatro dígitos.';
      return false;
    }
    final String hash = sha256.convert(utf8.encode(code)).toString();
    if (!_acceptedHashes.contains(hash)) {
      _message = 'O código não é válido. Confirma os quatro dígitos.';
      return false;
    }
    try {
      await _store.writeHash(hash);
      if (_disposed) return false;
      _message = null;
      _setActive(true);
      return true;
    } on Object {
      _message = 'Não foi possível guardar o acesso. Tenta novamente.';
      return false;
    }
  }

  Future<void> remove() async {
    await _store.clear();
    _message = null;
    _setActive(false);
  }

  void _setActive(bool value) {
    if (_disposed || _active == value) return;
    _active = value;
    _changes.add(value);
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_changes.close());
    super.dispose();
  }
}
