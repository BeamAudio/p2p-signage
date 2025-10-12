import 'dart:async';
import 'dart:convert';
import 'dart:typed_data'; // Added
import 'dart:math'; // Added
import 'package:core_lib/p2ptransport.dart';

/// Represents network health metrics
class NetworkHealthMetrics {
  final int connectedPeers;
  final double averageLatency;
  final int totalMessagesSent;
  final int totalMessagesReceived;
  final double messageDeliveryRate;
  final DateTime timestamp;

  NetworkHealthMetrics({
    required this.connectedPeers,
    required this.averageLatency,
    required this.totalMessagesSent,
    required this.totalMessagesReceived,
    required this.messageDeliveryRate,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Network Abstraction Layer - Provides high-level API for peer-to-peer networking
class NetAbstraction {
  final P2PTransport _transport;
  
  /// Expose the internal transport for advanced usage
  P2PTransport get transport => _transport;
  final String _localPeerId;
  final Map<String, String> _routingTable = {};
  final Map<String, Completer> _pendingOperations = {};
  final List<Function(Peer)> _peerDiscoveryHandlers = [];
  final List<Function(NetworkHealthMetrics)> _healthChangeHandlers = [];
  final List<Function(Map<String, Peer>)> _routingTableChangeHandlers = [];
  
  int _totalMessagesSent = 0;
  int _totalMessagesReceived = 0;
  int _totalBytesTransferred = 0;
  Timer? _gossipTimer;
  Timer? _healthCheckTimer;
  DateTime _lastHealthCheck = DateTime.now();

  StreamController<IncomingMessage>? _messageStreamController;
  late Stream<IncomingMessage> _messageStream;
  
  NetAbstraction({
    required String peerId,
    String localAddress = '0.0.0.0',
    int udpPort = 0,
    int tcpPort = 0,
  }) : _localPeerId = peerId,
       _transport = UnifiedP2PTransport(
         localPeerId: peerId,
         localAddress: localAddress,
         udpPort: udpPort,
         tcpPort: tcpPort,
       ) {
    _messageStreamController = StreamController<IncomingMessage>.broadcast();
    _messageStream = _transport.messageStream.asBroadcastStream();
  }
  
  /// Get access to the message stream for direct consumption
  Stream<IncomingMessage> get messageStream => _messageStream;

  /// Initialize the network abstraction layer
  Future<void> initialize() async {
    await _transport.initialize();
    
    // Add message handler for internal message types
    _transport.addMessageHandler(_handleInternalMessage);
    
    // Start gossip protocol timer
    _gossipTimer = Timer.periodic(Duration(seconds: 15), (timer) {
      _gossipRoutingTable();
    });
    
    // Start health check timer
    _healthCheckTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _performHealthCheck();
    });
  }

  /// Add a handler for peer discovery events
  void addPeerDiscoveryHandler(Function(Peer) handler) {
    _peerDiscoveryHandlers.add(handler);
  }

  /// Add a handler for network health changes
  void addHealthChangeHandler(Function(NetworkHealthMetrics) handler) {
    _healthChangeHandlers.add(handler);
  }

  /// Add a handler for routing table changes
  void addRoutingTableChangeHandler(Function(Map<String, Peer>) handler) {
    _routingTableChangeHandlers.add(handler);
  }

  /// Add a peer to the network
  void addPeer(Peer peer) {
    _transport.addPeer(peer);
    _routingTable[peer.id] = '${peer.address}:${peer.port}';
    _notifyRoutingTableChange();
  }

  /// Remove a peer from the network
  void removePeer(String peerId) {
    _transport.removePeer(peerId);
    _routingTable.remove(peerId);
    _notifyRoutingTableChange();
  }

  /// Get all known peers
  Map<String, Peer> getPeers() {
    return _transport.getPeers();
  }

  /// Send a message to a specific peer
  Future<void> sendMessage(String content, String peerId) async {
    final message = NetworkMessage(
      type: MessageType.data,
      fromPeerId: _localPeerId,
      toPeerId: peerId,
      payload: utf8.encode(content),
      sequenceNumber: 0, // Will be set by transport
    );
    
    await _transport.sendMessage(message, peerId: peerId);
    _totalMessagesSent++;
  }

  /// Broadcast a message to all peers
  Future<void> broadcastMessage(String content) async {
    final message = NetworkMessage(
      type: MessageType.data,
      fromPeerId: _localPeerId,
      payload: utf8.encode(content),
      sequenceNumber: 0, // Will be set by transport
    );
    
    // Send to all peers without specifying a specific peer ID
    await _transport.sendMessage(message);
    _totalMessagesSent++;
  }

  /// Send data with integrity verification
  Future<bool> sendDataWithIntegrity(Uint8List data, String peerId) async {
    return await _transport.sendMessageWithAck(
      NetworkMessage(
        type: MessageType.fileTransfer,
        fromPeerId: _localPeerId,
        toPeerId: peerId,
        payload: data,
        sequenceNumber: 0,
      ),
      peerId,
    );
  }

  /// Get the local peer ID
  String get localPeerId => _localPeerId;

  /// Get the local UDP port
  int? get localPort => _transport.localPort;
  
  /// Get the local TCP port
  int? get localTcpPort {
    if (_transport is UnifiedP2PTransport) {
      return (_transport as UnifiedP2PTransport).tcpTransport.localPort;
    }
    return null;
  }

  /// Get current network health metrics
  NetworkHealthMetrics getHealthMetrics() {
    final peers = getPeers();
    int totalLatency = 0;
    for (final peer in peers.values) {
      totalLatency += DateTime.now().difference(peer.lastSeen).inMilliseconds;
    }
    final avgLatency = peers.isNotEmpty ? totalLatency / peers.length : 0.0;

    return NetworkHealthMetrics(
      connectedPeers: peers.length,
      averageLatency: avgLatency,
      totalMessagesSent: _totalMessagesSent,
      totalMessagesReceived: _totalMessagesReceived,
      messageDeliveryRate: _totalMessagesSent > 0 ? _totalMessagesReceived / _totalMessagesSent : 1.0,
      timestamp: DateTime.now(),
    );
  }

  /// Perform a health check on the network
  void _performHealthCheck() {
    final metrics = getHealthMetrics();
    
    for (final handler in _healthChangeHandlers) {
      handler(metrics);
    }
    
    // Log health metrics
    print('Network Health - Peers: ${metrics.connectedPeers}, '
          'Avg Latency: ${metrics.averageLatency.toStringAsFixed(2)}ms, '
          'Delivery Rate: ${(metrics.messageDeliveryRate * 100).toStringAsFixed(2)}%');
  }

  /// Share routing table with peers using gossip protocol
  void _gossipRoutingTable() {
    final payload = json.encode({
      'table': _routingTable,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    final routingTableMessage = NetworkMessage(
      type: MessageType.routingTable,
      fromPeerId: _localPeerId,
      payload: utf8.encode(payload),
      sequenceNumber: 0,
    );
    
    // Send routing table to random subset of peers (gossip protocol)
    final peers = getPeers();
    final peerList = peers.keys.toList();
    
    // Select random subset (up to 3 peers)
    final random = Random();
    final gossipCount = peerList.length < 3 ? peerList.length : 3;
    
    for (int i = 0; i < gossipCount; i++) {
      final randomPeerId = peerList[random.nextInt(peerList.length)];
      _transport.sendMessage(routingTableMessage, peerId: randomPeerId);
    }
  }

  /// Handle internal messages (heartbeat, routing table, etc.)
  int _handleInternalMessage(IncomingMessage incoming) {
    final message = incoming.message;
    _totalMessagesReceived++;
    
    switch (message.type) {
      case MessageType.heartbeat:
        // Update peer status in routing table
        final peer = Peer(
          id: message.fromPeerId,
          address: incoming.address,
          port: incoming.port,
          lastSeen: DateTime.now(),
          isOnline: true,
        );
        addPeer(peer);
        break;
        
      case MessageType.routingTable:
        // Update local routing table with received information
        final payload = json.decode(utf8.decode(message.payload));
        final receivedTable = payload['table'] as Map<String, dynamic>;
        for (final entry in receivedTable.entries) {
          final peerId = entry.key;
          final addressPort = entry.value as String;
          
          if (!_routingTable.containsKey(peerId)) {
            final parts = addressPort.split(':');
            if (parts.length == 2) {
              final address = parts[0];
              final port = int.tryParse(parts[1]);
              
              if (port != null) {
                _routingTable[peerId] = addressPort;
                
                // Add to transport if not already known
                final peer = Peer(
                  id: peerId,
                  address: address,
                  port: port,
                  lastSeen: DateTime.now(),
                  isOnline: true,
                );
                
                if (!_transport.getPeers().containsKey(peerId)) {
                  _transport.addPeer(peer);
                  
                  // Notify of new peer discovery
                  for (final handler in _peerDiscoveryHandlers) {
                    handler(peer);
                  }
                }
              }
            }
          }
        }
        _notifyRoutingTableChange();
        break;
        
      case MessageType.performanceMetrics:
        // Handle received performance metrics
        // In a real implementation, this would update performance tracking
        break;
        
      default:
        // For other message types, the application would handle them
        break;
    }
    
    return 0; // Return value required by the message handler interface
  }

  /// Notify all routing table change handlers
  void _notifyRoutingTableChange() {
    final peers = getPeers();
    for (final handler in _routingTableChangeHandlers) {
      handler(peers);
    }
  }

  /// Get network statistics
  Map<String, dynamic> getNetworkStatistics() {
    return {
      'localPeerId': _localPeerId,
      'localPort': _transport.localPort,
      'connectedPeers': getPeers().length,
      'totalMessagesSent': _totalMessagesSent,
      'totalMessagesReceived': _totalMessagesReceived,
      'routingTableSize': _routingTable.length,
      'lastHealthCheck': _lastHealthCheck.toIso8601String(),
    };
  }

  /// Close the network abstraction layer
  void close() {
    _gossipTimer?.cancel();
    _healthCheckTimer?.cancel();
    _transport.close();
  }
}