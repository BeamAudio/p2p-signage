import 'dart:async';
import 'dart:io';
import 'package:p2p_signage/src/config/config.dart';
import 'package:p2p_signage/src/models/message.dart';
import 'package:p2p_signage/isolates/node_isolate.dart';
import 'package:test/test.dart';

void main() {
  group('Minimal Test', () {
    late NodeIsolate node1;
    late NodeIsolate node2;

    setUp(() async {
      node1 = NodeIsolate();
      node2 = NodeIsolate();
    });

    tearDown(() async {
      await node1.stop();
      await node2.stop();
    });

    test('2 nodes can send messages to each other', () async {
      final config1 = P2PConfig(
        username: 'node1',
        forceLocalhost: true,
      );
      final config2 = P2PConfig(
        username: 'node2',
        forceLocalhost: true,
      );

      final completer1 = Completer<Message>();
      node1.onMessage.listen((message) {
        completer1.complete(message);
      });

      final completer2 = Completer<Message>();
      node2.onMessage.listen((message) {
        completer2.complete(message);
      });

      await node1.start(config1);
      await node2.start(config2);

      final node2Port = await node2.getLocalPort();
      await node1.addDonorPeerSimple('127.0.0.1', node2Port);
      await Future.delayed(const Duration(seconds: 5));

      await node1.sendMessage('node2', 'hello from node1');
      await node2.sendMessage('node1', 'hello from node2');

      final message1 = await completer1.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Message not received'),
      );
      final message2 = await completer2.future.timeout(const Duration(seconds: 10));

      expect(message1.content, 'hello from node2');
      expect(message2.content, 'hello from node1');
    });
  });
}
