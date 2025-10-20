import 'dart:async';
import 'dart:convert';

import 'package:p2p_signage/src/config/config.dart';
import 'package:p2p_signage/src/core/peer_manager.dart';
import 'package:p2p_signage/src/models/message.dart';
import 'package:p2p_signage/src/models/peer.dart';
import 'package:p2p_signage/src/networking/udp_transport.dart';
import 'package:p2p_signage/src/security/crypto_service.dart';
import 'package:p2p_signage/src/security/auth_service.dart';
import 'package:p2p_signage/src/core/metrics.dart';
import 'package:p2p_signage/src/util/rate_limiter.dart';
import 'package:p2p_signage/src/util/network_utils.dart';
import 'package:cryptography/cryptography.dart';

/// Represents a pending message awaiting an ACK
class PendingMessage {
  final String id;
  final String recipient;
  final String message;
  final String serializedEnvelope;
  DateTime sentTime;  // Made mutable to allow updating for retransmission tracking
  final Completer<bool> completer;
  int retryCount = 0;

  PendingMessage({
    required this.id,
    required this.recipient,
    required this.message,
    required this.serializedEnvelope,
    required this.sentTime,
    required this.completer,
  });
}

class P2PNode {
  final P2PConfig _config;
  final PeerManager _peerManager;
  final CryptoService _cryptoService;
  final UdpTransport _udpTransport;
  final AuthService _authService;
  final StreamController<Message> _messageController;
  final Metrics _metrics;
  final Map<String, SecretKey> _sharedSecrets;
  final Map<String, String> _contentStore;
  Timer? _gossipTimer;
  Timer? _cleanupTimer;
  final void Function(String) log;

  // NEW: For ACK-based control protocol
  final Map<String, PendingMessage> _pendingMessages = {};
  final Map<String, Set<String>> _ackedMessages = {};
  Timer? _retransmissionTimer;
  late String ipAddress; // Declared as a class member

  P2PNode(this._config, {required this.log}) :
    _peerManager = PeerManager(),
    _cryptoService = CryptoService(),
    _udpTransport = UdpTransport(0),
    _authService = AuthService(CryptoService()),
    _messageController = StreamController<Message>.broadcast(),
    _metrics = Metrics(),
    _sharedSecrets = {},
    _contentStore = {} {
    log('${_config.username}: P2PNode _messageController initialized.');
  }

