import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';

class CryptoUtils {
  // Generate a new RSA key pair
  static AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generateRSAKeyPair() {
    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          _getSecureRandom()));
    final keyPair = keyGen.generateKeyPair();
    return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
        keyPair.publicKey as RSAPublicKey, keyPair.privateKey as RSAPrivateKey);
  }

  // Sign data with a private key
  static Uint8List sign(RSAPrivateKey privateKey, Uint8List dataToSign) {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final sig = signer.generateSignature(dataToSign);
    return sig.bytes;
  }

  // Verify a signature with a public key
  static bool verify(
      RSAPublicKey publicKey, Uint8List signedData, Uint8List signature) {
    final sig = RSASignature(signature);
    final verifier = RSASigner(SHA256Digest(), '0609608648016503040201');
    verifier.init(false, PublicKeyParameter(publicKey));
    try {
      return verifier.verifySignature(signedData, sig);
    } catch (e) {
      return false;
    }
  }

  // Encode a public key to PEM format
  static String encodePublicKeyToPem(RSAPublicKey publicKey) {
    final algorithm = ASN1Sequence();
    algorithm.add(ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1'));
    algorithm.add(ASN1Null());

    final publicKeySequence = ASN1Sequence();
    publicKeySequence.add(ASN1Integer(publicKey.modulus!));
    publicKeySequence.add(ASN1Integer(publicKey.exponent!));
    final publicKeyBitString =
        ASN1BitString(publicKeySequence.encodedBytes);

    final topLevelSequence = ASN1Sequence();
    topLevelSequence.add(algorithm);
    topLevelSequence.add(publicKeyBitString);

    final dataBase64 = base64.encode(topLevelSequence.encodedBytes);
    return '-----BEGIN PUBLIC KEY-----\n$dataBase64\n-----END PUBLIC KEY-----';
  }

  // Decode a public key from PEM format
  static RSAPublicKey parsePublicKeyFromPem(String pemString) {
    final pem = pemString
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll('\n', '');
    final decoded = base64.decode(pem);
    final asn1Parser = ASN1Parser(decoded);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    final publicKeyBitString = topLevelSeq.elements[1] as ASN1BitString;

    final publicKeyAsn = ASN1Parser(publicKeyBitString.stringValue as Uint8List);
    final publicKeySeq = publicKeyAsn.nextObject() as ASN1Sequence;
    final modulus = publicKeySeq.elements[0] as ASN1Integer;
    final exponent = publicKeySeq.elements[1] as ASN1Integer;

    return RSAPublicKey(modulus.valueAsBigInteger, exponent.valueAsBigInteger);
  }

  static SecureRandom _getSecureRandom() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seed = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
    secureRandom.seed(KeyParameter(seed));
    return secureRandom;
  }
}
