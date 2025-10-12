import 'dart:typed_data';

class DhtProtocol {
  static const int PING = 0x01;
  static const int PONG = 0x02;
  static const int FIND_NODE = 0x03;
  static const int FOUND_NODE = 0x04;
  static const int STORE = 0x05;

  static Uint8List createPing(int rpcId, Uint8List peerInfo) {
    final buffer = BytesBuilder();
    buffer.addByte(PING);
    buffer.add(Uint8List(4)..buffer.asByteData().setInt32(0, rpcId));
    buffer.add(peerInfo);
    return buffer.toBytes();
  }

  static Uint8List createPong(int rpcId, Uint8List peerInfo) {
    final buffer = BytesBuilder();
    buffer.addByte(PONG);
    buffer.add(Uint8List(4)..buffer.asByteData().setInt32(0, rpcId));
    buffer.add(peerInfo);
    return buffer.toBytes();
  }

  static Uint8List createFindNode(int rpcId, Uint8List targetId) {
    final buffer = BytesBuilder();
    buffer.addByte(FIND_NODE);
    buffer.add(Uint8List(4)..buffer.asByteData().setInt32(0, rpcId));
    buffer.add(targetId);
    return buffer.toBytes();
  }

  static Uint8List createFoundNode(int rpcId, List<Uint8List> nodes) {
    final buffer = BytesBuilder();
    buffer.addByte(FOUND_NODE);
    buffer.add(Uint8List(4)..buffer.asByteData().setInt32(0, rpcId));
    buffer.addByte(nodes.length);
    for (final node in nodes) {
      buffer.add(Uint8List(2)..buffer.asByteData().setUint16(0, node.length));
      buffer.add(node);
    }
    return buffer.toBytes();
  }

  static Uint8List createStore(int rpcId, Uint8List peerInfo) {
    final buffer = BytesBuilder();
    buffer.addByte(STORE);
    buffer.add(Uint8List(4)..buffer.asByteData().setInt32(0, rpcId));
    buffer.add(peerInfo);
    return buffer.toBytes();
  }
}
