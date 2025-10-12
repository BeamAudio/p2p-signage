import 'dart:convert';

/// Enum for device roles
enum DeviceRole { master, slave }

/// Enum for device status
enum DeviceStatus { online, offline, syncing, error }

/// Enum for file types
enum FileType { video, image, text }

/// Enum for transfer status
enum TransferStatus { pending, inProgress, completed, error }

/// Represents a device in the network
class Device {
  final String deviceId;
  final String deviceName;
  final DeviceRole role;
  final String publicIp;
  final int publicPort;
  final DeviceStatus status;
  final String? assignedPlaylistId;

  Device({
    String? deviceId,
    required this.deviceName,
    required this.role,
    required this.publicIp,
    required this.publicPort,
    required this.status,
    this.assignedPlaylistId,
  }) : deviceId = deviceId ?? 'device_${DateTime.now().millisecondsSinceEpoch}';

  Device copyWith({
    String? deviceId,
    String? deviceName,
    DeviceRole? role,
    String? publicIp,
    int? publicPort,
    DeviceStatus? status,
    String? assignedPlaylistId,
  }) {
    return Device(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      role: role ?? this.role,
      publicIp: publicIp ?? this.publicIp,
      publicPort: publicPort ?? this.publicPort,
      status: status ?? this.status,
      assignedPlaylistId: assignedPlaylistId ?? this.assignedPlaylistId,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'role': role.index,
        'publicIp': publicIp,
        'publicPort': publicPort,
        'status': status.index,
        'assignedPlaylistId': assignedPlaylistId,
      };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        deviceId: json['deviceId'],
        deviceName: json['deviceName'],
        role: DeviceRole.values[json['role']],
        publicIp: json['publicIp'],
        publicPort: json['publicPort'],
        status: DeviceStatus.values[json['status']],
        assignedPlaylistId: json['assignedPlaylistId'],
      );
}

/// Represents a media file
class MediaFile {
  final String fileId;
  final String fileName;
  final FileType fileType;
  final int fileSize;
  final int chunkCount;
  final String checksum;
  final String filePath;

  MediaFile({
    String? fileId,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.chunkCount,
    required this.checksum,
    required this.filePath,
  }) : fileId = fileId ?? 'file_${DateTime.now().millisecondsSinceEpoch}';

  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'fileName': fileName,
        'fileType': fileType.index,
        'fileSize': fileSize,
        'chunkCount': chunkCount,
        'checksum': checksum,
        'filePath': filePath,
      };

  factory MediaFile.fromJson(Map<String, dynamic> json) => MediaFile(
        fileId: json['fileId'],
        fileName: json['fileName'],
        fileType: FileType.values[json['fileType']],
        fileSize: json['fileSize'],
        chunkCount: json['chunkCount'],
        checksum: json['checksum'],
        filePath: json['filePath'],
      );
}

/// Represents a playlist item
class PlaylistItem {
  final String mediaFileId;
  final int duration; // in seconds
  final int order;

  PlaylistItem({
    required this.mediaFileId,
    required this.duration,
    required this.order,
  });

  Map<String, dynamic> toJson() => {
        'mediaFileId': mediaFileId,
        'duration': duration,
        'order': order,
      };

  factory PlaylistItem.fromJson(Map<String, dynamic> json) => PlaylistItem(
        mediaFileId: json['mediaFileId'],
        duration: json['duration'],
        order: json['order'],
      );
}

/// Represents a playlist schedule
class PlaylistSchedule {
  final bool isLooped;

  PlaylistSchedule({
    required this.isLooped,
  });

  Map<String, dynamic> toJson() => {
        'isLooped': isLooped,
      };

  factory PlaylistSchedule.fromJson(Map<String, dynamic> json) => PlaylistSchedule(
        isLooped: json['isLooped'],
      );
}

/// Represents a transfer session
class TransferSession {
  final String fileId;
  final String targetDeviceId;
  final int totalChunks;
  final TransferStatus status;

