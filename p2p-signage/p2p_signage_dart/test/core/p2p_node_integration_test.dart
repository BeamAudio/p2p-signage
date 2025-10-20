import 'dart:async';

import 'package:p2p_signage/src/config/config.dart';
import 'package:p2p_signage/src/models/message.dart';
import 'package:p2p_signage/src/models/peer.dart';
import 'package:p2p_signage/isolates/node_isolate.dart';
import 'package:test/test.dart';

void main() {
  group('P2PNode Integration', () {
    late List<NodeIsolate> nodes;

    setUp(() async {
      nodes = List.generate(4, (_) => NodeIsolate());
    });

    tearDown(() async {
      for (final node in nodes) {
        await node.stop();
      }
    });

    test('4 nodes discover each other and can send messages', () async {
      final configs = List.generate(
        4,
        (i) => P2PConfig(
          username: 'node${i + 1}',
          udpPort: 0,
          forceLocalhost: true,
        ),
      );

      for (var i = 0; i < 4; i++) {
        await nodes[i].start(configs[i]);
      }

      // Wait a bit for nodes to fully start and discover their actual IPs
      await Future.delayed(const Duration(milliseconds: 500));

      // Get the actual ports and IP addresses after nodes have started
      final ports = <int>[];
      final ips = <String>[];
      for (var i = 0; i < 4; i++) {
        ports.add(await nodes[i].getLocalPort());
        // Get the actual IP that the node is using (from its own peer information)
        final peers = await nodes[i].getPeers();
        final selfPeer = peers.firstWhere((p) => p.username == configs[i].username);
        ips.add(selfPeer.ip);
      }

      for (var i = 1; i < 4; i++) {
        await nodes[i].addDonorPeerSimple(ips[0], ports[0]);
      }

      // Also let node 0 know about node 2 to connect the graph
      await nodes[0].addDonorPeerSimple(ips[1], ports[1]);

      // Add a delay to allow for authentication and gossip to propagate
      await Future.delayed(const Duration(seconds: 5));

      // Wait for nodes to discover each other via gossip
      var allNodesDiscovered = false;
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed < const Duration(seconds: 15) && !allNodesDiscovered) {
        allNodesDiscovered = true;
        for (var i = 0; i < 4; i++) {
          final peers = await nodes[i].getPeers();
          if (peers.length < 4) {
            allNodesDiscovered = false;
            break;
          }
        }
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      for (var i = 0; i < 4; i++) {
        final peers = await nodes[i].getPeers();
        expect(peers.length, 4, reason: "Node ${i+1} did not discover all peers");
      }

    }, timeout: Timeout(Duration(seconds: 20)));
  });
}