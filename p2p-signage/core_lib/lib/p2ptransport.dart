import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Represents a peer in the network
class Peer {
  final String id;
  final String address;
  final int port;
  final DateTime lastSeen;
  final bool isOnline;

  Peer({
    required this.id,
    required this.address,
    required this.port,
    DateTime? lastSeen,
    this.isOnline = true,
  }) : lastSeen = lastSeen ?? DateTime.now();
}

/// Message types for network communication
enum MessageType {
  data,
  ack,
  nack,
  heartbeat,
  routingTable,
  performanceMetrics,
  fileTransfer,
}

/// Network message structure
class NetworkMessage {
  final MessageType type;
  final String fromPeerId;
  final String? toPeerId;
  final Uint8List payload;
  final String? checksum;
  final int sequenceNumber;
  final DateTime timestamp;

  NetworkMessage({
    required this.type,
    required this.fromPeerId,
    this.toPeerId,
    required this.payload,
    this.checksum,
    required this.sequenceNumber,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convert to JSON string for transmission
  String toJson() {
    return jsonEncode({
      'type': type.index,
      'fromPeerId': fromPeerId,
      'toPeerId': toPeerId,
      'payload': base64.encode(payload),
      'checksum': checksum,
      'sequenceNumber': sequenceNumber,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  /// Create from JSON string
  static NetworkMessage fromJson(String jsonString) {
    final Map<String, dynamic> json = jsonDecode(jsonString);
    return NetworkMessage(
      type: MessageType.values[json['type']],
      fromPeerId: json['fromPeerId'],
      toPeerId: json['toPeerId'],
      payload: base64.decode(json['payload']),
      checksum: json['checksum'],
      sequenceNumber: json['sequenceNumber'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

/// Represents a message received from the network, including sender info
class IncomingMessage {
  final NetworkMessage message;
  final String address;
  final int port;

  IncomingMessage(this.message, this.address, this.port);
}


/// P2PTransport handles the low-level transport layer for peer-to-peer communication
/// including transmission, integrity verification, and basic message handling
abstract class P2PTransport {
  String get localPeerId;
  int? get localPort;
  String get localAddress;

  Future<void> initialize();
  void addPeer(Peer peer);
  void removePeer(String peerId);
  Map<String, Peer> getPeers();
  void addMessageHandler(int Function(IncomingMessage) handler);
  Future<void> sendMessage(NetworkMessage message, {String? peerId, String? address, int? port});
  Future<bool> sendMessageWithAck(NetworkMessage message, String peerId, {Duration timeout = const Duration(seconds: 10)});
  Stream<IncomingMessage> get messageStream;
  void close();
}

class UdpTransport implements P2PTransport {
  RawDatagramSocket? _socket;
  @override
  final String localPeerId;
  @override
  final String localAddress;
  final int _localPort;
  final Map<String, Peer> _peers = {};
  final Map<String, Completer<bool>> _pendingRequests = {}; // Changed to bool
  final Map<int, NetworkMessage> _sentMessages = {}; // For ACK/NACK protocol
  final List<int Function(IncomingMessage)> _messageHandlers = [];
  int _sequenceNumber = 0;
  Timer? _heartbeatTimer;

  StreamController<IncomingMessage>? _messageStreamController;
  late Stream<IncomingMessage> _messageStream;
  
  UdpTransport({
    required this.localPeerId,
    this.localAddress = '0.0.0.0',
    int localPort = 0,
  }) : _localPort = localPort {
    _messageStreamController = StreamController<IncomingMessage>.broadcast();
    _messageStream = _messageStreamController!.stream;
  }

  @override
  /// Initialize the transport layer
  Future<void> initialize() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _localPort);
    _socket!.listen(_handleSocketEvent);
    
    // Start heartbeat timer
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _sendHeartbeat();
    });
  }

  @override
  /// Get the actual local port assigned by the system
  int? get localPort => _socket?.port;

  @override
  /// Add a peer to the network
  void addPeer(Peer peer) {
    _peers[peer.id] = peer;
  }

  @override
  /// Remove a peer from the network
  void removePeer(String peerId) {
    _peers.remove(peerId);
  }

  @override
  /// Get all known peers
  Map<String, Peer> getPeers() {
    return Map.from(_peers);
  }

  @override
  /// Add a message handler
  void addMessageHandler(int Function(IncomingMessage) handler) {
    _messageHandlers.add(handler);
  }

  @override
  /// Send a message to a specific peer
  Future<void> sendMessage(NetworkMessage message, {String? peerId, String? address, int? port}) async {
    // Calculate sequence number
    message = NetworkMessage(
      type: message.type,
      fromPeerId: localPeerId,
      toPeerId: message.toPeerId,
      payload: message.payload,
      checksum: message.checksum,
      sequenceNumber: _sequenceNumber++,
      timestamp: message.timestamp,
    );

    // Calculate and add checksum if not already present
    if (message.checksum == null) {
      message = NetworkMessage(
        type: message.type,
        fromPeerId: message.fromPeerId,
        toPeerId: message.toPeerId,
        payload: message.payload,
        checksum: _calculateChecksum(message),
        sequenceNumber: message.sequenceNumber,
        timestamp: message.timestamp,
      );
    }

    // Store message for ACK/NACK protocol
    _sentMessages[message.sequenceNumber] = message;

    final jsonString = message.toJson();
    final data = Uint8List.fromList(utf8.encode(jsonString));

    if (peerId != null && _peers.containsKey(peerId)) {
      final peer = _peers[peerId]!;
      _socket!.send(data, InternetAddress(peer.address), peer.port);
    } else if (address != null && port != null) {
      _socket!.send(data, InternetAddress(address), port);
    } else {
      // Broadcast to all peers
      for (final peer in _peers.values) {
        _socket!.send(data, InternetAddress(peer.address), peer.port);
      }
    }
  }

  @override
  /// Send a message with integrity verification and wait for ACK
  Future<bool> sendMessageWithAck(NetworkMessage message, String peerId, {Duration timeout = const Duration(seconds: 10)}) async {
    final completer = Completer<bool>();
    final messageId = message.sequenceNumber.toString();
    _pendingRequests[messageId] = completer;

    await sendMessage(message, peerId: peerId);

    // Set timeout
    Timer(timeout, () {
      if (!completer.isCompleted) {
        _pendingRequests.remove(messageId);
        completer.complete(false);
      }
    });

    return completer.future;
  }

  /// Calculate checksum for message integrity
  String _calculateChecksum(NetworkMessage message) {
    final content = jsonEncode({
      'type': message.type.index,
      'fromPeerId': message.fromPeerId,
      'toPeerId': message.toPeerId,
      'payload': base64.encode(message.payload),
      'sequenceNumber': message.sequenceNumber,
      'timestamp': message.timestamp.toIso8601String(),
    });
    return sha256.convert(utf8.encode(content)).toString();
  }

  /// Verify message integrity
  bool _verifyMessageIntegrity(NetworkMessage message) {
    if (message.checksum == null) return true; // No checksum to verify

    final calculatedChecksum = _calculateChecksum(message);
    return calculatedChecksum == message.checksum;
  }

  /// Handle socket events
  void _handleSocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read && _socket != null) {
      final datagram = _socket!.receive();
      if (datagram != null) {
        try {
          final messageStr = String.fromCharCodes(datagram.data);
          final message = NetworkMessage.fromJson(messageStr);

          // Update peer last seen
          _peers[message.fromPeerId] = Peer(
            id: message.fromPeerId,
            address: datagram.address.address,
            port: datagram.port,
            lastSeen: DateTime.now(),
            isOnline: true,
          );

          // Verify message integrity
          if (!_verifyMessageIntegrity(message)) {
            print('Message integrity failed from ${message.fromPeerId}');
            // Send NACK
            _sendNack(message);
            return;
          }

          // If it's an ACK, complete the pending request
          if (message.type == MessageType.ack) {
            final ackForSeq = message.payload[0];
            final completerId = ackForSeq.toString();
            if (_pendingRequests.containsKey(completerId)) {
              _pendingRequests[completerId]!.complete(true);
              _pendingRequests.remove(completerId);
            }
          } 
          // If it's a NACK, handle retransmission
          else if (message.type == MessageType.nack) {
            final nackForSeq = message.payload[0];
            final reason = String.fromCharCodes(message.payload.sublist(1));
            _handleNack(nackForSeq, reason);
          } 
          // Otherwise, process the message normally
          else {
            // If this is not an ACK/NACK, send ACK back
            if (message.type != MessageType.ack && message.type != MessageType.nack) {
              _sendAck(message);
            }

            final incomingMessage = IncomingMessage(message, datagram.address.address, datagram.port);
            // Process the message
            for (final handler in _messageHandlers) {
              handler(incomingMessage);
            }

            // Add to stream
            _messageStreamController?.add(incomingMessage);
          }
        } catch (e) {
          print('Error processing message: $e');
        }
      }
    }
  }

  /// Send ACK for received message
  void _sendAck(NetworkMessage message) {
    final ackMessage = NetworkMessage(
      type: MessageType.ack,
      fromPeerId: localPeerId,
      toPeerId: message.fromPeerId,
      payload: Uint8List.fromList([message.sequenceNumber]),
      sequenceNumber: _sequenceNumber++,
    );
    
    sendMessage(ackMessage, peerId: message.fromPeerId);
  }

  /// Send NACK for failed message
  void _sendNack(NetworkMessage message) {
    final nackMessage = NetworkMessage(
      type: MessageType.nack,
      fromPeerId: localPeerId,
      toPeerId: message.fromPeerId,
      payload: Uint8List.fromList([message.sequenceNumber] + utf8.encode('integrity_failed')),
      sequenceNumber: _sequenceNumber++,
    );
    
    sendMessage(nackMessage, peerId: message.fromPeerId);
  }

  /// Handle NACK by potentially retransmitting
  void _handleNack(int sequenceNumber, String reason) {
    if (_sentMessages.containsKey(sequenceNumber)) {
      final originalMessage = _sentMessages[sequenceNumber]!;
      print('Received NACK for sequence $sequenceNumber, reason: $reason, retransmitting...');
      // In a real implementation, we would retransmit the message
      // For now, we'll just log it
    }
  }

  /// Send periodic heartbeat to maintain connectivity
  void _sendHeartbeat() {
    final heartbeatMessage = NetworkMessage(
      type: MessageType.heartbeat,
      fromPeerId: localPeerId,
      payload: Uint8List.fromList(DateTime.now().millisecondsSinceEpoch.toString().codeUnits),
      sequenceNumber: _sequenceNumber++,
    );
    
    sendMessage(heartbeatMessage); // Broadcast to all peers
  }

  @override
  /// Get the message stream
  Stream<IncomingMessage> get messageStream => _messageStream;

  @override
  /// Close the transport layer
  void close() {
    _heartbeatTimer?.cancel();
    _socket?.close();
    _messageStreamController?.close();
    
    // Complete all pending requests with error
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Transport closed'));
      }
    }
    _pendingRequests.clear();
  }
}

class TcpTransport implements P2PTransport {
  ServerSocket? _serverSocket;
  final Map<String, Socket> _sockets = {}; // peerId -> Socket
  final Map<String, Peer> _connectedPeers = {}; // peerId -> Peer
  final Map<String, Completer<bool>> _pendingRequests = {}; // Changed to bool
  final Map<int, NetworkMessage> _sentMessages = {}; // For ACK/NACK protocol
  final List<int Function(IncomingMessage)> _messageHandlers = [];
  int _sequenceNumber = 0;
  Timer? _heartbeatTimer; // For TCP connections, if needed

