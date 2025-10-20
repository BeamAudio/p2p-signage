import 'package:p2p_signage/src/core/i_peer_manager.dart';
import 'package:p2p_signage/src/models/peer.dart';

class PeerManager implements IPeerManager {
  final List<Peer> _peers = [];
  void Function(Peer peer)? _onPeerAdded;

  @override
  void addPeer(Peer peer) {
    final existingPeerIndex = _peers.indexWhere((p) => p.username == peer.username);
    if (existingPeerIndex != -1) {
      // Update existing peer information
      final existingPeer = _peers[existingPeerIndex];
      _peers[existingPeerIndex] = Peer(
        username: peer.username,
        ip: peer.ip,
        port: peer.port,
        publicKey: peer.publicKey,
        lastSeen: peer.lastSeen.isAfter(existingPeer.lastSeen) ? peer.lastSeen : existingPeer.lastSeen,
        isAuthenticated: peer.isAuthenticated || existingPeer.isAuthenticated,
      );
    } else {
      // Add new peer
      _peers.add(peer);
      _onPeerAdded?.call(peer);
    }
  }

  @override
  void removePeer(Peer peer) {
    _peers.removeWhere((p) => p.username == peer.username);
  }

  @override
  List<Peer> getPeers() {
    return List.unmodifiable(_peers);
  }

  @override
  void onPeerAdded(void Function(Peer peer) callback) {
    _onPeerAdded = callback;
  }

  @override
  void setAuthenticated(String username, bool isAuthenticated) {
    final peer = _peers.firstWhere((p) => p.username == username, orElse: () => throw Exception('Peer not found'));
    peer.isAuthenticated = isAuthenticated;
  }

  void updatePeerLastSeen(String username) {
    final existingPeerIndex = _peers.indexWhere((p) => p.username == username);
    if (existingPeerIndex != -1) {
      final existingPeer = _peers[existingPeerIndex];
      _peers[existingPeerIndex] = Peer(
        username: existingPeer.username,
        ip: existingPeer.ip,
        port: existingPeer.port,
        publicKey: existingPeer.publicKey,
        lastSeen: DateTime.now(),
        isAuthenticated: existingPeer.isAuthenticated,
      );
    }
  }

  void cleanupInactivePeers(Duration timeout) {
    final now = DateTime.now();
    _peers.removeWhere((peer) {
      if (!peer.isAuthenticated) {
        return false;
      }
      final isInactive = now.difference(peer.lastSeen) > timeout;
      return isInactive;
    });
  }
}