  Future<void> start() async {
    log('${_config.username}: Starting node...');
    await _cryptoService.init();
    await _udpTransport.start();

    int port = _udpTransport.localPort;

    if (_config.forceLocalhost) {
      ipAddress = '127.0.0.1'; // Initialize class member
      log('${_config.username}: Using localhost mode: $ipAddress:$port');
    } else {
      // Use STUN to discover public IP and port
      log('${_config.username}: Discovering public address using STUN server: ${_config.stunServer}');
      final publicAddress = await _udpTransport.discoverPublicAddress(_config.stunServer);
      if (publicAddress != null) {
        ipAddress = publicAddress.address; // Initialize class member
        port = publicAddress.port;
        log('${_config.username}: Discovered public address: $ipAddress:$port');
      } else {
        // Fallback to local IP if STUN fails
        log('${_config.username}: STUN discovery failed, falling back to local IP');
        ipAddress = await NetworkUtils.getLocalIpAddress(); // Initialize class member
        port = _udpTransport.localPort;
        log('${_config.username}: Using local address: $ipAddress:$port');
      }
    }
    
    log('${_config.username}: Using IP: $ipAddress:$port');

    final self = Peer(
      username: _config.username,
      ip: ipAddress,
      port: port,
      publicKey: await _cryptoService.publicKey,
      lastSeen: DateTime.now(),
      isAuthenticated: true,
    );
    _peerManager.addPeer(self);
    _peerManager.onPeerAdded((peer) {
      log('${_config.username}: Peer added: ${peer.username} (${peer.ip}:${peer.port})');
      _metrics.peersDiscovered++;
      _authenticatePeer(peer);
    });

    _udpTransport.messages.listen((event) {
      _handleMessage(event.data, event.address, event.port);
    });

    _gossipTimer = Timer.periodic(Duration(seconds: _config.gossipInterval), (timer) {
      _performGossip();
    });

    _cleanupTimer = Timer.periodic(Duration(seconds: _config.peerCleanupInterval), (timer) {
      _peerManager.cleanupInactivePeers(Duration(seconds: _config.messageTimeoutSeconds * 2)); // Example: 2x message timeout
    });

    // NEW: Start retransmission timer for ACK-based control protocol
    _retransmissionTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      _processRetransmissions();
    });

    log('${_config.username}: Node started.');
  }
  
  Future<void> stop() async {
    log('${_config.username}: Stopping node...');
    _gossipTimer?.cancel();
    _cleanupTimer?.cancel();
    _retransmissionTimer?.cancel();
    await _udpTransport.stop();
    log('${_config.username}: Node stopped.');
  }

  /// Gets the actual IP address to use for sending messages to a peer.
  /// For peers on the same machine in a local test environment, uses loopback address (127.0.0.1) instead of public IP.
  String _getPeerSendAddress(Peer peer) {
    if (_config.forceLocalhost) {
      return '127.0.0.1';
    }
    return peer.ip;
  }

  // NEW: Process retransmissions for unacknowledged messages
  void _processRetransmissions() {
    final now = DateTime.now();
    final toRemove = <String>[];
    
    for (final entry in _pendingMessages.entries) {
      final pendingMessage = entry.value;
      
      // Check if message needs to be retransmitted (after 2 seconds)
      if (now.difference(pendingMessage.sentTime).inSeconds >= 2) {
        if (pendingMessage.retryCount < 3) { // Max 3 retries
          log('${_config.username}: Retransmitting message ${pendingMessage.id} to ${pendingMessage.recipient}');
          
          // Find the peer's address again
          String sendAddress;
          int sendPort;
          
          final peer = _peerManager.getPeers().firstWhere((p) => p.username == pendingMessage.recipient, orElse: () => 
              Peer(username: pendingMessage.recipient, ip: '', port: 0, publicKey: '', lastSeen: DateTime.now())
          );
          
          if (_config.forceLocalhost) {
            sendAddress = '127.0.0.1';
            sendPort = peer.port;
          } else {
            sendAddress = peer.ip;
            sendPort = peer.port;
          }
          
          // Send the message again
          _udpTransport.sendMessage(sendAddress, sendPort, pendingMessage.serializedEnvelope);
          
          // Update retry count and sent time
          pendingMessage.retryCount++;
          pendingMessage.sentTime = now; // Update the sent time for the retransmission
        } else {
          log('${_config.username}: Max retries reached for message ${pendingMessage.id}, marking as failed');
          pendingMessage.completer.complete(false);
          toRemove.add(entry.key);
        }
      }
    }
    
    // Remove messages that have reached max retries
    for (final key in toRemove) {
      _pendingMessages.remove(key);
    }
  }

  // NEW: Send message with ACK and retry mechanism
  Future<bool> sendMessage(String recipient, String message, {bool encryptMessage = true, bool requireAck = true}) async {
    log('${_config.username}: Sending message to $recipient: $message');
    log('${_config.username}: All peers in sendMessage: ${_peerManager.getPeers().map((p) => p.username).toList()}');
    _metrics.messagesSent++;
    
    // Debug logging to see all peers
    final allPeers = _peerManager.getPeers();
    log('${_config.username}: All peers: ${allPeers.map((p) => '${p.username} (${p.ip}:${p.port})').toList()}');
    
    final peer = _peerManager.getPeers().firstWhere((p) => p.username == recipient);
    
    // Determine the correct address to send to based on forceLocalhost flag
    String sendAddress;
    int sendPort = peer.port;
    
    if (_config.forceLocalhost) {
      // In localhost mode, always send to 127.0.0.1
      sendAddress = '127.0.0.1';
      // Use the peer's port (which should be the local port)
      sendPort = peer.port;
    } else {
      // In normal mode, use the peer's advertised public IP and port
      sendAddress = peer.ip;
      sendPort = peer.port;
    }
    
    log('${_config.username}: Found peer for recipient $recipient: ${peer.username} (${sendAddress}:${sendPort})');

    String messageToSend;
    String signatureData;

    if (encryptMessage) {
      final sharedSecret = _sharedSecrets[recipient];
      if (sharedSecret == null) {
        log('${_config.username}: No shared secret with $recipient. Cannot send encrypted message.');
        return false;
      }
      final encryptedMessage = await _cryptoService.encrypt(message, sharedSecret);
      messageToSend = json.encode({
        'cipherText': base64Url.encode(encryptedMessage.cipherText),
        'nonce': base64Url.encode(encryptedMessage.nonce),
        'mac': base64Url.encode(encryptedMessage.mac.bytes),
      });
      signatureData = base64Url.encode(encryptedMessage.cipherText);
    } else {
      messageToSend = message;
      signatureData = message;
    }

    // NEW: Generate a unique ID for ACK tracking
    final messageId = DateTime.now().millisecondsSinceEpoch.toString() + recipient;
    final envelope = {
      'sender': _config.username,
      'publicKey': await _cryptoService.publicKey,
      'signature': await _cryptoService.sign(signatureData),
      'message': messageToSend,
      // NEW: Add message ID and requireAck flag to envelope
      'messageId': messageId,
      'requireAck': requireAck,
    };
    
    final serializedEnvelope = json.encode(envelope);
    log('${_config.username}: Sending UDP message to ${sendAddress}:${sendPort}: $serializedEnvelope');
    
    // NEW: If requiring ACK, store pending message and send with retries
    if (requireAck) {
      final completer = Completer<bool>();
      final pendingMessage = PendingMessage(
        id: messageId,
        recipient: recipient,
        message: message,
        serializedEnvelope: serializedEnvelope,
        sentTime: DateTime.now(),
        completer: completer,
      );
      
      _pendingMessages[messageId] = pendingMessage;
      await _udpTransport.sendMessage(sendAddress, sendPort, serializedEnvelope);
      log('${_config.username}: Sent message with ID $messageId to ${sendAddress}:${sendPort}');
      
      // Wait for ack or timeout
      return completer.future.timeout(
        Duration(seconds: _config.messageTimeoutSeconds),
        onTimeout: () {
          log('${_config.username}: Message $messageId to $recipient timed out');
          _pendingMessages.remove(messageId);
          return false;
        },
      );
    } else {
      // For non-ACK messages, send once and return true immediately
      await _udpTransport.sendMessage(sendAddress, sendPort, serializedEnvelope);
      log('${_config.username}: Sent non-ACK message to ${sendAddress}:${sendPort}');
      return true;
    }
  }

  void addDonorPeer(Peer peer) {
    _peerManager.addPeer(peer);
    _authenticatePeer(peer);
  }

  /// Adds a donor peer with just IP and port.
  /// The system will discover additional information when the peer communicates.
  void addDonorPeerSimple(String ip, int port) {
    // Create a minimal peer with the provided information
    // Username will be set when the peer sends its first message
    
    // Adjust IP based on forceLocalhost setting
    String correctIp = ip;
    int correctPort = port;
    
    if (_config.forceLocalhost) {
      // In localhost mode, always use 127.0.0.1 for local peers
      correctIp = '127.0.0.1';
    }
    
    final peer = Peer(
      username: 'unknown', // Will be updated when peer communicates
      ip: correctIp,
      port: correctPort,
      publicKey: '', // Will be updated when peer communicates
      lastSeen: DateTime.now(),
      isAuthenticated: false,
    );
    _peerManager.addPeer(peer);
    _authenticatePeer(peer);
  }

  Future<void> publishContent(String contentId, String content) async {
    _contentStore[contentId] = content;
    final contentAnnouncement = {
      'type': 'content-announcement',
      'contentId': contentId,
      'contentHash': await _cryptoService.sign(content), // Using sign as a simple hash for now
    };
    for (final peer in _peerManager.getPeers()) {
      if (peer.username != _config.username && peer.isAuthenticated) {
        await sendMessage(peer.username, json.encode(contentAnnouncement), requireAck: false);
      }
    }
  }

  Future<String> getPublicKey() async {
    return await _cryptoService.publicKey;
  }

  List<Peer> getPeers() {
    return _peerManager.getPeers();
  }

  Metrics getMetrics() {
    return _metrics;
  }

  Map<String, String> getContentStore() {
    return _contentStore;
  }

  Stream<Message> get onMessage => _messageController.stream;

  int get localPort => _udpTransport.localPort;

  String get localIpAddress => ipAddress; // New getter

  void _performGossip() async {
    log('${_config.username}: Performing gossip...');
    _metrics.gossipMessagesSent++;
    final peers = _peerManager.getPeers();
    log('${_config.username}: Gossiping to ${peers.map((p) => '${p.username} (${p.ip}:${p.port})').toList()}');
    
    // Create a list of peers with correct addresses based on forceLocalhost setting
    final List<Map<String, dynamic>> peersForGossip = [];
    for (final peer in peers) {
      String gossipIp = peer.ip;
      int gossipPort = peer.port;
      
      if (_config.forceLocalhost && peer.ip != '127.0.0.1') {
        // In localhost mode, advertise ourselves as 127.0.0.1 to other localhost peers
        gossipIp = '127.0.0.1';
      }
      
      peersForGossip.add({
        'username': peer.username,
        'ip': gossipIp,
        'port': gossipPort,
        'publicKey': peer.publicKey,
        'lastSeen': peer.lastSeen.toIso8601String(),
        'isAuthenticated': peer.isAuthenticated,
      });
    }
    
    final gossipMessage = {
      'type': 'gossip',
      'peers': peersForGossip,
    };
    
    for (final peer in peers) {
      if (peer.username != _config.username && peer.isAuthenticated) {
        try {
          await sendMessage(peer.username, json.encode(gossipMessage), requireAck: false);
        } catch (e) {
          log('Error gossiping to ${peer.username}: $e');
        }
      }
    }
  }

  void _authenticatePeer(Peer peer) async {
    if (peer.username == _config.username) return;
    log('${_config.username}: Authenticating peer: ${peer.username}');
    _metrics.authenticationAttempts++;
    final challenge = _authService.createChallenge();
    final message = {
      'type': 'auth-challenge',
      'challenge': challenge,
      'x25519PublicKey': await _cryptoService.x25519PublicKey,
      'publicKey': await _cryptoService.publicKey,
    };
    await sendMessage(peer.username, json.encode(message), encryptMessage: false, requireAck: false);
  }

  void _handleMessage(String message, String senderAddress, int senderPort) async {
    log('${_config.username}: Received message from $senderAddress:$senderPort');
    log('${_config.username}: Received message from $senderAddress:$senderPort: $message');
    _metrics.messagesReceived++;
    
    // Prevent nodes from processing messages from themselves
    if (_config.forceLocalhost && senderAddress == '127.0.0.1' && senderPort == _udpTransport.localPort) {
      log('${_config.username}: Ignoring message from self ($senderAddress:$senderPort)');
      return;
    }
    
    log('${_config.username}: Processing message from $senderAddress:$senderPort');
    
    try {
      final decodedMessage = json.decode(message);
      final signature = decodedMessage['signature'];
      final publicKey = decodedMessage['publicKey'];
      final messageContent = decodedMessage['message'];
      final senderUsername = decodedMessage['sender'];
      
      // NEW: Check if this is an ACK message
      if (decodedMessage['type'] == 'ack') {
        final ackId = decodedMessage['ackId'];
        log('${_config.username}: Received ACK for message ID: $ackId');
        
        // Complete the pending message if it exists
        final pendingMessage = _pendingMessages[ackId];
        if (pendingMessage != null) {
          pendingMessage.completer.complete(true);
          _pendingMessages.remove(ackId);
          log('${_config.username}: Message $ackId acknowledged successfully');
        }
        return;
      }
      
      // NEW: Check for message ID and send ACK if required
      final requireAck = decodedMessage['requireAck'] ?? false;
      final messageId = decodedMessage['messageId'];
      
      if (requireAck && messageId != null) {
        // Send ACK back to sender
        final ackMessage = {
          'type': 'ack',
          'ackId': messageId,
          'sender': _config.username,
          'publicKey': await _cryptoService.publicKey,
          'signature': await _cryptoService.sign(messageId),
        };
        
        log('${_config.username}: Sending ACK for message ID: $messageId to $senderUsername');
        
        // Determine the correct address to send the ACK to
        String ackAddress;
        int ackPort;
        
        if (_config.forceLocalhost) {
          ackAddress = '127.0.0.1';
          ackPort = senderPort;
        } else {
          ackAddress = senderAddress;
          ackPort = senderPort;
        }
        
        _udpTransport.sendMessage(ackAddress, ackPort, json.encode(ackMessage));
      }
      
      var messageData;
      try {
        messageData = json.decode(messageContent);
      } catch (e) {
        messageData = messageContent;
      }

      String signedData;
      if (messageData is Map && messageData['cipherText'] != null) {
        // Encrypted message, signature is on cipherText
        signedData = messageData['cipherText'];
      } else if (messageData is Map) {
        // Unencrypted message, signature is on the message content itself
        signedData = json.encode(messageData);
      } else {
        signedData = messageContent;
      }
      log('${_config.username}: signedData: $signedData');
      log('${_config.username}: signature: $signature');

var peer = _peerManager.getPeers().firstWhere((p) => p.username == senderUsername, orElse: () {
        // If we don't have a peer with the sender's username, try to find an existing peer with matching IP and port
        // This handles the case where we added a donor peer with 'unknown' username but now know the real username
        try {
          Peer existingPeer = _peerManager.getPeers().firstWhere(
            (p) => p.ip == senderAddress && p.port == senderPort && p.username == 'unknown',
          );
          
          // Update the existing peer with the correct username and public key
          // But adjust the IP based on forceLocalhost setting
          String correctIp = senderAddress;
          int correctPort = senderPort;
          
          if (_config.forceLocalhost) {
            // In localhost mode, use 127.0.0.1 for local peers
            correctIp = '127.0.0.1';
          }
          
          _peerManager.removePeer(existingPeer);
          final updatedPeer = Peer(
            username: senderUsername,
            ip: correctIp,
            port: correctPort,
            publicKey: publicKey,
            lastSeen: DateTime.now(),
            isAuthenticated: existingPeer.isAuthenticated,
          );
          _peerManager.addPeer(updatedPeer);
          return updatedPeer;
        } on StateError {
          // No existing peer with matching IP and port found, create a new peer
          // But use the correct IP based on forceLocalhost setting
          String correctIp = senderAddress;
          int correctPort = senderPort;
          
          if (_config.forceLocalhost) {
            // In localhost mode, use 127.0.0.1 for local peers
            correctIp = '127.0.0.1';
          }
          
          final newPeer = Peer(
            username: senderUsername,
            ip: correctIp,
            port: correctPort,
            publicKey: publicKey,
            lastSeen: DateTime.now(),
            isAuthenticated: false,
          );
          _peerManager.addPeer(newPeer);
          return newPeer;
        }
      });
      
      // Update the last seen time for the existing peer and refresh public key
      // Also ensure the IP is correct based on forceLocalhost setting
      String correctIp = peer.ip;
      int correctPort = peer.port;
      
      if (_config.forceLocalhost) {
        // In localhost mode, use 127.0.0.1 for local peers
        correctIp = '127.0.0.1';
        correctPort = senderPort; // Use the sender's port
      } else {
        // In normal mode, use the sender's actual IP and port
        correctIp = senderAddress;
        correctPort = senderPort;
      }
      
      peer = Peer(
        username: peer.username,
        ip: correctIp,
        port: correctPort,
        publicKey: publicKey, // Update public key in case it changed
        lastSeen: DateTime.now(),
        isAuthenticated: peer.isAuthenticated,
      );
      _peerManager.addPeer(peer);

      if (await _cryptoService.verify(signedData, signature, publicKey)) {
        String decryptedContent;
        if (messageData is Map &&
            messageData['cipherText'] != null &&
            messageData['nonce'] != null &&
            messageData['mac'] != null) {
          // Encrypted message
          final sharedSecret = _sharedSecrets[senderUsername];
          if (sharedSecret == null) {
            log('${_config.username}: No shared secret with $senderUsername. Cannot decrypt message.');
            return;
          }
          final cipherText = base64Url.decode(messageData['cipherText']);
          final nonce = base64Url.decode(messageData['nonce']);
          final mac = Mac(base64Url.decode(messageData['mac']));
          final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
          decryptedContent = await _cryptoService.decrypt(secretBox, sharedSecret);
        } else {
          // Unencrypted message (e.g., auth messages)
          decryptedContent = messageContent;
        }

        try {
          final messageJson = json.decode(decryptedContent);
          final messageType = messageJson['type'];
          log('${_config.username}: Decrypted message type: $messageType');

          switch (messageType) {
            case 'gossip':
              _handleGossipMessage(messageJson);
              break;
            case 'auth-challenge':
              _handleAuthChallenge(senderUsername, publicKey, messageJson);
              break;
            case 'auth-response':
              _handleAuthResponse(senderUsername, messageJson);
              break;
            case 'content-announcement':
              _handleContentAnnouncement(senderUsername, messageJson);
              break;
            case 'content-request':
              _handleContentRequest(senderUsername, messageJson);
              break;
            case 'content-data':
              _handleContentData(senderUsername, messageJson);
              break;
            default:
              log('${_config.username}: Handling generic message: $decryptedContent');
              // Handle generic application messages
              _messageController.add(Message(
                sender: senderUsername,
                recipient: _config.username,
                content: decryptedContent,
                timestamp: DateTime.now(),
              ));
              break;
          }
        } on FormatException {
          // If it's not a JSON message, treat it as a generic message
          _messageController.add(Message(
            sender: senderUsername,
            recipient: _config.username,
            content: decryptedContent,
            timestamp: DateTime.now(),
          ));
        }
      }
    } catch (e) {
      log('Error handling message: $e');
    }
    log('${_config.username}: Finished processing message from $senderAddress:$senderPort');
  }

  void _handleGossipMessage(Map<String, dynamic> messageData) {
    log('${_config.username}: Handling gossip message: $messageData');
    _metrics.gossipMessagesReceived++;
    final peers = (messageData['peers'] as List)
        .map((p) => Peer.fromJson(p))
        .toList();
    
    // Adjust peer addresses based on forceLocalhost setting
    final List<Peer> adjustedPeers = [];
    for (final peer in peers) {
      String correctIp = peer.ip;
      int correctPort = peer.port;
      
      if (_config.forceLocalhost && peer.ip != '127.0.0.1') {
        // In localhost mode, use 127.0.0.1 for local peers
        correctIp = '127.0.0.1';
      }
      
      final adjustedPeer = Peer(
        username: peer.username,
        ip: correctIp,
        port: correctPort,
        publicKey: peer.publicKey,
        lastSeen: peer.lastSeen,
        isAuthenticated: peer.isAuthenticated,
      );
      adjustedPeers.add(adjustedPeer);
    }
    
    for (final peer in adjustedPeers) {
      _peerManager.addPeer(peer);
    }
  }

  void _handleAuthChallenge(String sender, String publicKey, Map<String, dynamic> messageData) async {
    log('${_config.username}: Handling auth challenge from $sender');
    final challenge = messageData['challenge'];
    final remoteX25519PublicKey = messageData['x25519PublicKey'];
    final sharedSecret = await _cryptoService.deriveSharedSecret(remoteX25519PublicKey);
    _sharedSecrets[sender] = sharedSecret;

    final response = await _cryptoService.sign(challenge);
    final message = {
      'type': 'auth-response',
      'challenge': challenge,
      'response': response,
      'publicKey': await _cryptoService.publicKey,
      'x25519PublicKey': await _cryptoService.x25519PublicKey,
    };
    sendMessage(sender, json.encode(message), encryptMessage: false, requireAck: false);
  }

  void _handleAuthResponse(String sender, Map<String, dynamic> messageData) async {
    log('${_config.username}: Handling auth response from $sender');
    final challenge = messageData['challenge'];
    final response = messageData['response'];
    final publicKey = messageData['publicKey'];
    final remoteX25519PublicKey = messageData['x25519PublicKey'];

    final isAuthenticated = await _authService.verifyResponse(challenge, response, publicKey);
    if (isAuthenticated) {
      final sharedSecret = await _cryptoService.deriveSharedSecret(remoteX25519PublicKey);
      _sharedSecrets[sender] = sharedSecret;
      _peerManager.setAuthenticated(sender, true);
      
      // Immediately send our peer list to the newly authenticated peer
      // to accelerate mesh formation
      final gossipMessage = {
        'type': 'gossip',
        'peers': _peerManager.getPeers().map((p) => p.toJson()).toList(),
      };
      await sendMessage(sender, json.encode(gossipMessage), requireAck: false);
      
      // Trigger an immediate gossip round to help propagate the new authentication
      // This helps speed up mesh formation by quickly spreading the authentication info
      _performGossip();
    }
  }

  void _handleContentAnnouncement(String sender, Map<String, dynamic> messageData) async {
    log('${_config.username}: Handling content announcement from $sender: $messageData');
    final contentId = messageData['contentId'];
    final contentHash = messageData['contentHash'];

    if (!_contentStore.containsKey(contentId)) {
      log('${_config.username}: Requesting content $contentId from $sender');
      final contentRequest = {
        'type': 'content-request',
        'contentId': contentId,
      };
      await sendMessage(sender, json.encode(contentRequest));
    }
  }

  void _handleContentRequest(String sender, Map<String, dynamic> messageData) async {
    log('${_config.username}: Handling content request from $sender: $messageData');
    final contentId = messageData['contentId'];

    if (_contentStore.containsKey(contentId)) {
      final content = _contentStore[contentId];
      final contentData = {
        'type': 'content-data',
        'contentId': contentId,
        'content': content,
      };
      log('${_config.username}: Sending content $contentId to $sender');
      await sendMessage(sender, json.encode(contentData)); // Content data should use ACK mechanism
    } else {
      log('${_config.username}: Content $contentId not found for request from $sender');
    }
  }

  void _handleContentData(String sender, Map<String, dynamic> messageData) {
    log('${_config.username}: Handling content data from $sender: $messageData');
    final contentId = messageData['contentId'];
    final content = messageData['content'];
    _contentStore[contentId] = content;
    log('${_config.username}: Stored content $contentId');
  }
}