  StreamController<IncomingMessage>? _messageStreamController;
  late Stream<IncomingMessage> _messageStream;

  @override
  final String localPeerId;
  @override
  final String localAddress;
  final int _localPort;

  TcpTransport({
    required this.localPeerId,
    this.localAddress = '0.0.0.0',
    int localPort = 0,
  }) : _localPort = localPort {
    _messageStreamController = StreamController<IncomingMessage>.broadcast();
    _messageStream = _messageStreamController!.stream;
  }

  @override
  Future<void> initialize() async {
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, _localPort);
    _serverSocket!.listen(_handleIncomingConnection);
    print('TCP Listening on ${localAddress}:${_serverSocket!.port}');

    // Start heartbeat timer for TCP connections if necessary
    // _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) {
    //   _sendHeartbeat();
    // });
  }

  @override
  int? get localPort => _serverSocket?.port;

  @override
  void addPeer(Peer peer) {
    _connectedPeers[peer.id] = peer;
  }

  @override
  void removePeer(String peerId) {
    _connectedPeers.remove(peerId);
    _sockets[peerId]?.destroy();
    _sockets.remove(peerId);
  }

  @override
  Map<String, Peer> getPeers() {
    return Map.from(_connectedPeers);
  }

  @override
  void addMessageHandler(int Function(IncomingMessage) handler) {
    _messageHandlers.add(handler);
  }

