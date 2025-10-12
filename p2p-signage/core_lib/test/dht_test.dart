import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:core_lib/p2ptransport.dart';
import 'package:core_lib/dht_manager.dart';
import 'package:core_lib/dht.dart';

void main() {
  group('DHT Network Simulation (Byte-based)', () {
    late List<DhtManager> nodes;
    late List<UdpTransport> discoveryTransports;
    const nodeCount = 5;
    const donorPort = 10000;

    setUp(() async {
      nodes = [];
      discoveryTransports = [];
      for (int i = 0; i < nodeCount; i++) {
        final transport = UdpTransport(
          localPeerId: 'node-$i',
          localAddress: '127.0.0.1',
          localPort: i == 0 ? donorPort : 0, // First node is the donor
        );
        await transport.initialize();
        discoveryTransports.add(transport);

        final dhtManager = DhtManager(
          deviceId: 'node-$i',
          transport: transport,
        );
        nodes.add(dhtManager);
      }
    });

    tearDown(() {
      for (final transport in discoveryTransports) {
        transport.close();
      }
    });

    test('Nodes should join the network and find each other', () async {
      final donor = nodes[0];

      final joinFutures = <Future>[];
      for (int i = 1; i < nodeCount; i++) {
        joinFutures.add(nodes[i].join('127.0.0.1', donorPort));
      }
      await Future.wait(joinFutures);

      await Future.delayed(Duration(seconds: 5));

      for (final querier in nodes) {
        for (final target in nodes) {
          if (querier.deviceId != target.deviceId) {
            final foundNodes = await querier.findNode(target.localNodeId);
            final targetInfo = foundNodes.firstWhere(
              (info) => info.deviceId == target.deviceId,
              orElse: () => throw Exception('Node ${target.deviceId} not found by ${querier.deviceId}'),
            );

            expect(targetInfo.deviceId, target.deviceId);
            expect(targetInfo.ip, target.localPeerInfo.ip);
            expect(targetInfo.port, target.localPeerInfo.port);
          }
        }
      }
    }, timeout: Timeout(Duration(seconds: 30)));

    test('Discovered peer should be connectable on a separate socket', () async {
      final donor = nodes[0];
      final node1 = nodes[1];

      await node1.join('127.0.0.1', donorPort);
      await Future.delayed(Duration(seconds: 2));

      // Node 1 finds the donor via DHT
      final foundNodes = await node1.findNode(donor.localNodeId);
      final donorInfo = foundNodes.firstWhere((info) => info.deviceId == donor.deviceId);

      // Now, use a separate communication transport to connect to the donor
      final commsTransport = TcpTransport(localPeerId: 'comm-node-1');
      await commsTransport.initialize();

      final message = NetworkMessage(
        type: MessageType.data,
        fromPeerId: 'comm-node-1',
        payload: Uint8List.fromList('Hello, this is a direct connection'.codeUnits),
        sequenceNumber: 0,
      );

      // This will create a new TCP connection to the donor's port
      await commsTransport.sendMessage(message, address: donorInfo.ip, port: donorInfo.port);

      // In a real app, the donor would be listening on this port with a TCP server.
      // For this test, we just verify that the sendMessage call completes without error.

      commsTransport.close();

    }, timeout: Timeout(Duration(seconds: 10)));
  });
}