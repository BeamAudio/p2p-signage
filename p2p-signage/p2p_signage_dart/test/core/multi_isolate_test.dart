import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:p2p_signage/src/config/config.dart';
import 'package:p2p_signage/isolates/node_isolate.dart';
import 'package:test/test.dart';

void main() {
  group('Multi-Isolate Test', () {
    final nodes = <NodeIsolate>[];
    final configs = <P2PConfig>[];
    late NodeIsolate donorNode;
    late P2PConfig donorConfig;

    setUp(() async {
      // Create donor node
      donorConfig = P2PConfig(
        username: 'donor',
        forceLocalhost: true,
        gossipInterval: 15, // Reduce gossip interval for faster discovery
        messageTimeoutSeconds: 10,
      );
      donorNode = NodeIsolate();
      nodes.add(donorNode);
      configs.add(donorConfig);

      // Create 20 other nodes
      for (int i = 0; i < 20; i++) {
        final config = P2PConfig(
          username: 'node$i',
          forceLocalhost: true,
          gossipInterval: 15, // Reduce gossip interval for faster discovery
          messageTimeoutSeconds: 10,
        );
        final node = NodeIsolate();
        nodes.add(node);
        configs.add(config);
        await Future.delayed(Duration(milliseconds: 50)); // Add a small delay
      }
    });

    tearDown(() async {
      for (final node in nodes) {
        await node.stop();
      }
    });

    test('20 nodes connect via donor and send messages', () async {
      // Start the donor node
      await donorNode.start(donorConfig);
      final donorPort = await donorNode.getLocalPort();
      
      // Start all other nodes and connect them to the donor
      final startFutures = <Future>[];
      for (int i = 0; i < 20; i++) {
        startFutures.add(nodes[i + 1].start(configs[i + 1])); // +1 to skip donor
        await Future.delayed(Duration(milliseconds: 50)); // Add a small delay
      }
      await Future.wait(startFutures);
      
      // Add donor peer to all nodes
      final donorAddFutures = <Future>[];
      for (int i = 1; i < nodes.length; i++) { // Skip donor node (index 0)
        donorAddFutures.add(nodes[i].addDonorPeerSimple('127.0.0.1', donorPort));
      }
      await Future.wait(donorAddFutures);
      
      // Wait to allow nodes to connect and authenticate
      await Future.delayed(Duration(seconds: 10));
      
      // Collect all peers each node sees
      final allPeerLists = <List<String>>[];
      for (int i = 0; i < nodes.length; i++) {
        final peers = await nodes[i].getPeers();
        final peerNames = peers.map((p) => p.username).toList();
        allPeerLists.add(peerNames);
        print('[ROUTING_TABLE] Node ${configs[i].username}: ${peerNames.join(', ')}'); // Log peer list
      }
      
      // Send test messages between some nodes
      final messageCompleters = <Completer<bool>>[];
      for (int i = 0; i < 5; i++) {
        final completer = Completer<bool>();
        messageCompleters.add(completer);
        
        // Listen for messages on target node
        final targetNode = nodes[i + 2]; // Use nodes[2] onwards to avoid donor and first node
        final targetUsername = configs[i + 2].username;
        
        targetNode.onMessage.listen((message) {
          if (message.content == 'Test message $i from donor') {
            completer.complete(true);
          }
        });
        
        // Send message from donor
        await donorNode.sendMessage(targetUsername, 'Test message $i from donor');
      }
      
      // Wait for all messages to be received or timeout
      await Future.delayed(Duration(seconds: 5));
      
      // Collect metrics from all nodes
      final allMetrics = <Map<String, dynamic>>[];
      for (int i = 0; i < nodes.length; i++) {
        final metrics = await nodes[i].getMetrics();
        allMetrics.add(metrics);
      }
      
      // Summarize all metrics
      int totalMessagesSent = 0;
      int totalMessagesReceived = 0;
      int totalGossipMessagesSent = 0;
      int totalGossipMessagesReceived = 0;
      int totalAuthenticationAttempts = 0;
      
      for (final metrics in allMetrics) {
        totalMessagesSent += (metrics['messagesSent'] as int?) ?? 0;
        totalMessagesReceived += (metrics['messagesReceived'] as int?) ?? 0;
        totalGossipMessagesSent += (metrics['gossipMessagesSent'] as int?) ?? 0;
        totalGossipMessagesReceived += (metrics['gossipMessagesReceived'] as int?) ?? 0;
        totalAuthenticationAttempts += (metrics['authenticationAttempts'] as int?) ?? 0;
      }
      
      // Let the test run for a bit longer to gather more data
      await Future.delayed(Duration(seconds: 10));
    }, timeout: Timeout(Duration(minutes: 3)));
  });
}