  @override
  Future<void> sendMessage(NetworkMessage message, {String? peerId, String? address, int? port}) async {
    message = NetworkMessage(
      type: message.type,
      fromPeerId: localPeerId,
      toPeerId: message.toPeerId,
      payload: message.payload,
      checksum: message.checksum,
      sequenceNumber: _sequenceNumber++,
      timestamp: message.timestamp,
    );

    if (message.checksum == null) {
      message = NetworkMessage(
        type: message.type,
        fromPeerId: message.fromPeerId,
        toPeerId: message.toPeerId,
        payload: message.payload,
        checksum: _calculateChecksum(message),
        sequenceNumber: message.sequenceNumber,
        timestamp: message.timestamp,
      );
    }

    _sentMessages[message.sequenceNumber] = message;

    final jsonString = message.toJson();
    final data = utf8.encode(jsonString);

    Socket? targetSocket;
    if (peerId != null && _sockets.containsKey(peerId)) {
      targetSocket = _sockets[peerId];
    } else if (address != null && port != null) {
      // Attempt to connect if not already connected
      final tempPeerId = '$address:$port';
      if (!_sockets.containsKey(tempPeerId)) {
        try {
          final socket = await Socket.connect(address, port);
          _sockets[tempPeerId] = socket;
          _handleSocket(socket, tempPeerId);
          _connectedPeers[tempPeerId] = Peer(id: tempPeerId, address: address, port: port);
          print('TCP Connected to $tempPeerId for sending message.');
        } catch (e) {
          print('Failed to connect to $address:$port: $e');
          return;
        }
      }
      targetSocket = _sockets[tempPeerId];
    }

    if (targetSocket != null) {
      targetSocket.write(data);
      await targetSocket.flush();
    } else {
      print('TCP: No active connection or peer info to send message to.');
    }
  }

