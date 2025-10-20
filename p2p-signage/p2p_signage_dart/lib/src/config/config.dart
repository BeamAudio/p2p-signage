class P2PConfig {
  final String username;
  final String ipAddress;
  final int udpPort;
  final int tcpPort;
  final int gossipInterval;
  final int gossipPeerCount;
  final int messageTimeoutSeconds;
  final int peerCleanupInterval;
  final String stunServer;
  final bool forceLocalhost;

  P2PConfig({
    required this.username,
    this.ipAddress = '127.0.0.1', // Default to localhost
    this.udpPort = 0,
    this.tcpPort = 0,
    this.gossipInterval = 30,
    this.gossipPeerCount = 3,
    this.messageTimeoutSeconds = 30,
    this.peerCleanupInterval = 60, // Default to 60 seconds
    this.stunServer = 'stun.l.google.com:19302',
    this.forceLocalhost = false,
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'ipAddress': ipAddress,
        'udpPort': udpPort,
        'tcpPort': tcpPort,
        'gossipInterval': gossipInterval,
        'gossipPeerCount': gossipPeerCount,
        'messageTimeoutSeconds': messageTimeoutSeconds,
        'peerCleanupInterval': peerCleanupInterval,
        'stunServer': stunServer,
        'forceLocalhost': forceLocalhost,
      };

  factory P2PConfig.fromJson(Map<String, dynamic> json) => P2PConfig(
        username: json['username'],
        ipAddress: json['ipAddress'],
        udpPort: json['udpPort'],
        tcpPort: json['tcpPort'],
        gossipInterval: json['gossipInterval'] ?? 30,
        gossipPeerCount: json['gossipPeerCount'] ?? 3,
        messageTimeoutSeconds: json['messageTimeoutSeconds'] ?? 30,
        peerCleanupInterval: json['peerCleanupInterval'] ?? 60,
        stunServer: json['stunServer'] ?? 'stun.l.google.com:19302',
        forceLocalhost: json['forceLocalhost'] ?? false,
      );
}