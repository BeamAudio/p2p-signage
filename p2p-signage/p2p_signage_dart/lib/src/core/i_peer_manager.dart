import 'package:p2p_signage/src/models/peer.dart';

abstract class IPeerManager {
  void addPeer(Peer peer);
  void removePeer(Peer peer);
  List<Peer> getPeers();
  void onPeerAdded(void Function(Peer peer) callback);
  void setAuthenticated(String username, bool isAuthenticated);
}
