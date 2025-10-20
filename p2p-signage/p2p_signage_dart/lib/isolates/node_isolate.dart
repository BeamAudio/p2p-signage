import 'dart:async';
import 'dart:isolate';

import 'package:p2p_signage/src/config/config.dart';
import 'package:p2p_signage/src/core/p2p_node.dart';
import 'package:p2p_signage/src/models/message.dart';
import 'package:p2p_signage/src/models/peer.dart';

enum NodeCommand {
  start,
  stop,
  sendMessage,
  getPeers,
  addDonorPeer,
  addDonorPeerSimple,
  getPublicKey,
  getMetrics,
  publishContent,
  getContentStore,
  getLocalPort,
  getLocalIpAddress,
  sendTestMessage,
}

class NodeMessage {
  final NodeCommand command;
  final dynamic data;
  final String? id;

  NodeMessage(this.command, {this.data, this.id});

  Map<String, dynamic> toJson() => {
        'command': command.toString(),
        'data': data,
        'id': id,
      };

  factory NodeMessage.fromJson(Map<String, dynamic> json) => NodeMessage(
        NodeCommand.values.firstWhere((e) => e.toString() == json['command']),
        data: json['data'],
        id: json['id'],
      );
}

class NodeResponse {
  final String id;
  final dynamic data;
  final bool success;
  final String? error;

  NodeResponse(this.id, {this.data, this.success = true, this.error});

  Map<String, dynamic> toJson() => {
        'id': id,
        'data': data,
        'success': success,
        'error': error,
      };

  factory NodeResponse.fromJson(Map<String, dynamic> json) => NodeResponse(
        json['id'],
        data: json['data'],
        success: json['success'],
        error: json['error'],
      );
}

class NodeIsolate {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  final _responseCompleters = <String, Completer<NodeResponse>>{};
  final _messageController = StreamController<Message>.broadcast();

  Stream<Message> get onMessage => _messageController.stream;

