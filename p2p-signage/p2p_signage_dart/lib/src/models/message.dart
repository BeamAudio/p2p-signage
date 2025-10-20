class Message {
  final String sender;
  final String recipient;
  final String content;
  final DateTime timestamp;

  Message({
    required this.sender,
    required this.recipient,
    required this.content,
    required this.timestamp,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        sender: json['sender'],
        recipient: json['recipient'],
        content: json['content'],
        timestamp: DateTime.parse(json['timestamp']),
      );

  Map<String, dynamic> toJson() => {
        'sender': sender,
        'recipient': recipient,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };
}
