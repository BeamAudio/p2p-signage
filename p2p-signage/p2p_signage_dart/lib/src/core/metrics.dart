class Metrics {
  int gossipMessagesSent = 0;
  int gossipMessagesReceived = 0;
  int peersDiscovered = 0;
  int authenticationAttempts = 0;
  int messagesSent = 0;
  int messagesReceived = 0;

  Map<String, dynamic> toJson() => {
        'gossipMessagesSent': gossipMessagesSent,
        'gossipMessagesReceived': gossipMessagesReceived,
        'peersDiscovered': peersDiscovered,
        'authenticationAttempts': authenticationAttempts,
        'messagesSent': messagesSent,
        'messagesReceived': messagesReceived,
      };
}
