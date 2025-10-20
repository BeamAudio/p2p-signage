import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:p2p_signage/src/security/i_security.dart';

class CryptoService implements ISecurity {
  late SimpleKeyPair _signingKeyPair;
  late SimpleKeyPair _x25519KeyPair;

  final _ed25519 = Ed25519();
  final _x25519 = X25519();

  Future<void> init() async {
    _signingKeyPair = await _ed25519.newKeyPair();
    _x25519KeyPair = await _x25519.newKeyPair();
  }

  Future<String> get x25519PublicKey async {
    final publicKey = await _x25519KeyPair.extractPublicKey();
    return base64Url.encode(publicKey.bytes);
  }

  Future<SecretKey> deriveSharedSecret(String remoteX25519PublicKey) async {
    final remotePublicKeyBytes = base64Url.decode(remoteX25519PublicKey);
    final remotePublicKey = SimplePublicKey(
      remotePublicKeyBytes,
      type: KeyPairType.x25519,
    );
    return await _x25519.sharedSecretKey(
      keyPair: _x25519KeyPair,
      remotePublicKey: remotePublicKey,
    );
  }

  Future<SecretBox> encrypt(String plaintext, SecretKey sharedSecret) async {
    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(plaintext),
      secretKey: sharedSecret,
    );
    return secretBox;
  }

  Future<String> decrypt(SecretBox secretBox, SecretKey sharedSecret) async {
    final decryptedBytes = await AesGcm.with256bits().decrypt(
      secretBox,
      secretKey: sharedSecret,
    );
    return utf8.decode(decryptedBytes);
  }

  @override
  Future<String> get publicKey async {
    final publicKey = await _signingKeyPair.extractPublicKey();
    return base64Url.encode(publicKey.bytes);
  }

  @override
  Future<String> sign(String data) async {
    final messageBytes = utf8.encode(data);
    final signature = await _ed25519.sign(
      messageBytes,
      keyPair: _signingKeyPair,
    );
    return base64Url.encode(signature.bytes);
  }

  @override
  Future<bool> verify(String data, String signature, String publicKey) async {
    final messageBytes = utf8.encode(data);
    final signatureBytes = base64Url.decode(signature);
    final publicKeyBytes = base64Url.decode(publicKey);

    final simplePublicKey = SimplePublicKey(
      publicKeyBytes,
      type: KeyPairType.ed25519,
    );

    return await _ed25519.verify(
      messageBytes,
      signature: Signature(signatureBytes, publicKey: simplePublicKey),
    );
  }
}
