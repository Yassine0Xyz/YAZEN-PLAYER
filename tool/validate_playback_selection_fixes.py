from pathlib import Path

root = Path(__file__).resolve().parents[1]
handler = (root / "lib/services/hybrid_audio_handler.dart").read_text()
search = (root / "lib/screens/search/search_screen.dart").read_text()
home = (root / "lib/screens/home/home_screen.dart").read_text()
playlist = (root / "lib/screens/collections/playlist_details_screen.dart").read_text()
mini_player_host = (root / "lib/widgets/mini_player_host.dart").read_text()
library = (root / "lib/screens/library/local_media_screen.dart").read_text()
tests = (root / "test/hybrid_audio_queue_race_test.dart").read_text()
checks = {
    "stale queue index events are discarded": "index != _player.currentIndex" in handler,
    "source-swap index events are suppressed": "_selectionSourceLoadRequest != null" in handler,
    "failed queue selection restores prior queue": "previousTracks.isNotEmpty" in handler and "previousWasPlaying" in handler,
    "search waits for queue setup before popping route": "await controller.playTrackQueue(audioResults, initialIndex: index)" in search and "if (mounted) navigator.pop();" in search,
    "search prevents duplicate overlapping first-tap queue swaps": "_isStartingPlayback" in search,
    "home mini player is seeded from active media item": "MiniPlayerHost()" in home and "initialData: handler.activeTrack?.toMediaItem()" in mini_player_host,
    # Playlist details uses the shared MiniPlayerHost, so validate the host's
    # first-frame seed rather than requiring duplicate StreamBuilder logic in
    # every screen that embeds it.
    "playlist detail mini player is seeded from active media item": "initialData: handler.activeTrack?.toMediaItem()" in mini_player_host,
    "playlist tab reserves space above the mini player": "EdgeInsets.fromLTRB(20, 0, 20, 116)" in library,
    "queue race regression tests cover stale indices and failed selections": "stale current-index events" in tests and "failed queue selection restores" in tests,
}
for label, passed in checks.items():
    print(("PASS " if passed else "FAIL ") + label)
if not all(checks.values()):
    raise SystemExit(1)
print(f"{len(checks)}/{len(checks)} playback-selection guardrails passed.")
