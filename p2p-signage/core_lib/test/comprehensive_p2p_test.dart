import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:test/test.dart';
import 'package:core_lib/core_lib.dart';

void main() {
  group('Comprehensive P2P System Test Suite', () {
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
    });

    test('Test P2PTransport Initialization and Peer Management', () async {
      final transport = UdpTransport(
        localPeerId: 'test_peer_1',
        localAddress: '127.0.0.1',
        localPort: 0, // Let system assign port
      );

      await transport.initialize();
      
      // Check that the transport initialized with a valid port
      expect(transport.localPort, isNotNull);
      expect(transport.localPort, greaterThan(0));
      
      // Test adding and getting peers
      final peer1 = Peer(
        id: 'peer_1',
        address: '127.0.0.1',
        port: 9001,
        isOnline: true,
      );
      
      transport.addPeer(peer1);
      final peers = transport.getPeers();
      expect(peers.containsKey('peer_1'), isTrue);
      expect(peers['peer_1']!.address, '127.0.0.1');
      
      // Test removing peer
      transport.removePeer('peer_1');
      final peersAfterRemoval = transport.getPeers();
      expect(peersAfterRemoval.containsKey('peer_1'), isFalse);
      
      transport.close();
    });

    test('Test Message Sending and Receiving with UDP Transport', () async {
      final node1 = UdpTransport(
        localPeerId: 'node_1',
        localAddress: '127.0.0.1',
        localPort: 0,
      );
      final node2 = UdpTransport(
        localPeerId: 'node_2',
        localAddress: '127.0.0.1',
        localPort: 0,
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
      expect(ackResult, isTrue);

      node1.close();
      node2.close();
    });

    test('Test NetAbstraction with Unified Transport', () async {
      final node1 = NetAbstraction(
        peerId: 'node_1', 
        localAddress: '127.0.0.1',
        udpPort: 0, 
        tcpPort: 0
      );
      final node2 = NetAbstraction(
        peerId: 'node_2', 
        localAddress: '127.0.0.1',
        udpPort: 0, 
        tcpPort: 0
      );

      await node1.initialize();
      await node2.initialize();

      // Connect nodes using TCP ports
      final node2TcpPort = (node2.transport as UnifiedP2PTransport).tcpTransport.localPort!;
      final node2Peer = Peer(
        id: 'node_2',
        address: '127.0.0.1',
        port: node2TcpPort, // TCP port
        isOnline: true,
      );
      node1.addPeer(node2Peer);

      final node1TcpPort = (node1.transport as UnifiedP2PTransport).tcpTransport.localPort!;
      final node1Peer = Peer(
        id: 'node_1',
        address: '127.0.0.1',
        port: node1TcpPort,
        isOnline: true,
      );
      node2.addPeer(node1Peer);

      // Allow time for TCP connections to establish
      await Future.delayed(Duration(milliseconds: 500));

      // Set up message tracking
      int node2MessagesReceived = 0;
      Completer<void> messageReceivedCompleter = Completer<void>();

      node2.messageStream.listen((incoming) {
        final message = incoming.message;
        node2MessagesReceived++;
        if (!messageReceivedCompleter.isCompleted) {
          messageReceivedCompleter.complete();
        }
      });

      // Test message sending
      await node1.sendMessage('Hello from Node 1', 'node_2');
      
      await messageReceivedCompleter.future.timeout(Duration(seconds: 5), 
        onTimeout: () {
          throw TimeoutException('Message not received within 5 seconds');
        });
      
      expect(node2MessagesReceived, greaterThanOrEqualTo(1));

      // Test broadcast
      messageReceivedCompleter = Completer<void>();
      await node1.broadcastMessage('Broadcast message');
      await messageReceivedCompleter.future.timeout(Duration(seconds: 5), 
        onTimeout: () {
          throw TimeoutException('Broadcast message not received within 5 seconds');
        });
      
      expect(node2MessagesReceived, greaterThanOrEqualTo(2));

      // Test sending data with integrity
      final testData = Uint8List.fromList(List.generate(256, (i) => i % 256));
      final integrityResult = await node1.sendDataWithIntegrity(testData, 'node_2');
      expect(integrityResult, isTrue);

      // Test health metrics
      final healthMetrics = node1.getHealthMetrics();
      expect(healthMetrics.connectedPeers, greaterThanOrEqualTo(1));
      expect(healthMetrics.totalMessagesSent, greaterThanOrEqualTo(0));
      
      // Test routing table functionality
      final routingTable = node1.getPeers();
      expect(routingTable.containsKey('node_2'), isTrue);

      // Test network statistics
      final stats = node1.getNetworkStatistics();
      expect(stats['connectedPeers'], greaterThanOrEqualTo(1));

      node1.close();
      node2.close();
    });

    test('Test Playlist and Media File Transfer Simulation', () async {
      // Create test data
      final mediaFile = MediaFile(
        fileName: 'test_video.mp4',
        fileType: FileType.video,
        fileSize: 2048576, // ~2MB
        chunkCount: 8,
        checksum: 'd41d8cd98f00b204e9800998ecf8427e',
        filePath: '/tmp/test_video.mp4',
      );
      
      final playlist = Playlist(
        name: 'Test Playlist',
        items: [
          PlaylistItem(
            mediaFileId: mediaFile.fileId,
            duration: 30,
            order: 0,
          ),
        ],
        schedule: PlaylistSchedule(isLooped: true),
        assignedDevices: ['node_2'],
      );
      
      // Create nodes for transfer testing
      final node1 = NetAbstraction(
        peerId: 'node_1', 
        localAddress: '127.0.0.1',
        udpPort: 0, 
        tcpPort: 0
      );
      final node2 = NetAbstraction(
        peerId: 'node_2', 
        localAddress: '127.0.0.1',
        udpPort: 0, 
        tcpPort: 0
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

      // Allow time for TCP connections to establish
      await Future.delayed(Duration(milliseconds: 500));

      // Listen for playlist message
      Completer<void> playlistReceivedCompleter = Completer<void>();
      node2.messageStream.listen((incoming) {
        final message = incoming.message;
        if (message.type == MessageType.data && message.payload is Map<String, dynamic>) {
          // Check if this could be a playlist
          final payload = message.payload as Map<String, dynamic>;
          if (payload.containsKey('name') && payload.containsKey('items')) {
            try {
              final playlistFromMessage = Playlist.fromJson(payload);
              if (playlistFromMessage.name == 'Test Playlist') {
                playlistReceivedCompleter.complete();
              }
            } catch (e) {
              // Not a playlist, continue listening
            }
          }
        }
      });

      // Convert playlist to message and send
      final playlistMessage = NetworkMessage(
        type: MessageType.data,
        fromPeerId: node1.localPeerId,
        toPeerId: 'node_2',
        payload: playlist.toJson(),
        sequenceNumber: 0,
      );
      
      await node1.transport.sendMessage(playlistMessage, peerId: 'node_2');
      
      await playlistReceivedCompleter.future.timeout(Duration(seconds: 5), 
        onTimeout: () {
          throw TimeoutException('Playlist not received within 5 seconds');
        });

      // Close nodes
      node1.close();
      node2.close();
      
      expect(playlist.name, 'Test Playlist');
      expect(playlist.items.length, 1);
    });

    test('Test Error Handling and Robustness', () async {
      final node1 = NetAbstraction(
        peerId: 'node_1', 
        localAddress: '127.0.0.1',
        udpPort: 0, 
        tcpPort: 0
      );

      await node1.initialize();

      // Try to send message to non-existent peer
      try {
        await node1.sendMessage('Test message', 'non_existent_peer');
        // This might not throw an error immediately, but should handle gracefully
      } catch (e) {
        // Expected that this might fail, but shouldn't crash
      }

      // Test with invalid message
      try {
        final invalidMessage = NetworkMessage(
          type: MessageType.data,
          fromPeerId: node1.localPeerId,
          toPeerId: 'invalid_peer',
          payload: null, // Invalid payload
          sequenceNumber: 0,
        );
        await node1.transport.sendMessage(invalidMessage, peerId: 'invalid_peer');
      } catch (e) {
        // Should handle gracefully
      }

      node1.close();
    });
  });
}