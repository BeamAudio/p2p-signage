import 'dart:async';
import 'package:p2p_signage/src/config/config.dart';
import 'package:p2p_signage/src/models/message.dart';
import 'package:p2p_signage/src/models/peer.dart';
import 'package:p2p_signage/isolates/node_isolate.dart';
import 'package:test/test.dart';

void main() {
  group('P2PNode Feature Integration', () {
    late List<NodeIsolate> nodes;

    setUp(() async {
      nodes = List.generate(2, (_) => NodeIsolate());
    });

    tearDown(() async {
      for (final node in nodes) {
        await node.stop();
      }
    });

    test('Inactive peers are cleaned up', () async {
      final config1 = P2PConfig(
        username: 'node1',
        peerCleanupInterval: 2, // Cleanup every 2 seconds
        messageTimeoutSeconds: 1, // Peers inactive after 1 second
forceLocalhost: true,
      );
      final config2 = P2PConfig(
        username: 'node2',
        gossipInterval: 1,
        forceLocalhost: true,
      );

      await nodes[0].start(config1);
      await nodes[1].start(config2);

      final node2Port = await nodes[1].getLocalPort();
      final node2PublicKey = await nodes[1].getPublicKey();
      await nodes[0].addDonorPeerSimple(config2.ipAddress, node2Port);

      // Wait for peer to be added
      await Future.delayed(const Duration(seconds: 5));

      var peersOfNode1 = await nodes[0].getPeers();

      // Wait for discovery and authentication
      await Future.delayed(const Duration(seconds: 4));

      peersOfNode1 = await nodes[0].getPeers();
      expect(peersOfNode1.any((p) => p.username == config2.username), isTrue);

      // Stop node 2 to make it inactive
      await nodes[1].stop();

      // Wait for cleanup to occur
      await Future.delayed(const Duration(seconds: 4));

      peersOfNode1 = await nodes[0].getPeers();
      expect(peersOfNode1.any((p) => p.username == config2.username), isFalse);
    }, timeout: Timeout(Duration(seconds: 20)));
  });
}