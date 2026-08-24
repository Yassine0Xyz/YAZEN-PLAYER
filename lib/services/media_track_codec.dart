import '../models/media_track.dart';

Map<String, dynamic> mediaTrackToJson(MediaTrack track) => <String, dynamic>{
  'id': track.id,
  'title': track.title,
  'artist': track.artist,
  'album': track.album,
  'source': track.source.name,
  'uri': track.uri?.toString(),
  'artworkUri': track.artworkUri?.toString(),
  'durationMs': track.duration?.inMilliseconds,
  'folder': track.folder,
  'youtubeId': track.youtubeId,
  'viewCount': track.viewCount,
  'channelName': track.channelName,
};

MediaTrack mediaTrackFromJson(Map<String, dynamic> json) {
  final sourceName = json['source']?.toString() ?? TrackSource.local.name;
  final source = TrackSource.values.firstWhere(
    (item) => item.name == sourceName,
    orElse: () => TrackSource.local,
  );
  final durationMs = json['durationMs'];
  return MediaTrack(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Unknown title',
    artist: json['artist']?.toString() ?? 'Unknown artist',
    album: json['album']?.toString() ?? 'Unknown album',
    source: source,
    uri: _tryParseUri(json['uri']),
    artworkUri: _tryParseUri(json['artworkUri']),
    duration:
        durationMs is num ? Duration(milliseconds: durationMs.toInt()) : null,
    folder: json['folder']?.toString(),
    youtubeId: json['youtubeId']?.toString(),
    viewCount: (json['viewCount'] as num?)?.toInt(),
    channelName: json['channelName']?.toString(),
  );
}

Uri? _tryParseUri(dynamic value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return Uri.tryParse(text);
}
