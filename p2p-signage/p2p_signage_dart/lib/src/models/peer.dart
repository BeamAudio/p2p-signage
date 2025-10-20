class Peer {
  final String username;
  final String ip;
  final int port;
  final String publicKey;
  final DateTime lastSeen;
  bool isAuthenticated;

  Peer({
    required this.username,
    required this.ip,
    required this.port,
    required this.publicKey,
    required this.lastSeen,
    this.isAuthenticated = false,
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'ip': ip,
        'port': port,
        'publicKey': publicKey,
        'lastSeen': lastSeen.toIso8601String(),
        'isAuthenticated': isAuthenticated,
      };

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
        username: json['username'],
        ip: json['ip'],
        port: json['port'],
        publicKey: json['publicKey'],
        lastSeen: DateTime.parse(json['lastSeen']),
        isAuthenticated: json['isAuthenticated'] ?? false,
      );
}
