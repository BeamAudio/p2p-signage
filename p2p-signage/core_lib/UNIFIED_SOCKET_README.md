# Unified P2P Socket Implementation

## Overview

This unified implementation combines the core P2P networking functionality with network abstraction layer features into a single, cohesive class. The UnifiedP2PSocket provides:

- P2P networking with STUN/TURN/ICE support for NAT traversal
- ACK/NACK reliable transmission protocol
- Network abstraction layer with gossip protocol
- Playlist and media file management
- Node discovery and routing table maintenance
- Performance monitoring and metrics
- Geolocation services

## Features

### Core Networking
- UDP-based P2P communication
- STUN/TURN/ICE for NAT traversal
- Candidate gathering and selection
- Direct and relayed communication

### Reliability
- ACK/NACK protocol for reliable data delivery
- Message retransmission on failure
- Duplicate detection

### Network Abstraction
- Gossip protocol for network topology discovery
- Playlist management (add, update, delete)
- Media file transfer with chunking
- Heartbeat and performance metrics
- Node discovery and routing

## Usage

```dart
import 'package:core_lib/unified_p2p_socket.dart';

// Create a unified socket instance
final socket = UnifiedP2PSocket(
  nodeId: 'my-node-id',
  configuredPublicIp: '127.0.0.1',
  configuredPublicPort: 8080,
);

// Initialize
await socket.gatherCandidates();

// Add remote peers
socket.addRemoteCandidate(
  IceCandidate('manual', '127.0.0.1', 8081, 100)
);

// Listen for messages
socket.onMessage.listen((data) {
  print('Received: ${String.fromCharCodes(data)}');
});

// Send reliable message
await socket.sendWithAck(Uint8List.fromList('Hello'.codeUnits));

// Send playlist to network
final playlist = Playlist(
  id: 'playlist-1',
  name: 'My Playlist',
  mediaItems: [],
);

await socket.addPlaylist(playlist);
```

## Architecture

The unified design combines several previous separate components:

- Core P2PSocket functionality (now integrated)
- ReliableP2PSocket features (ACK/NACK protocol)
- NetAbstraction layer (gossip, playlists, etc.)

This eliminates the need for multiple wrapper classes while maintaining all functionality.