  TransferSession({
    required this.fileId,
    required this.targetDeviceId,
    required this.totalChunks,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'targetDeviceId': targetDeviceId,
        'totalChunks': totalChunks,
        'status': status.index,
      };

  factory TransferSession.fromJson(Map<String, dynamic> json) => TransferSession(
        fileId: json['fileId'],
        targetDeviceId: json['targetDeviceId'],
        totalChunks: json['totalChunks'],
        status: TransferStatus.values[json['status']],
      );
}

/// Represents a playlist with its metadata and associated media files
class Playlist {
  String id;
  String name;
  List<PlaylistItem> items;
  final DateTime createdAt;
  DateTime updatedAt;
  PlaylistSchedule schedule;
  List<String> assignedDevices; // IDs of devices this playlist is assigned to
  String? location; // Geographic location for this playlist

  Playlist({
    String? id,
    required this.name,
    required this.items,
    DateTime? createdAt,
    DateTime? updatedAt,
    required this.schedule,
    List<String>? assignedDevices,
    this.location,
  })  : id = id ?? 'playlist_${DateTime.now().millisecondsSinceEpoch}',
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        assignedDevices = assignedDevices ?? [];

  Playlist copyWith({
    String? id,
    String? name,
    List<PlaylistItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
    PlaylistSchedule? schedule,
    List<String>? assignedDevices,
    String? location,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      schedule: schedule ?? this.schedule,
      assignedDevices: assignedDevices ?? this.assignedDevices,
      location: location ?? this.location,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.map((item) => item.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'schedule': schedule.toJson(),
        'assignedDevices': assignedDevices,
        'location': location,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'],
        name: json['name'],
        items: (json['items'] as List).map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>)).toList(),
        createdAt: DateTime.parse(json['createdAt']),
        updatedAt: DateTime.parse(json['updatedAt']),
        schedule: PlaylistSchedule.fromJson(json['schedule']),
        assignedDevices: List<String>.from(json['assignedDevices'] ?? []),
        location: json['location'],
      );
}

/// Represents media file information
class MediaFileInfo {
  final String id;
  final String checksum;
  final int size;
  final String fileName;

  MediaFileInfo({
    required this.id,
    required this.checksum,
    required this.size,
    required this.fileName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'checksum': checksum,
        'size': size,
        'fileName': fileName,
      };

  factory MediaFileInfo.fromJson(Map<String, dynamic> json) => MediaFileInfo(
        id: json['id'],
        checksum: json['checksum'],
        size: json['size'],
        fileName: json['fileName'],
      );
}

/// Represents geolocation information
class LocationInfo {
  final double latitude;
  final double longitude;
  final double? accuracy; // in meters
  final DateTime timestamp;

  LocationInfo({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'timestamp': timestamp.toIso8601String(),
      };

  factory LocationInfo.fromJson(Map<String, dynamic> json) => LocationInfo(
        latitude: json['latitude'],
        longitude: json['longitude'],
        accuracy: json['accuracy'],
        timestamp: DateTime.parse(json['timestamp']),
      );
}

/// Represents performance metrics
class PerformanceMetrics {
  final double cpuUsage;
  final int memoryUsage; // in bytes
  final int totalMemory; // in bytes
  final double diskUsage; // percentage
  final double networkLatency; // in ms
  final int networkDownload; // in bytes/sec
  final int networkUpload; // in bytes/sec
  final String nodeId;
  final DateTime timestamp;

  PerformanceMetrics({
    required this.cpuUsage,
    required this.memoryUsage,
    required this.totalMemory,
    required this.diskUsage,
    required this.networkLatency,
    required this.networkDownload,
    required this.networkUpload,
    required this.nodeId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'cpuUsage': cpuUsage,
        'memoryUsage': memoryUsage,
        'totalMemory': totalMemory,
        'diskUsage': diskUsage,
        'networkLatency': networkLatency,
        'networkDownload': networkDownload,
        'networkUpload': networkUpload,
        'nodeId': nodeId,
        'timestamp': timestamp.toIso8601String(),
      };

  factory PerformanceMetrics.fromJson(Map<String, dynamic> json) =>
      PerformanceMetrics(
        cpuUsage: json['cpuUsage'],
        memoryUsage: json['memoryUsage'],
        totalMemory: json['totalMemory'],
        diskUsage: json['diskUsage'],
        networkLatency: json['networkLatency'],
        networkDownload: json['networkDownload'],
        networkUpload: json['networkUpload'],
        nodeId: json['nodeId'],
        timestamp: DateTime.parse(json['timestamp']),
      );
}