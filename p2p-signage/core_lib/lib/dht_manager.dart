import 'dart:async';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

import 'dht.dart';
import 'crypto_utils.dart';
import 'p2ptransport.dart';
import 'dht_protocol.dart';
import 'dht_utils.dart';

class DhtManager {
  final String deviceId;
  final UdpTransport transport;
  late final Uint8List localNodeId;
  late final RoutingTable routingTable;
  late final AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> keyPair;
  late final SignedPeerInfo localPeerInfo;

  final Map<int, Completer> _pendingRpcs = {};
  int _rpcIdCounter = 0;

  DhtManager({required this.deviceId, required this.transport}) {
    keyPair = CryptoUtils.generateRSAKeyPair();
    localNodeId = generateNodeId(deviceId);
    routingTable = RoutingTable(localNodeId: localNodeId);
    localPeerInfo = SignedPeerInfo.create(
      deviceId,
      transport.localAddress,
      transport.localPort!,
      keyPair,
    );
    _listenForMessages();
  }

  void _listenForMessages() {
    transport.messageStream.listen((incoming) {
      final message = incoming.message.payload;
      final messageType = message[0];
      final rpcId = ByteData.view(message.buffer).getInt32(1);

      if (_pendingRpcs.containsKey(rpcId)) {
        _pendingRpcs[rpcId]!.complete(message);
        _pendingRpcs.remove(rpcId);
        return;
      }

      switch (messageType) {
        case DhtProtocol.PING:
          _handlePing(rpcId, message.sublist(5), incoming.address, incoming.port);
          break;
        case DhtProtocol.FIND_NODE:
          _handleFindNode(rpcId, message.sublist(5), incoming.address, incoming.port);
          break;
        case DhtProtocol.STORE:
          _handleStore(rpcId, message.sublist(5), incoming.address, incoming.port);
          break;
      }
    });
  }

  Future<void> join(String donorIp, int donorPort) async {
    await _sendPing(donorIp, donorPort);
    await findNode(localNodeId);
    await publishSelf();
  }

  Future<void> publishSelf() async {
    final closestNodes = routingTable.findClosestNodes(localNodeId);
    for (final peerInfo in closestNodes) {
      _sendStore(localPeerInfo, peerInfo.ip, peerInfo.port);
    }
  }

  Future<List<SignedPeerInfo>> findNode(Uint8List targetId) async {
    final nodes = <SignedPeerInfo>[];
    final queried = <String>{};

    var closest = routingTable.findClosestNodes(targetId);
    nodes.addAll(closest);

    while (true) {
      var foundMore = false;
      final queries = <Future>[];

      for (final nodeInfo in closest) {
        if (!queried.contains(nodeInfo.deviceId)) {
          queried.add(nodeInfo.deviceId);
          queries.add(
            _sendFindNode(targetId, nodeInfo.ip, nodeInfo.port).then((found) {
              for (final foundNodeInfo in found) {
                if (nodes.every((n) => n.deviceId != foundNodeInfo.deviceId)) {
                  nodes.add(foundNodeInfo);
                  foundMore = true;
                }
              }
            })
          );
        }
      }

      await Future.wait(queries);

      if (!foundMore) break;

      nodes.sort((a, b) {
        final distA = xorDistance(generateNodeId(a.deviceId), targetId);
        final distB = xorDistance(generateNodeId(b.deviceId), targetId);
        return compareDistances(distA, distB);
      });
      closest = nodes.take(K_BUCKET_SIZE).toList();
    }
    return nodes;
  }

  // --- RPC Sending Methods ---

  Future<Uint8List> _sendRpc(Uint8List message, String ip, int port) {
    final rpcId = ByteData.view(message.buffer).getInt32(1);
    final completer = Completer<Uint8List>();
    _pendingRpcs[rpcId] = completer;

    final networkMessage = NetworkMessage(
      type: MessageType.data,
      fromPeerId: deviceId,
      payload: message,
      sequenceNumber: 0,
    );
    transport.sendMessage(networkMessage, address: ip, port: port);

    Timer(Duration(seconds: 5), () {
      if (_pendingRpcs.containsKey(rpcId)) {
        _pendingRpcs[rpcId]!.completeError('RPC Timeout');
        _pendingRpcs.remove(rpcId);
      }
    });

    return completer.future;
  }

  Future<void> _sendPing(String ip, int port) async {
    final rpcId = _rpcIdCounter++;
    final message = DhtProtocol.createPing(rpcId, localPeerInfo.toBytes());
    final response = await _sendRpc(message, ip, port);
    if (response[0] == DhtProtocol.PONG) {
      final peerInfo = SignedPeerInfo.fromBytes(response.sublist(5));
      routingTable.addNode(peerInfo);
    }
  }

  Future<List<SignedPeerInfo>> _sendFindNode(Uint8List targetId, String ip, int port) async {
    final rpcId = _rpcIdCounter++;
    final message = DhtProtocol.createFindNode(rpcId, targetId);
    final response = await _sendRpc(message, ip, port);

    if (response[0] == DhtProtocol.FOUND_NODE) {
      final nodes = <SignedPeerInfo>[];
      final count = response[5];
      int offset = 6;
      for (int i = 0; i < count; i++) {
        final len = ByteData.view(response.buffer).getUint16(offset);
        offset += 2;
        final nodeBytes = response.sublist(offset, offset + len);
        nodes.add(SignedPeerInfo.fromBytes(nodeBytes));
        offset += len;
      }
      return nodes;
    }
    return [];
  }

  void _sendStore(SignedPeerInfo info, String ip, int port) {
    final rpcId = _rpcIdCounter++;
    final message = DhtProtocol.createStore(rpcId, info.toBytes());
    final networkMessage = NetworkMessage(
      type: MessageType.data,
      fromPeerId: deviceId,
      payload: message,
      sequenceNumber: 0,
    );
    transport.sendMessage(networkMessage, address: ip, port: port);
  }

  // --- RPC Handling Methods ---

  void _handlePing(int rpcId, Uint8List payload, String ip, int port) {
    final peerInfo = SignedPeerInfo.fromBytes(payload);
    routingTable.addNode(peerInfo);

    final response = DhtProtocol.createPong(rpcId, localPeerInfo.toBytes());
    final networkMessage = NetworkMessage(
      type: MessageType.data,
      fromPeerId: deviceId,
      payload: response,
      sequenceNumber: 0,
    );
    transport.sendMessage(networkMessage, address: ip, port: port);
  }

  void _handleFindNode(int rpcId, Uint8List payload, String ip, int port) {
    final targetId = payload;
    final closestNodes = routingTable.findClosestNodes(targetId);
    final closestNodesBytes = closestNodes.map((info) => info.toBytes()).toList();

    final response = DhtProtocol.createFoundNode(rpcId, closestNodesBytes);
    final networkMessage = NetworkMessage(
      type: MessageType.data,
      fromPeerId: deviceId,
      payload: response,
      sequenceNumber: 0,
    );
    transport.sendMessage(networkMessage, address: ip, port: port);
  }

  void _handleStore(int rpcId, Uint8List payload, String ip, int port) {
    final peerInfo = SignedPeerInfo.fromBytes(payload);
    routingTable.addNode(peerInfo);
  }
}