  @override
  Future<bool> sendMessageWithAck(NetworkMessage message, String peerId, {Duration timeout = const Duration(seconds: 10)}) async {
    final completer = Completer<bool>();
    final messageId = message.sequenceNumber.toString();
    _pendingRequests[messageId] = completer;

    await sendMessage(message, peerId: peerId);

    Timer(timeout, () {
      if (!completer.isCompleted) {
        _pendingRequests.remove(messageId);
        completer.complete(false);
      }
    });

    return completer.future;
  }

  String _calculateChecksum(NetworkMessage message) {
    final content = jsonEncode({
      'type': message.type.index,
      'fromPeerId': message.fromPeerId,
      'toPeerId': message.toPeerId,
      'payload': base64.encode(message.payload),
      'sequenceNumber': message.sequenceNumber,
      'timestamp': message.timestamp.toIso8601String(),
    });
    return sha256.convert(utf8.encode(content)).toString();
  }

  bool _verifyMessageIntegrity(NetworkMessage message) {
    if (message.checksum == null) return true;

    final calculatedChecksum = _calculateChecksum(message);
    return calculatedChecksum == message.checksum;
  }

  void _handleIncomingConnection(Socket socket) {
    final peerId = '${socket.remoteAddress.address}:${socket.remotePort}';
    print('TCP Incoming connection from $peerId');
    _sockets[peerId] = socket;
    _connectedPeers[peerId] = Peer(id: peerId, address: socket.remoteAddress.address, port: socket.remotePort);
    // _onConnectedController?.add(_connectedPeers[peerId]!); // If we had an onConnected stream

    _handleSocket(socket, peerId);
  }

