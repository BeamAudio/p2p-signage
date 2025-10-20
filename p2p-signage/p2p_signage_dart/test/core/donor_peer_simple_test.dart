import 'dart:async';
import 'package:p2p_signage/src/config/config.dart';
import 'package:p2p_signage/src/models/message.dart';
import 'package:p2p_signage/src/models/peer.dart';
import 'package:p2p_signage/isolates/node_isolate.dart';
import 'package:test/test.dart';

void main() {
  group('Donor Peer Simple Test', () {
    late NodeIsolate donorNode;
    late NodeIsolate clientNode;

    setUp(() async {
      donorNode = NodeIsolate();
      clientNode = NodeIsolate();
    });

    tearDown(() async {
      await donorNode.stop();
      await clientNode.stop();
    });

    test('Client node can connect to a donor peer and receive messages', () async {
      final donorConfig = P2PConfig(
        username: 'donor',
        forceLocalhost: true,
      );
      final clientConfig = P2PConfig(
        username: 'client',
        forceLocalhost: true,
      );

      final completer = Completer<Message>();
      clientNode.onMessage.listen((message) {
        completer.complete(message);
      });

      await donorNode.start(donorConfig);
      await clientNode.start(clientConfig);

      final donorPort = await donorNode.getLocalPort();
      await clientNode.addDonorPeerSimple('127.0.0.1', donorPort);

      // Wait for connection and authentication
      await Future.delayed(const Duration(seconds: 5));

      await donorNode.sendMessage('client', 'hello from donor');

      final message = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Message not received'),
      );

      expect(message.content, 'hello from donor');
    }, timeout: Timeout(Duration(seconds: 20)));
  });
}