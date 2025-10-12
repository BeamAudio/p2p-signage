import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'crypto_utils.dart';
import 'dht_utils.dart';

const int K_BUCKET_SIZE = 20;
const int NODE_ID_LENGTH = 20; // SHA-1 hash length

// Represents the information a peer signs and shares.
class SignedPeerInfo {
  final String deviceId;
  final String ip;
  final int port;
  final RSAPublicKey publicKey;
  final Uint8List signature;
  final int timestamp;

  SignedPeerInfo({
    required this.deviceId,
    required this.ip,
    required this.port,
    required this.publicKey,
    required this.signature,
    required this.timestamp,
  });

  // Creates a signed payload for the current peer.
  static SignedPeerInfo create(
      String deviceId, String ip, int port, AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> keyPair) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final dataToSign = toVerifiableData(deviceId, ip, port, keyPair.publicKey, timestamp);
    final signature = CryptoUtils.sign(keyPair.privateKey, dataToSign);

    return SignedPeerInfo(
      deviceId: deviceId,
      ip: ip,
      port: port,
      publicKey: keyPair.publicKey,
      signature: signature,
      timestamp: timestamp,
    );
  }

  static Uint8List toVerifiableData(
      String deviceId, String ip, int port, RSAPublicKey publicKey, int timestamp) {
    final publicKeyPem = CryptoUtils.encodePublicKeyToPem(publicKey);
    return utf8.encode('$deviceId:$ip:$port:$publicKeyPem:$timestamp');
  }

  Uint8List toBytes() {
    final deviceIdBytes = utf8.encode(deviceId);
    final ipBytes = utf8.encode(ip);
    final publicKeyPem = CryptoUtils.encodePublicKeyToPem(publicKey);
    final publicKeyBytes = utf8.encode(publicKeyPem);

    final buffer = BytesBuilder();
    buffer.addByte(deviceIdBytes.length);
    buffer.add(deviceIdBytes);
    buffer.addByte(ipBytes.length);
    buffer.add(ipBytes);
    buffer.add(Uint8List(2)..buffer.asByteData().setUint16(0, port));
    buffer.add(Uint8List(2)..buffer.asByteData().setUint16(0, publicKeyBytes.length));
    buffer.add(publicKeyBytes);
    buffer.add(Uint8List(2)..buffer.asByteData().setUint16(0, signature.length));
    buffer.add(signature);
    buffer.add(Uint8List(8)..buffer.asByteData().setInt64(0, timestamp));
    return buffer.toBytes();
  }

  static SignedPeerInfo fromBytes(Uint8List bytes) {
    final byteData = ByteData.view(bytes.buffer);
    int offset = 0;

    final deviceIdLen = byteData.getUint8(offset++);
    final deviceId = utf8.decode(bytes.sublist(offset, offset + deviceIdLen));
    offset += deviceIdLen;

    final ipLen = byteData.getUint8(offset++);
    final ip = utf8.decode(bytes.sublist(offset, offset + ipLen));
    offset += ipLen;

    final port = byteData.getUint16(offset);
    offset += 2;

    final publicKeyLen = byteData.getUint16(offset);
    offset += 2;
    final publicKeyPem = utf8.decode(bytes.sublist(offset, offset + publicKeyLen));
    final publicKey = CryptoUtils.parsePublicKeyFromPem(publicKeyPem);
    offset += publicKeyLen;

    final signatureLen = byteData.getUint16(offset);
    offset += 2;
    final signature = bytes.sublist(offset, offset + signatureLen);
    offset += signatureLen;

    final timestamp = byteData.getInt64(offset);

    return SignedPeerInfo(
      deviceId: deviceId,
      ip: ip,
      port: port,
      publicKey: publicKey,
      signature: signature,
      timestamp: timestamp,
    );
  }
}


// Manages the k-buckets for the routing table
class RoutingTable {
  final Uint8List localNodeId;
  final List<List<SignedPeerInfo>> buckets;

  RoutingTable({required this.localNodeId})
      : buckets = List.generate(NODE_ID_LENGTH * 8, (_) => []);

  void addNode(SignedPeerInfo peerInfo) {
    final nodeId = generateNodeId(peerInfo.deviceId);
    if (_equalNodeIds(localNodeId, nodeId)) return;

    final bucketIndex = _getBucketIndex(nodeId);
    final bucket = buckets[bucketIndex];

    // Avoid duplicates
    bucket.removeWhere((p) => p.deviceId == peerInfo.deviceId);
    bucket.add(peerInfo);

    if (bucket.length > K_BUCKET_SIZE) {
      // If the bucket is full, remove the oldest entry.
      // A more robust implementation would ping the oldest node first.
      bucket.removeAt(0);
    }
  }

  List<SignedPeerInfo> findClosestNodes(Uint8List targetId, {int count = K_BUCKET_SIZE}) {
    final distances = <_NodeDistance>[];
    for (final bucket in buckets) {
      for (final peerInfo in bucket) {
        final nodeId = generateNodeId(peerInfo.deviceId);
        distances.add(_NodeDistance(peerInfo, xorDistance(nodeId, targetId)));
      }
    }

    distances.sort((a, b) => compareDistances(a.distance, b.distance));

    return distances.take(count).map((nd) => nd.node).toList();
  }

  int _getBucketIndex(Uint8List nodeId) {
    final distance = xorDistance(localNodeId, nodeId);
    for (int i = 0; i < distance.length; i++) {
      for (int j = 0; j < 8; j++) {
        if ((distance[i] >> (7 - j)) & 1 != 0) {
          return i * 8 + j;
        }
      }
    }
    return (NODE_ID_LENGTH * 8) - 1;
  }

  bool _equalNodeIds(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _NodeDistance {
  final SignedPeerInfo node;
  final Uint8List distance;

  _NodeDistance(this.node, this.distance);
}

// Generates a node ID from a string
Uint8List generateNodeId(String value) {
  return Uint8List.fromList(sha1.convert(utf8.encode(value)).bytes);
}