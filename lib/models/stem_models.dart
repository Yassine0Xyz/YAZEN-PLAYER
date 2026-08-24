import 'dart:convert';

class StemSeparationResult {
  const StemSeparationResult({
    required this.jobId,
    required this.model,
    required this.stems,
  });

  final String jobId;
  final String model;
  final Map<StemType, Uri> stems;

  factory StemSeparationResult.fromJson(Map<String, dynamic> json) {
    final rawStems =
        json['stems'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final stems = <StemType, Uri>{};
    for (final entry in rawStems.entries) {
      final type = StemType.fromName(entry.key);
      final payload = entry.value as Map<String, dynamic>?;
      final url = Uri.tryParse(payload?['url']?.toString() ?? '');
      if (type != null && url != null) stems[type] = url;
    }
    return StemSeparationResult(
      jobId: json['job_id']?.toString() ?? '',
      model: json['model']?.toString() ?? 'htdemucs',
      stems: stems,
    );
  }

  String toJsonString() => jsonEncode(<String, dynamic>{
    'job_id': jobId,
    'model': model,
    'stems': stems.map((key, value) => MapEntry(key.name, value.toString())),
  });
}

enum StemType {
  vocals('Vocals', 'Mic2'),
  bass('Bass', 'Bass'),
  drums('Drums', 'Drums'),
  other('Other', 'Music');

  const StemType(this.label, this.shortLabel);

  final String label;
  final String shortLabel;

  static StemType? fromName(String value) {
    for (final stem in values) {
      if (stem.name == value.toLowerCase()) return stem;
    }
    return null;
  }
}
