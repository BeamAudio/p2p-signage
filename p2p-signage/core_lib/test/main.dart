
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_lib/core_lib.dart';
import 'package:core_lib/dht.dart';
import 'package:core_lib/dht_manager.dart';
import 'package:core_lib/dht_protocol.dart';

void main() async {
  // --- Peer 1 Setup ---
  final peer1Id = 'peer1';
  final peer1Transport = UdpTransport(localPeerId: peer1Id);
  await peer1Transport.initialize();
  final peer1DhtManager = DhtManager(deviceId: peer1Id, transport: peer1Transport);
  peer1DhtManager.localPeerInfo = SignedPeerInfo.create(
    peer1Id,
    '127.0.0.1',
    peer1Transport.localPort!,
    peer1DhtManager.keyPair,
  );

  print('Peer 1 listening on \${peer1Transport.localAddress}:\${peer1Transport.localPort}');
  print('Peer 1 advertising address \${peer1DhtManager.localPeerInfo.ip}:\${peer1DhtManager.localPeerInfo.port}');

  // --- Peer 2 Setup ---
  final peer2Id = 'peer2';
  final peer2Transport = UdpTransport(localPeerId: peer2Id);
  await peer2Transport.initialize();
  final peer2DhtManager = DhtManager(deviceId: peer2Id, transport: peer2Transport);
  peer2DhtManager.localPeerInfo = SignedPeerInfo.create(
    peer2Id,
    '127.0.0.1',
    peer2Transport.localPort!,
    peer2DhtManager.keyPair,
  );

  print('Peer 2 listening on \${peer2Transport.localAddress}:\${peer2Transport.localPort}');
  print('Peer 2 advertising address \${peer2DhtManager.localPeerInfo.ip}:\${peer2DhtManager.localPeerInfo.port}');

  // --- Bootstrapping ---
  print('\n--- Bootstrapping Peer 2 from Peer 1 ---');
  await peer2DhtManager.join(peer1DhtManager.localPeerInfo.ip, peer1DhtManager.localPeerInfo.port);

  // --- Peer Discovery ---
  print('\n--- Peer 1 searching for Peer 2 ---');
  final foundPeers = await peer1DhtManager.findNode(generateNodeId(peer2Id));

  if (foundPeers.isNotEmpty) {
    final peer2Info = foundPeers.first;
    print('Peer 1 found Peer 2 at \${peer2Info.ip}:\${peer2Info.port}');

    // --- Direct Communication ---
    print('\n--- Direct Communication ---');
    final message = 'Hello from Peer 1!';
    final networkMessage = NetworkMessage(
      type: MessageType.data,
      fromPeerId: peer1Id,
      toPeerId: peer2Id,
      payload: Uint8List.fromList(utf8.encode(message)),
      sequenceNumber: 0,
    );

    peer2Transport.messageStream.listen((incoming) {
      if (incoming.message.type == MessageType.data) {
        final receivedMessage = utf8.decode(incoming.message.payload);
        print('Peer 2 received message: "\$receivedMessage"');
      }
    });

    await peer1Transport.sendMessage(
      networkMessage,
      address: peer2Info.ip,
      port: peer2Info.port,
    );
  } else {
    print('Peer 1 could not find Peer 2');
  }

  // --- Shutdown ---
  await Future.delayed(Duration(seconds: 5));
  peer1Transport.close();
  peer2Transport.close();
}
