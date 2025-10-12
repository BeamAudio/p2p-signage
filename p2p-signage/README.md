# Peer-to-Peer Digital Signage System

A complete serverless, peer-to-peer digital signage solution built with Flutter. The system allows a central controller device ("master") to manage multiple remote display devices ("slaves") without any external servers, centralized infrastructure, or cloud dependencies.

## Architecture

The system is composed of three main components:

1. **Master App**: The control center that manages content and devices
2. **Slave App**: The display devices that play assigned content
3. **Core Library**: Shared functionality for both apps

### Key Features

- Peer-to-peer connections using UDP hole punching
- ICE/STUN for public IP discovery
- Direct file transfers between devices
- Map-based device management
- Playlist scheduling and distribution
- Resumable file transfers with integrity verification
- Local content caching for offline playback
- Playback engine for scheduled content

## Setup

### Prerequisites

- Flutter SDK 3.6.1 or later
- Dart SDK 3.6.1 or later
- Android SDK (for mobile builds)
- iOS SDK (for iOS builds, macOS only)

### Building the Applications

1. **Master App**: Controls and manages content
   ```bash
   cd master_app
   flutter pub get
   flutter run
   ```

2. **Slave App**: Displays assigned content
   ```bash
   cd slave_app
   flutter pub get
   flutter run
   ```

## How It Works

### 1. Device Discovery and Identity

- Each device generates a unique persistent device ID using UUID
- Master and slaves use ICE/STUN to discover public IP addresses
- Initial pairing can be done via QR code, LAN broadcast, or manual entry

### 2. Peer-to-Peer Connections

- Uses UDP hole punching to establish direct connections through NAT
- NAT traversal implemented using synchronized packet exchange
- Connection status tracking and health checks

### 3. File Transfers

- Chunked UDP-based file transfers with resume capability
- Content verification using SHA256 checksums
- Real-time progress tracking for each transfer
- Retry mechanism for failed chunks

### 4. Content Management

- Media library with support for video, image, and audio files
- Playlist builder with scheduling capabilities
- Assignment of content to specific devices
- Local caching for offline playback

### 5. Playback Engine

- Automatic playback of assigned content
- Schedule-aware playback (start/end times, looping)
- Content caching for offline operation
- Automatic resume after device restart

## Core Components

### Models
- `Device`: Represents a master or slave device
- `MediaFile`: Represents media files with metadata
- `Playlist`: Defines content schedule and order
- `TransferSession`: Manages file transfer state

### Managers
- `IdentityManager`: Handles device identity and persistence
- `PeerListManager`: Maintains list of known peers
- `FileTransferManager`: Manages file transfers between devices
- `PlaylistManager`: Handles playlist creation and distribution
- `PlaybackEngine`: Executes content playback on slaves

### Network Components
- `ICEDiscoveryManager`: Uses STUN to discover public addresses
- `UDPPuncher`: Implements UDP hole punching for NAT traversal

## Security Features

- Device identity with unique persistent IDs
- Content verification using SHA256 checksums
- Direct connections without intermediary servers
- Rate limiting to prevent flooding attacks

## Limitations

- Requires network devices to support UDP hole punching
- Performance depends on network conditions
- Complex NAT types may prevent direct connections

## Testing

The system includes integration tests that verify:
- Device identity and persistence
- File transfer mechanisms
- Playlist distribution
- Network connectivity

## Deployment

### Android
```bash
cd master_app
flutter build apk --release

cd ../slave_app
flutter build apk --release
```

### iOS
```bash
cd master_app
flutter build ios --release

cd ../slave_app
flutter build ios --release
```

## Troubleshooting

- If devices can't connect, ensure UDP traffic is not blocked
- Check that STUN servers are accessible
- Verify that both devices are on networks that support UDP hole punching

## License

This project is licensed under the MIT License.