  void _handleSocket(Socket socket, String peerId) {
    socket.listen(
      (Uint8List data) {
        try {
          final messageStr = utf8.decode(data);
          final message = NetworkMessage.fromJson(messageStr);

          if (!_verifyMessageIntegrity(message)) {
            print('TCP Message integrity failed from ${message.fromPeerId}');
            _sendNack(message);
            return;
          }

          if (message.type == MessageType.ack) {
            final ackForSeq = message.payload[0];
            final completerId = ackForSeq.toString();
            if (_pendingRequests.containsKey(completerId)) {
              _pendingRequests[completerId]!.complete(true);
              _pendingRequests.remove(completerId);
            }
          } else if (message.type == MessageType.nack) {
            final nackForSeq = message.payload[0];
            final reason = String.fromCharCodes(message.payload.sublist(1));
            _handleNack(nackForSeq, reason);
          } else {
            if (message.type != MessageType.ack && message.type != MessageType.nack) {
              _sendAck(message);
            }
            final incomingMessage = IncomingMessage(message, socket.remoteAddress.address, socket.remotePort);
            for (final handler in _messageHandlers) {
              handler(incomingMessage);
            }
            _messageStreamController?.add(incomingMessage);
          }
        } catch (e) {
          print('TCP Error processing message from $peerId: $e');
        }
      },
      onError: (error) {
        print('TCP Socket error for $peerId: $error');
        _sockets.remove(peerId);
        _connectedPeers.remove(peerId);
        // _onDisconnectedController?.add(peerId); // If we had an onDisconnected stream
        socket.destroy();
      },
      onDone: () {
        print('TCP Socket done for $peerId');
        _sockets.remove(peerId);
        _connectedPeers.remove(peerId);
        // _onDisconnectedController?.add(peerId); // If we had an onDisconnected stream
        socket.destroy();
      },
      cancelOnError: true,
    );
  }

  void _sendAck(NetworkMessage message) {
    final ackMessage = NetworkMessage(
      type: MessageType.ack,
      fromPeerId: localPeerId,
      toPeerId: message.fromPeerId,
      payload: Uint8List.fromList([message.sequenceNumber]),
      sequenceNumber: _sequenceNumber++,
    );
    sendMessage(ackMessage, peerId: message.fromPeerId);
  }

  void _sendNack(NetworkMessage message) {
    final nackMessage = NetworkMessage(
      type: MessageType.nack,
      fromPeerId: localPeerId,
      toPeerId: message.fromPeerId,
      payload: Uint8List.fromList([message.sequenceNumber] + utf8.encode('integrity_failed')),
      sequenceNumber: _sequenceNumber++,
    );
    sendMessage(nackMessage, peerId: message.fromPeerId);
  }

  void _handleNack(int sequenceNumber, String reason) {
    if (_sentMessages.containsKey(sequenceNumber)) {
      print('TCP Received NACK for sequence $sequenceNumber, reason: $reason, retransmitting...');
    }
  }

  /// Send periodic heartbeat to maintain connectivity
  void _sendHeartbeat() {
    final heartbeatMessage = NetworkMessage(
      type: MessageType.heartbeat,
      fromPeerId: localPeerId,
      payload: Uint8List(0),
      sequenceNumber: _sequenceNumber++,
    );
    
    // Broadcast to all connected peers
    for (final peerId in _sockets.keys) {
      sendMessage(heartbeatMessage, peerId: peerId);
    }
  }

