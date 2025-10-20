import 'dart:async';

import 'package:p2p_signage/src/networking/message_event.dart';

abstract class ITransport {
  Future<void> start();
  Future<void> stop();
  Future<void> sendMessage(String address, int port, String message);
  Stream<MessageEvent> get messages;
}