  Future<void> start(P2PConfig config) async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, _receivePort!.sendPort);

    final completer = Completer<void>();

    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _sendReceive(NodeCommand.start, data: config.toJson()).then((response) {
          if (response.success) {
            completer.complete();
          } else {
            completer.completeError(Exception(response.error));
          }
        });
      } else if (message is NodeResponse) {
        _responseCompleters[message.id]?.complete(message);
        _responseCompleters.remove(message.id);
      } else if (message is Map<String, dynamic>) {
        if (message.containsKey('id')) {
          final response = NodeResponse.fromJson(message);
          _responseCompleters[response.id]?.complete(response);
          _responseCompleters.remove(response.id);
        } else {
          // This is likely a Message object that was sent as a Map from the isolate
          _messageController.add(Message.fromJson(message));
        }
      }
    });

    return completer.future;
  }

  Future<List<String>> stop() async {
    final response = await _sendReceive(NodeCommand.stop).timeout(const Duration(seconds: 30));
    await Future.delayed(const Duration(milliseconds: 100));
    _receivePort?.close();
    return (response.data as List).cast<String>();
  }

  Future<void> sendMessage(String recipient, String message) async {
    await _sendReceive(NodeCommand.sendMessage, data: {'recipient': recipient, 'message': message});
  }

  Future<List<Peer>> getPeers() async {
    final response = await _sendReceive(NodeCommand.getPeers);
    return (response.data as List).map((p) => Peer.fromJson(p)).toList();
  }

  Future<void> addDonorPeer(Peer peer) async {
    await _sendReceive(NodeCommand.addDonorPeer, data: peer.toJson());
  }

  /// Adds a donor peer with just IP and port.
  Future<void> addDonorPeerSimple(String ip, int port) async {
    await _sendReceive(NodeCommand.addDonorPeerSimple, data: {'ip': ip, 'port': port});
  }

  Future<String> getPublicKey() async {
    final response = await _sendReceive(NodeCommand.getPublicKey);
    return response.data as String;
  }

  Future<int> getLocalPort() async {
    final response = await _sendReceive(NodeCommand.getLocalPort);
    return response.data as int;
  }

  Future<String> getLocalIpAddress() async {
    final response = await _sendReceive(NodeCommand.getLocalIpAddress);
    return response.data as String;
  }

  Future<Map<String, dynamic>> getMetrics() async {
    final response = await _sendReceive(NodeCommand.getMetrics);
    return response.data as Map<String, dynamic>;
  }

  Future<void> publishContent(String contentId, String content) async {
    await _sendReceive(NodeCommand.publishContent, data: {'contentId': contentId, 'content': content});
  }

  Future<Map<String, String>> getContentStore() async {
    final response = await _sendReceive(NodeCommand.getContentStore);
    return Map<String, String>.from(response.data);
  }

  Future<NodeResponse> _sendReceive(NodeCommand command, {dynamic data}) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString() + command.toString();
    final completer = Completer<NodeResponse>();
    _responseCompleters[id] = completer;
    _sendPort?.send(NodeMessage(command, data: data, id: id).toJson());
    return completer.future;
  }

  static void _isolateEntry(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    P2PNode? node;
    final logs = <String>[];

    void log(String message) {
      logs.add(message);
    }

    receivePort.listen((message) async {
      try {
        final nodeMessage = NodeMessage.fromJson(message as Map<String, dynamic>);

        switch (nodeMessage.command) {
          case NodeCommand.start:
            final config = P2PConfig.fromJson(nodeMessage.data);
            node = P2PNode(config, log: log);
            node?.onMessage.listen((message) {
              sendPort.send(message.toJson());
            });
            await node?.start();
            sendPort.send(NodeResponse(nodeMessage.id!, success: true).toJson());
            break;
          case NodeCommand.stop:
            await node?.stop();
            sendPort.send(NodeResponse(nodeMessage.id!, data: logs, success: true).toJson());
            break;
          case NodeCommand.sendMessage:
            final recipient = nodeMessage.data['recipient'];
            final messageContent = nodeMessage.data['message'];
            await node?.sendMessage(recipient, messageContent);
            sendPort.send(NodeResponse(nodeMessage.id!, success: true).toJson());
            break;
          case NodeCommand.getPeers:
            final peers = node?.getPeers().map((p) => p.toJson()).toList();
            sendPort.send(NodeResponse(nodeMessage.id!, data: peers, success: true).toJson());
            break;
          case NodeCommand.getPublicKey:
            final publicKey = await node?.getPublicKey();
            sendPort.send(NodeResponse(nodeMessage.id!, data: publicKey, success: true).toJson());
            break;
          case NodeCommand.addDonorPeer:
            final peer = Peer.fromJson(nodeMessage.data);
            node?.addDonorPeer(peer);
            sendPort.send(NodeResponse(nodeMessage.id!, success: true).toJson());
            break;
          case NodeCommand.addDonorPeerSimple:
            final ip = nodeMessage.data['ip'];
            final port = nodeMessage.data['port'];
            node?.addDonorPeerSimple(ip, port);
            sendPort.send(NodeResponse(nodeMessage.id!, success: true).toJson());
            break;
          case NodeCommand.getMetrics:
            final metrics = node?.getMetrics().toJson();
            sendPort.send(NodeResponse(nodeMessage.id!, data: metrics, success: true).toJson());
            break;
          case NodeCommand.publishContent:
            final contentId = nodeMessage.data['contentId'];
            final content = nodeMessage.data['content'];
            await node?.publishContent(contentId, content);
            sendPort.send(NodeResponse(nodeMessage.id!, success: true).toJson());
            break;
          case NodeCommand.getContentStore:
            final contentStore = node?.getContentStore();
            sendPort.send(NodeResponse(nodeMessage.id!, data: contentStore, success: true).toJson());
            break;
          case NodeCommand.getLocalPort:
            final port = node?.localPort;
            sendPort.send(NodeResponse(nodeMessage.id!, data: port, success: true).toJson());
            break;
          case NodeCommand.getLocalIpAddress:
            final ipAddress = node?.localIpAddress;
            sendPort.send(NodeResponse(nodeMessage.id!, data: ipAddress, success: true).toJson());
            break;
          case NodeCommand.sendTestMessage:
            // Directly add a test message to the main isolate's _messageController
            sendPort.send(Message(sender: 'isolate_test_sender', recipient: 'main_isolate', content: 'This is a test message from isolate', timestamp: DateTime.now()).toJson());
            sendPort.send(NodeResponse(nodeMessage.id!, success: true).toJson());
            break;
        }
      } catch (e) {
        log('Error in isolate: $e');
      }
    });
  }
}