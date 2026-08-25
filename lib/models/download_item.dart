enum DownloadKind { classicAudio, mp3Audio, video }

enum DownloadStatus {
  queued,
  downloading,
  processing,
  paused,
  retrying,
  completed,
  failed,
  cancelled,
}

class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.videoId,
    required this.title,
    required this.artist,
    required this.kind,
    required this.qualityLabel,
    required this.extension,
    required this.status,
    required this.createdAt,
    this.artworkUri,
    this.filePath,
    this.totalBytes,
    this.downloadedBytes = 0,
    this.progressPercent,
    this.backgroundTaskId,
    this.errorMessage,
  });

  final String id;
  final String videoId;
  final String title;
  final String artist;
  final Uri? artworkUri;
  final DownloadKind kind;
  final String qualityLabel;
  final String extension;
  final DownloadStatus status;
  final DateTime createdAt;
  final String? filePath;
  final int? totalBytes;
  final int downloadedBytes;

  /// Percentage reported by Flutter Downloader when the byte total is unknown.
  /// It is intentionally separate from [downloadedBytes] so UI never treats a
  /// percentage as a byte count.
  final int? progressPercent;
  final String? backgroundTaskId;
  final String? errorMessage;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (downloadedBytes / total).clamp(0.0, 1.0).toDouble();
  }

  bool get isCompleted =>
      status == DownloadStatus.completed && filePath != null;

  bool get isActive =>
      status == DownloadStatus.queued ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.processing ||
      status == DownloadStatus.retrying;

  String get typeLabel => switch (kind) {
    DownloadKind.classicAudio => 'Classic audio',
    DownloadKind.mp3Audio => 'MP3 audio',
    DownloadKind.video => 'Video',
  };

  DownloadItem copyWith({
    Uri? artworkUri,
    String? filePath,
    int? totalBytes,
    int? downloadedBytes,
    int? progressPercent,
    String? backgroundTaskId,
    DownloadStatus? status,
    String? errorMessage,
    bool clearFilePath = false,
    bool clearError = false,
    bool clearProgressPercent = false,
    bool clearBackgroundTaskId = false,
  }) {
    return DownloadItem(
      id: id,
      videoId: videoId,
      title: title,
      artist: artist,
      artworkUri: artworkUri ?? this.artworkUri,
      kind: kind,
      qualityLabel: qualityLabel,
      extension: extension,
      status: status ?? this.status,
      createdAt: createdAt,
      filePath: clearFilePath ? null : filePath ?? this.filePath,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      progressPercent:
          clearProgressPercent ? null : progressPercent ?? this.progressPercent,
      backgroundTaskId:
          clearBackgroundTaskId
              ? null
              : backgroundTaskId ?? this.backgroundTaskId,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'artworkUri': artworkUri?.toString(),
    'kind': kind.name,
    'qualityLabel': qualityLabel,
    'extension': extension,
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'filePath': filePath,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'progressPercent': progressPercent,
    'backgroundTaskId': backgroundTaskId,
    'errorMessage': errorMessage,
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind']?.toString();
    final statusName = json['status']?.toString();
    final kind = DownloadKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => DownloadKind.classicAudio,
    );
    final status = DownloadStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => DownloadStatus.failed,
    );
    return DownloadItem(
      id: json['id']?.toString() ?? '',
      videoId: json['videoId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled download',
      artist: json['artist']?.toString() ?? 'Unknown artist',
      artworkUri: Uri.tryParse(json['artworkUri']?.toString() ?? ''),
      kind: kind,
      qualityLabel: json['qualityLabel']?.toString() ?? 'Unknown quality',
      extension: json['extension']?.toString() ?? 'bin',
      status: status,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      filePath: json['filePath']?.toString(),
      totalBytes: (json['totalBytes'] as num?)?.toInt(),
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      progressPercent: (json['progressPercent'] as num?)?.toInt(),
      backgroundTaskId: json['backgroundTaskId']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}
