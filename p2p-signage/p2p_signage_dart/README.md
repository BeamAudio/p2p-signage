# P2P Signage Dart Application

This directory contains the core Dart application for the P2P (Peer-to-Peer) signage system. It implements the node logic, including peer discovery, authentication, secure communication, and content distribution.

## Project Structure

- `lib/src/config/config.dart`: Configuration settings for P2P nodes.
- `lib/src/core/p2p_node.dart`: The main P2P node logic, handling communication, peer management, and message processing.
- `lib/src/core/peer_manager.dart`: Manages the list of known peers.
- `lib/src/networking/udp_transport.dart`: Handles UDP socket communication.
- `lib/src/security/`: Contains cryptographic and authentication services.
- `lib/isolates/node_isolate.dart`: A wrapper to run `P2PNode` in a separate Dart isolate.
- `test/`: Unit and integration tests for the P2P node.

## Getting Started

### Prerequisites

- **Dart SDK:** [Install Dart](https://dart.dev/get-dart)

### Installation

Navigate to this directory and fetch the Dart dependencies:

```bash
dart pub get
```

### Running Tests

To run all tests:

```bash
dart test
```

To run a specific test (e.g., the multi-isolate test):

```bash
dart test test/core/multi_isolate_test.dart
```

**Note on Logging:** The `udp_transport.dart` file has been instrumented to output detailed `[UDP_LOG]` messages to `stdout`. When running tests, you can redirect this output to a file for analysis by the Python script:

```bash
dart test test/core/multi_isolate_test.dart > multi_isolate_log.txt
```

### Running a Single Node (Example)

To run a single P2P node, you would typically create an instance of `P2PNode` with a `P2PConfig` and call its `start()` method. This usually involves more application-specific logic. For development and testing, running the provided tests is often sufficient to observe node behavior.

```dart
// Example (not a runnable script, for illustration only)
import 'package:p2p_signage/src/config/config.dart';
import 'package:p2p_signage/src/core/p2p_node.dart';

void main() async {
  final config = P2PConfig(username: 'myNode', forceLocalhost: true);
  final node = P2PNode(config, log: print);
  await node.start();
  print('Node myNode started on port ${node.localPort}');
  // Keep the node running, e.g., with a long Future.delayed or a user input loop
}
```

## Configuration (`lib/src/config/config.dart`)

The `P2PConfig` class allows you to configure various aspects of a P2P node, including:

- `username`: Unique identifier for the node.
- `udpPort`: The UDP port to bind to (0 for auto-assignment).
- `gossipInterval`: How often the node gossips its peer list.
- `messageTimeoutSeconds`: Timeout for ACK-required messages.
- `stunServer`: STUN server for public IP discovery.
- `forceLocalhost`: Forces communication over 127.0.0.1, useful for local testing.

## Extending the Protocol

To add new message types or protocol features, you would typically:

1.  Define new message structures in `lib/src/models/message.dart`.
2.  Implement handling logic in `P2PNode._handleMessage` and its associated helper methods.
3.  Extend `NodeCommand` in `lib/isolates/node_isolate.dart` if the new feature needs to be exposed via the isolate API.
