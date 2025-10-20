import 'dart:async';
import 'dart:io';

import 'core/donor_peer_simple_test.dart' as donor_peer_simple_test;
import 'core/minimal_test.dart' as minimal_test;
import 'core/p2p_node_feature_test.dart' as p2p_node_feature_test;
import 'core/p2p_node_integration_test.dart' as p2p_node_integration_test;

void main() {
  final logFile = File('test_log.txt');
  final sink = logFile.openWrite();

  runZonedGuarded(() {
    donor_peer_simple_test.main();
    minimal_test.main();
    p2p_node_feature_test.main();
    p2p_node_integration_test.main();
  }, (error, stack) {
    sink.writeln('Error: $error');
    sink.writeln(stack.toString());
  }, zoneSpecification: ZoneSpecification(
    print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
      sink.writeln(line);
    },
  ));

  // sink.close(); // Removed to prevent premature closing of the log file
}