  @override
  Stream<IncomingMessage> get messageStream => _messageStream;

  @override
  void close() {
    _heartbeatTimer?.cancel();
    _serverSocket?.close();
    for (final socket in _sockets.values) {
      socket.destroy();
    }
    _sockets.clear();
    _connectedPeers.clear();
    _messageStreamController?.close();
    
    // Complete all pending requests with error
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Transport closed'));
      }
    }
    _pendingRequests.clear();
  }
}

class UnifiedP2PTransport implements P2PTransport {
  final UdpTransport _udpTransport;
  final TcpTransport _tcpTransport;
  
  /// Expose TCP transport for advanced usage
  TcpTransport get tcpTransport => _tcpTransport;
  
  /// Expose UDP transport for advanced usage
  UdpTransport get udpTransport => _udpTransport;

  StreamController<IncomingMessage>? _messageStreamController;
  late Stream<IncomingMessage> _messageStream;

  @override
  final String localPeerId;
  @override
  final String localAddress;
  @override
  final int? localPort; // This will be the UDP port for now

  UnifiedP2PTransport({
    required this.localPeerId,
    this.localAddress = '0.0.0.0',
    int udpPort = 0,
    int tcpPort = 0,
  })  : _udpTransport = UdpTransport(localPeerId: localPeerId, localAddress: localAddress, localPort: udpPort),
        _tcpTransport = TcpTransport(localPeerId: localPeerId, localAddress: localAddress, localPort: tcpPort),
        localPort = udpPort
  {
    _messageStreamController = StreamController<IncomingMessage>.broadcast();
    _messageStream = _messageStreamController!.stream;
  }

  @override
  Future<void> initialize() async {
    await _udpTransport.initialize();
    await _tcpTransport.initialize();

    // Merge message streams from both transports
    _udpTransport.messageStream.listen((message) {
      _messageStreamController?.add(message);
    });
    _tcpTransport.messageStream.listen((message) {
      _messageStreamController?.add(message);
    });
  }

  @override
  void addPeer(Peer peer) {
    _udpTransport.addPeer(peer);
    _tcpTransport.addPeer(peer);
  }

  @override
  void removePeer(String peerId) {
    _udpTransport.removePeer(peerId);
    _tcpTransport.removePeer(peerId);
  }

  @override
  Map<String, Peer> getPeers() {
    // Combine peers from both transports, prioritizing TCP if a peer exists in both
    final allPeers = <String, Peer>{};
    _udpTransport.getPeers().forEach((id, peer) => allPeers[id] = peer);
    _tcpTransport.getPeers().forEach((id, peer) => allPeers[id] = peer);
    return allPeers;
  }

  @override
  void addMessageHandler(int Function(IncomingMessage) handler) {
    _udpTransport.addMessageHandler(handler);
    _tcpTransport.addMessageHandler(handler);
  }

  @override
  Future<void> sendMessage(NetworkMessage message, {String? peerId, String? address, int? port}) async {
    // For simplicity, try TCP first, then UDP
    try {
      await _tcpTransport.sendMessage(message, peerId: peerId, address: address, port: port);
    } catch (e) {
      print('TCP send failed, trying UDP: $e');
      await _udpTransport.sendMessage(message, peerId: peerId, address: address, port: port);
    }
  }

  @override
  Future<bool> sendMessageWithAck(NetworkMessage message, String peerId, {Duration timeout = const Duration(seconds: 10)}) async {
    // For simplicity, try TCP first, then UDP
    try {
      return await _tcpTransport.sendMessageWithAck(message, peerId, timeout: timeout);
    } catch (e) {
      print('TCP sendMessageWithAck failed, trying UDP: $e');
      return await _udpTransport.sendMessageWithAck(message, peerId, timeout: timeout);
    }
  }

  @override
  Stream<IncomingMessage> get messageStream => _messageStream;

  @override
  void close() {
    _udpTransport.close();
    _tcpTransport.close();
    _messageStreamController?.close();
  }
}