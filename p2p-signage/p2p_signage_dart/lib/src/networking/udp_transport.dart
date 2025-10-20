import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:p2p_signage/src/networking/i_transport.dart';
import 'package:p2p_signage/src/networking/message_event.dart';
import 'package:p2p_signage/src/util/rate_limiter.dart';

const stunBindingRequest = 0x0001;
const stunBindingResponse = 0x0101;
const stunXorMappedAddress = 0x0020;
const stunMagicCookie = 0x2112A442;

class UdpTransport implements ITransport {
  final int port;
  RawDatagramSocket? _socket;
  final _messageController = StreamController<MessageEvent>.broadcast();
  final _rateLimiter = RateLimiter(10, const Duration(seconds: 10));

  Completer<StunAddress?>? _stunCompleter;
  Uint8List? _stunTransactionId;

  UdpTransport([this.port = 0]);

  @override
  Stream<MessageEvent> get messages => _messageController.stream;

  int get localPort => _socket?.port ?? 0;

  void _log(String direction, String remoteAddress, int remotePort, String message) {
    final timestamp = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    final localPort = _socket?.port ?? 0;
    final messagePreview = message.length > 50 ? '${message.substring(0, 50)}...' : message;
    print('[UDP_LOG] [$direction] [$timestamp] [$localPort] [$remoteAddress:$remotePort] [$messagePreview]');
  }

  @override
  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _socket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram != null) {
          if (_stunTransactionId != null) {
            final stunAddress = _parseStunResponse(datagram.data, _stunTransactionId!);
            if (stunAddress != null) {
              if (!(_stunCompleter?.isCompleted ?? true)) {
                _stunCompleter?.complete(stunAddress);
              }
              _stunTransactionId = null;
              return;
            }
          }

          // if (!_rateLimiter.isAllowed(datagram.address.address)) {
          //   return;
          // }
          final message = String.fromCharCodes(datagram.data);
          _log('IN', datagram.address.address, datagram.port, message);
          _messageController.add(MessageEvent(datagram.address.address, datagram.port, message));
        }
      }
    });
  }

  @override
  Future<void> stop() async {
    _socket?.close();
    await _messageController.close();
  }

  @override
  Future<void> sendMessage(String address, int port, String message) async {
    if (_socket == null) {
      return;
    }
    final data = utf8.encode(message);
    try {
      _log('OUT', address, port, message);
      _socket!.send(data, InternetAddress(address), port);
    } on SocketException catch (e) {
    } catch (e) {
    }
  }

  Future<StunAddress?> discoverPublicAddress(String stunServer) async {
    if (stunServer == 'disabled') {
      return null;
    }
    final parts = stunServer.split(':');
    if (parts.length != 2) {
      return null;
    }
    final host = parts[0];
    final port = int.tryParse(parts[1]);

    if (port == null) {
      return null;
    }

    _stunTransactionId = _generateTransactionId();
    final request = _buildStunRequest(_stunTransactionId!);

    try {
      final addresses = await InternetAddress.lookup(host);
      if (addresses.isEmpty) return null;
      final address = addresses.first;

      _socket?.send(request, address, port);

      _stunCompleter = Completer<StunAddress?>();
      return await _stunCompleter!.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      return null;
    }
  }

  Uint8List _buildStunRequest(Uint8List transactionId) {
    final buffer = ByteData(20);
    buffer.setUint16(0, stunBindingRequest);
    buffer.setUint16(2, 0); // Message length
    buffer.setUint32(4, stunMagicCookie);
    for (var i = 0; i < 12; i++) {
      buffer.setUint8(8 + i, transactionId[i]);
    }
    return buffer.buffer.asUint8List();
  }

  Uint8List _generateTransactionId() {
    final random = Random();
    final bytes = Uint8List(12);
    for (var i = 0; i < 12; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  StunAddress? _parseStunResponse(Uint8List data, Uint8List transactionId) {
    if (data.length < 20) return null;
    final buffer = ByteData.view(data.buffer);
    final messageType = buffer.getUint16(0);
    if (messageType != stunBindingResponse) return null;

    for (var i = 0; i < 12; i++) {
      if (buffer.getUint8(8 + i) != transactionId[i]) return null;
    }

    var offset = 20;
    while (offset < data.length) {
      if (offset + 4 > data.length) break;
      final attributeType = buffer.getUint16(offset);
      final attributeLength = buffer.getUint16(offset + 2);
      offset += 4;

      if (offset + attributeLength > data.length) break;

      if (attributeType == stunXorMappedAddress) {
        final family = buffer.getUint8(offset + 1);
        if (family == 1) { // IPv4
          final port = buffer.getUint16(offset + 2) ^ (stunMagicCookie >> 16);
          final addressBytes = data.sublist(offset + 4, offset + 8);
          final magicCookieBytes = ByteData(4)..setUint32(0, stunMagicCookie);
          for (var i = 0; i < 4; i++) {
            addressBytes[i] ^= magicCookieBytes.getUint8(i);
          }
          final address = InternetAddress.fromRawAddress(addressBytes).address;
          return StunAddress(address, port);
        }
      }

      offset += attributeLength;
    }

    return null;
  }
}

class StunAddress {
  final String address;
  final int port;

  StunAddress(this.address, this.port);

  @override
  String toString() => '$address:$port';
}
