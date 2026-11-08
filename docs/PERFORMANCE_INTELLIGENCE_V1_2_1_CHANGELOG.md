# YAZEN Performance Intelligence V1.2.1 — Source Changes

## Implemented

### Journal loss attribution and integrity
- Track the journal queue high-water mark.
- Separate queue-overflow losses from journal I/O failures.
- Track first/last dropped sequence and per-event-type loss counts for queue overflow and serialization failures.
- Count journal write failures and classify affected events as `journal_io_uncertain` rather than implying that the JSONL file is complete.
- Add a `journalIntegrity` summary object with capacity, high-water mark, observed/queued/persisted/dropped/pending counts, loss attribution, and an accounting consistency check.
- Report `complete_at_export_boundary` only when there are no known drops, no journal error, and no pending records. Otherwise report `incomplete_or_uncertain`.

## Important limitations
- This change improves the evidence about event loss; it does not guarantee lossless recording under arbitrary I/O stalls or process termination.
- The `IOSink` API does not identify exactly which lines from a failed flush reached durable storage. Such events are therefore marked uncertain.
- No Flutter/Dart SDK is installed in the editing environment, so `dart format`, `flutter analyze`, `flutter test`, and APK builds have not been run.
- No Full Player rendering change is included in this patch: the available session data identifies a Raster-heavy Full Player route but does not isolate Ambient Flow, Visualizer, artwork animation, or another painter as the individual cause. Changing those visuals without component-level evidence risks regressions.
- Disk cache is not changed: the captured session does not include a post-restart warm-cache test.
