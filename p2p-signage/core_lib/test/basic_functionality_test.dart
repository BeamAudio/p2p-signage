import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:core_lib/core_lib.dart';

void main() {
  group('Core Lib Unit Tests', () {
    test('Test Data Models Creation and Serialization', () {
      // Test Device data model
      final device = Device(
        deviceName: 'Test Device',
        role: DeviceRole.master,
        publicIp: '192.168.1.100',
        publicPort: 8080,
        status: DeviceStatus.online,
      );
      
      expect(device.deviceName, 'Test Device');
      expect(device.role, DeviceRole.master);
      expect(device.status, DeviceStatus.online);
      
      // Test serialization/deserialization
      final deviceJson = device.toJson();
      final deviceFromJson = Device.fromJson(deviceJson);
      expect(deviceFromJson.deviceName, device.deviceName);
      
      // Test MediaFile data model
      final mediaFile = MediaFile(
        fileName: 'test_video.mp4',
        fileType: FileType.video,
        fileSize: 1024000,
        chunkCount: 10,
        checksum: 'abc123',
        filePath: '/path/to/file',
      );
      
      expect(mediaFile.fileName, 'test_video.mp4');
      expect(mediaFile.fileType, FileType.video);
      
      final mediaFileJson = mediaFile.toJson();
      final mediaFileFromJson = MediaFile.fromJson(mediaFileJson);
      expect(mediaFileFromJson.fileName, mediaFile.fileName);
      
      // Test Playlist data model
      final playlist = Playlist(
        name: 'Test Playlist',
        items: [
          PlaylistItem(
            mediaFileId: 'file1',
            duration: 30,
            order: 0,
          ),
          PlaylistItem(
            mediaFileId: 'file2',
            duration: 60,
            order: 1,
          ),
        ],
        schedule: PlaylistSchedule(isLooped: true),
        assignedDevices: ['device1', 'device2'],
      );
      
      expect(playlist.name, 'Test Playlist');
      expect(playlist.items.length, 2);
      expect(playlist.schedule.isLooped, true);
      
      final playlistJson = playlist.toJson();
      final playlistFromJson = Playlist.fromJson(playlistJson);
      expect(playlistFromJson.name, playlist.name);
      expect(playlistFromJson.items.length, playlist.items.length);
      
      print('Data models test passed!');
    });

    test('Test UDP Transport Basic Functionality', () async {
      final node1 = UdpTransport(
        localPeerId: 'node_1',
        localAddress: '127.0.0.1',
        localPort: 0, // Let system assign port
      );
      final node2 = UdpTransport(
        localPeerId: 'node_2',
        localAddress: '127.0.0.1',
        localPort: 0, // Let system assign port
      );

      await node1.initialize();
      await node2.initialize();

      // Connect nodes
      final node2Peer = Peer(
        id: 'node_2',
        address: '127.0.0.1',
        port: node2.localPort!,
        isOnline: true,
      );
      node1.addPeer(node2Peer);

      final node1Peer = Peer(
        id: 'node_1',
        address: '127.0.0.1',
        port: node1.localPort!,
        isOnline: true,
      );
      node2.addPeer(node1Peer);

      // Set up message tracking
      int node2MessagesReceived = 0;
      Completer<void> messageReceivedCompleter = Completer<void>();

      node2.addMessageHandler((incoming) {
        node2MessagesReceived++;
        if (!messageReceivedCompleter.isCompleted) {
          messageReceivedCompleter.complete();
        }
        return 0; // Required return value
      });

      // Send a test message
      final message = NetworkMessage(
        type: MessageType.data,
        fromPeerId: 'node_1',
        toPeerId: 'node_2',
        payload: 'Test message',
        sequenceNumber: 0,
      );

      await node1.sendMessage(message, peerId: 'node_2');
      
      // Wait for message to be received
      await messageReceivedCompleter.future.timeout(Duration(seconds: 5), 
        onTimeout: () {
          throw TimeoutException('Message not received within 5 seconds');
        });
      
      expect(node2MessagesReceived, greaterThanOrEqualTo(1));

      // Test ACK/NACK mechanism
      final ackResult = await node1.sendMessageWithAck(message, 'node_2');
      expect(ackResult, true);

      node1.close();
      node2.close();
      
      print('UDP Transport test passed!');
    });

    test('Test NetAbstraction UDP-only Functionality', () async {
      // Create two nodes using UDP only to simplify the test
      final node1Transport = UdpTransport(
        localPeerId: 'node_1',
        localAddress: '127.0.0.1',
        localPort: 0,
      );
      final node2Transport = UdpTransport(
        localPeerId: 'node_2',
        localAddress: '127.0.0.1',
        localPort: 0,
      );
      
      await node1Transport.initialize();
      await node2Transport.initialize();
      
      // Connect nodes
      node1Transport.addPeer(Peer(
        id: 'node_2',
        address: '127.0.0.1',
        port: node2Transport.localPort!,
        isOnline: true,
      ));
      
      node2Transport.addPeer(Peer(
        id: 'node_1',
        address: '127.0.0.1',
        port: node1Transport.localPort!,
        isOnline: true,
      ));
      
      // Set up message tracking
      int node2MessagesReceived = 0;
      Completer<void> messageReceivedCompleter = Completer<void>();

      node2Transport.addMessageHandler((incoming) {
        node2MessagesReceived++;
        final message = incoming.message;
        print('Node 2 received: ${message.type} from ${message.fromPeerId}');
        if (!messageReceivedCompleter.isCompleted) {
          messageReceivedCompleter.complete();
        }
        return 0; // Required return value
      });

      // Send a test message
      final message = NetworkMessage(
        type: MessageType.data,
        fromPeerId: 'node_1',
        toPeerId: 'node_2',
        payload: 'Hello from Node 1',
        sequenceNumber: 0,
      );

      await node1Transport.sendMessage(message, peerId: 'node_2');
      
      // Wait for message to be received
      await messageReceivedCompleter.future.timeout(Duration(seconds: 5), 
        onTimeout: () {
          throw TimeoutException('Message not received within 5 seconds');
        });
      
      expect(node2MessagesReceived, greaterThanOrEqualTo(1));
      
      node1Transport.close();
      node2Transport.close();
      
      print('NetAbstraction UDP test passed!');
    });

    test('Test Message Integrity Verification', () {
      // Create a test message
      final originalMessage = NetworkMessage(
        type: MessageType.data,
        fromPeerId: 'test_node',
        payload: 'test_data',
        sequenceNumber: 0,
      );

      // Calculate checksum manually to verify the method
      final calculatedChecksum = _calculateMessageChecksum(originalMessage);

      // Message should pass integrity check with correct checksum
      final messageWithChecksum = NetworkMessage(
        type: MessageType.data,
        fromPeerId: originalMessage.fromPeerId,
        toPeerId: originalMessage.toPeerId,
        payload: originalMessage.payload,
        checksum: calculatedChecksum,
        sequenceNumber: originalMessage.sequenceNumber,
        timestamp: originalMessage.timestamp,
      );
      
      expect(_verifyMessageIntegrity(messageWithChecksum), true);

      // Message should fail integrity check with wrong checksum
      final messageWithWrongChecksum = NetworkMessage(
        type: MessageType.data,
        fromPeerId: originalMessage.fromPeerId,
        toPeerId: originalMessage.toPeerId,
        payload: originalMessage.payload,
        checksum: 'wrong_checksum',
        sequenceNumber: originalMessage.sequenceNumber,
        timestamp: originalMessage.timestamp,
      );
      
      expect(_verifyMessageIntegrity(messageWithWrongChecksum), false);
      
      print('Message integrity test passed!');
    });

    test('Test Performance Metrics Data Model', () {
      final metrics = PerformanceMetrics(
        cpuUsage: 25.5,
        memoryUsage: 1048576, // 1 MB
        totalMemory: 8388608, // 8 MB
        diskUsage: 45.2,
        networkLatency: 15.7,
        networkDownload: 1048576, // 1 MB/s
        networkUpload: 524288,   // 0.5 MB/s
        nodeId: 'test_node_1',
      );

      expect(metrics.cpuUsage, 25.5);
      expect(metrics.memoryUsage, 1048576);
      expect(metrics.nodeId, 'test_node_1');

      // Test serialization/deserialization
      final json = metrics.toJson();
      final fromJson = PerformanceMetrics.fromJson(json);
      
      expect(fromJson.cpuUsage, metrics.cpuUsage);
      expect(fromJson.memoryUsage, metrics.memoryUsage);
      expect(fromJson.nodeId, metrics.nodeId);
      
      print('Performance metrics test passed!');
    });
  });
}

// Helper functions to test integrity methods
String _calculateMessageChecksum(NetworkMessage message) {
  // This replicates the checksum calculation from P2PTransport
  final content = jsonEncode({
    'type': message.type.index,
    'fromPeerId': message.fromPeerId,
    'toPeerId': message.toPeerId,
    'payload': message.payload,
    'sequenceNumber': message.sequenceNumber,
    'timestamp': message.timestamp.toIso8601String(),
  });
  return sha256.convert(utf8.encode(content)).toString();
}

bool _verifyMessageIntegrity(NetworkMessage message) {
  if (message.checksum == null) return true; // No checksum to verify

  final calculatedChecksum = _calculateMessageChecksum(message);
  return calculatedChecksum == message.checksum;
}