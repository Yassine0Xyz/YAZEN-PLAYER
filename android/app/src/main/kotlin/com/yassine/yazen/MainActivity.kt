package com.yassine.yazen

import android.Manifest
import android.app.Activity
import android.app.PictureInPictureParams
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.util.Rational
import android.util.Size
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.LinkedHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.roundToInt

class MainActivity : AudioServiceActivity() {
    private val channelName = "yazen/local_media"
    private val pcmTag = "YAZENPcm"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val deleteAudioRequestCode = 4207
    private var pendingVideoPermissionResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeleteIds: List<Int> = emptyList()
    private val pcmExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val artworkExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var pcmGeneration = 0
    private var pcmState = "idle"
    private var pcmResult: PcmSpectrumAnalyzer.Result? = null
    private var pcmProgressFrames: MutableList<FloatArray> = mutableListOf()
    private val pcmCache = object : LinkedHashMap<String, PcmSpectrumAnalyzer.Result>(
        4,
        0.75f,
        true,
    ) {
        override fun removeEldestEntry(
            eldest: MutableMap.MutableEntry<String, PcmSpectrumAnalyzer.Result>?,
        ): Boolean = size > 3
    }
    private var pcmFailure: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestVideoPermission" -> requestVideoPermission(result)
                    "videoPermissionStatus" -> result.success(hasVideoPermission())
                    "openAppSettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.parse("package:$packageName")
                                },
                            )
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("settings_unavailable", error.message, null)
                        }

                    }
                    "queryVideos" -> queryVideos(result)
                    "videoThumbnail" -> videoThumbnail(
                        call.argument<String>("uri"),
                        call.argument<Int>("width") ?: 640,
                        result,
                    )
                    "readArtworkPixels" -> readArtworkPixels(
                        call.argument<String>("uri"),
                        call.argument<Int>("size") ?: 64,
                        result,
                    )
                    "readOriginalArtwork" -> readOriginalArtwork(
                        call.argument<String>("uri"),
                        result,
                    )
                    "shareAudioTracks" -> shareAudioTracks(
                        call.argument<List<Int>>("ids"),
                        result,
                    )
                    "deleteAudioTracks" -> deleteAudioTracks(
                        call.argument<List<Int>>("ids"),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yazen/audio_visualizer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startPcm" -> startPcmAnalyzer(call.argument<String>("uri"), result)
                    "readPcm" -> readPcmAnalyzer(
                        call.argument<Number>("positionMs")?.toLong() ?: 0L,
                        result,
                    )
                    "stopPcm" -> {
                        stopPcmAnalyzer()
                        result.success(null)
                    }
                    "stop" -> {
                        stopPcmAnalyzer()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yazen/player_controls")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setVolume" -> {
                        val value = (call.argument<Number>("value")?.toFloat() ?: 0.75f)
                            .coerceIn(0f, 1f)
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        audioManager.setStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            (max * value).roundToInt(),
                            0,
                        )
                        result.success(null)
                    }
                    "setBrightness" -> {
                        val value = (call.argument<Number>("value")?.toFloat() ?: 0.65f)
                            .coerceIn(0.05f, 1f)
                        val attributes = window.attributes
                        attributes.screenBrightness = value
                        window.attributes = attributes
                        result.success(null)
                    }
                    "setKeepScreenOn" -> {
                        val keepScreenOn = call.argument<Boolean>("enabled") == true
                        if (keepScreenOn) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "enterPictureInPicture" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            enterPictureInPictureMode(
                                PictureInPictureParams.Builder()
                                    .setAspectRatio(Rational(16, 9))
                                    .build(),
                            )
                            result.success(null)
                        } else {
                            result.error("UNAVAILABLE", "Picture-in-picture requires Android 8.0 or newer.", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == deleteAudioRequestCode) {
            val result = pendingDeleteResult
            val ids = pendingDeleteIds
            pendingDeleteResult = null
            pendingDeleteIds = emptyList()
            if (result != null) {
                if (resultCode == Activity.RESULT_OK) {
                    result.success(ids)
                } else {
                    result.error("delete_denied", "Audio deletion was cancelled.", null)
                }
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun shareAudioTracks(ids: List<Int>?, result: MethodChannel.Result) {
        val trackIds = ids?.distinct().orEmpty()
        if (trackIds.isEmpty()) {
            result.error("invalid_tracks", "No audio tracks were selected.", null)
            return
        }
        try {
            val streams = ArrayList(trackIds.map { id ->
                ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    id.toLong(),
                )
            })
            val intent = if (streams.size == 1) {
                Intent(Intent.ACTION_SEND).apply {
                    type = "audio/*"
                    putExtra(Intent.EXTRA_STREAM, streams.first())
                }
            } else {
                Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    type = "audio/*"
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, streams)
                }
            }.apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = android.content.ClipData.newUri(
                    contentResolver,
                    "YAZEN audio",
                    streams.first(),
                ).also { clip ->
                    streams.drop(1).forEach {
                        clip.addItem(android.content.ClipData.Item(it))
                    }
                }
            }
            startActivity(Intent.createChooser(intent, "Share audio"))
            result.success(null)
        } catch (error: Exception) {
            result.error("share_failed", error.message ?: "Unable to share audio.", null)
        }
    }

    private fun deleteAudioTracks(ids: List<Int>?, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.error(
                "delete_unsupported",
                "Secure audio deletion requires Android 11 or newer.",
                null,
            )
            return
        }
        val trackIds = ids?.distinct().orEmpty()
        if (trackIds.isEmpty()) {
            result.error("invalid_tracks", "No audio tracks were selected.", null)
            return
        }
        if (pendingDeleteResult != null) {
            result.error("delete_in_progress", "A delete request is already active.", null)
            return
        }
        val uris = trackIds.map { id ->
            ContentUris.withAppendedId(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                id.toLong(),
            )
        }
        try {
            val request = MediaStore.createDeleteRequest(contentResolver, uris)
            pendingDeleteIds = trackIds
            pendingDeleteResult = result
            startIntentSenderForResult(
                request.intentSender,
                deleteAudioRequestCode,
                null,
                0,
                0,
                0,
            )
        } catch (error: Exception) {
            pendingDeleteResult = null
            pendingDeleteIds = emptyList()
            result.error(
                "delete_failed",
                error.message ?: "Unable to request audio deletion.",
                null,
            )
        }
    }

    private fun startPcmAnalyzer(uriString: String?, result: MethodChannel.Result) {
        stopPcmAnalyzer()
        if (uriString.isNullOrBlank()) {
            result.success(mapOf<String, Any>("started" to false, "state" to "unavailable"))
            return
        }
        val generation = ++pcmGeneration
        val cached = pcmCache[uriString]
        if (cached != null) {
            pcmResult = cached
            pcmProgressFrames = cached.frames.toMutableList()
            pcmState = "ready"
            pcmFailure = null
            Log.i(
                pcmTag,
                "pcm cache hit uri=$uriString frames=${cached.frames.size}",
            )
            result.success(
                mapOf<String, Any>(
                    "started" to true,
                    "mode" to "pcm_file_cache",
                    "state" to "ready",
                ),
            )
            return
        }
        pcmState = "preparing"
        pcmResult = null
        pcmProgressFrames = mutableListOf()
        pcmFailure = null
        Log.i(pcmTag, "pcm start requested uri=$uriString")
        result.success(
            mapOf<String, Any>(
                "started" to true,
                "mode" to "pcm_file",
                "state" to "preparing",
            ),
        )
        pcmExecutor.execute {
            val analysis = PcmSpectrumAnalyzer(contentResolver) {
                generation != pcmGeneration
            }.analyze(Uri.parse(uriString)) { frames ->
                mainHandler.post {
                    if (generation != pcmGeneration) return@post
                    pcmProgressFrames.addAll(frames)
                }
            }
            mainHandler.post {
                if (generation != pcmGeneration) return@post
                if (analysis == null) {
                    if (pcmProgressFrames.isEmpty()) {
                        pcmState = "unavailable"
                        pcmFailure = "decoder_failed"
                    } else {
                        pcmState = "ready"
                    }
                    Log.w(pcmTag, "pcm analysis unavailable uri=$uriString frames=${pcmProgressFrames.size}")
                } else {
                    pcmCache[uriString] = analysis
                    pcmResult = analysis
                    pcmProgressFrames = analysis.frames.toMutableList()
                    pcmState = "ready"
                    Log.i(
                        pcmTag,
                        "pcm ready uri=$uriString frames=${analysis.frames.size} " +
                            "frameMs=${analysis.frameDurationMs} sampleRate=${analysis.sampleRate} " +
                            "channels=${analysis.channels}",
                    )
                }
            }
        }
    }

    private fun readPcmAnalyzer(positionMs: Long, result: MethodChannel.Result) {
        val analysis = pcmResult
        val frameDurationMs = analysis?.frameDurationMs ?: 40L
        val frames = if (analysis != null) analysis.frames else pcmProgressFrames
        if (frames.isEmpty()) {
            if (pcmState == "preparing") {
                result.success(mapOf<String, Any>("state" to "preparing"))
            } else {
                result.success(
                    mapOf<String, Any>(
                        "state" to "unavailable",
                        "error" to (pcmFailure ?: "not_ready"),
                    ),
                )
            }
            return
        }
        val index = (positionMs / frameDurationMs).coerceAtLeast(0L).toInt()
        if (index >= frames.size) {
            val state = if (pcmState == "preparing") "preparing" else "unavailable"
            result.success(
                mapOf<String, Any>(
                    "state" to state,
                    "error" to (pcmFailure ?: if (state == "unavailable") "analysis_failed" else "not_ready"),
                ),
            )
            return
        }
        if (pcmState != "ready" && pcmState != "preparing") {
            result.success(
                mapOf<String, Any>(
                    "state" to "unavailable",
                    "error" to (pcmFailure ?: "not_ready"),
                ),
            )
            return
        }
        val frame = frames[index]
        result.success(
            mapOf<String, Any>(
                "state" to "live",
                "frameIndex" to index,
                "frameCount" to frames.size,
                "frameDurationMs" to frameDurationMs,
                "bands" to frame.toList(),
            ),
        )
    }

    private fun stopPcmAnalyzer() {
        pcmGeneration++
        pcmState = "idle"
        pcmResult = null
        pcmProgressFrames = mutableListOf()
        pcmFailure = null
    }

    override fun onDestroy() {
        stopPcmAnalyzer()
        pcmExecutor.shutdownNow()
        artworkExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun videoPermission(): String = if (Build.VERSION.SDK_INT >= 33) {
        Manifest.permission.READ_MEDIA_VIDEO
    } else {
        Manifest.permission.READ_EXTERNAL_STORAGE
    }

    private fun hasVideoPermission(): Boolean {
        val fullAccess =
            checkSelfPermission(videoPermission()) == PackageManager.PERMISSION_GRANTED
        val selectedAccess = Build.VERSION.SDK_INT >= 34 &&
            checkSelfPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) ==
            PackageManager.PERMISSION_GRANTED
        return fullAccess || selectedAccess
    }

    private fun requestVideoPermission(result: MethodChannel.Result) {
        if (hasVideoPermission()) {
            result.success(true)
            return
        }
        pendingVideoPermissionResult = result
        val permissions = if (Build.VERSION.SDK_INT >= 34) {
            arrayOf(
                videoPermission(),
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
        } else {
            arrayOf(videoPermission())
        }
        requestPermissions(permissions, 9001)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 9001) {
            pendingVideoPermissionResult?.success(hasVideoPermission())
            pendingVideoPermissionResult = null
        }
    }

    private fun videoThumbnail(
        uriString: String?,
        requestedWidth: Int,
        result: MethodChannel.Result,
    ) {
        if (!hasVideoPermission() || uriString.isNullOrBlank()) {
            result.success(null)
            return
        }
        val uri = Uri.parse(uriString)
        val width = requestedWidth.coerceIn(160, 1200)
        try {
            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentResolver.loadThumbnail(uri, Size(width, width), null)
            } else {
                val id = ContentUris.parseId(uri)
                MediaStore.Video.Thumbnails.getThumbnail(
                    contentResolver,
                    id,
                    MediaStore.Video.Thumbnails.MINI_KIND,
                    null,
                )
            }
            if (bitmap == null) {
                result.success(null)
                return
            }
            val bytes = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 86, bytes)
            bitmap.recycle()
            result.success(bytes.toByteArray())
        } catch (_: SecurityException) {
            result.success(null)
        } catch (_: Exception) {
            result.success(null)
        }
    }

    private fun readArtworkPixels(
        uriString: String?,
        requestedSize: Int,
        result: MethodChannel.Result,
    ) {
        if (uriString.isNullOrBlank()) {
            result.success(null)
            return
        }
        val uri = runCatching { Uri.parse(uriString) }.getOrNull()
        if (uri == null) {
            result.success(null)
            return
        }
        val size = requestedSize.coerceIn(16, 128)
        artworkExecutor.execute {
            val pixels = try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                contentResolver.openInputStream(uri)?.use { input ->
                    BitmapFactory.decodeStream(input, null, bounds)
                }
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                    null
                } else {
                    var sample = 1
                    while (bounds.outWidth / (sample * 2) >= size &&
                        bounds.outHeight / (sample * 2) >= size
                    ) {
                        sample *= 2
                    }
                    val options = BitmapFactory.Options().apply { inSampleSize = sample }
                    val decoded = contentResolver.openInputStream(uri)?.use { input ->
                        BitmapFactory.decodeStream(input, null, options)
                    }
                    if (decoded == null) {
                        null
                    } else {
                        val scaled = Bitmap.createScaledBitmap(decoded, size, size, true)
                        val output = IntArray(size * size)
                        scaled.getPixels(output, 0, size, 0, 0, size, size)
                        if (scaled !== decoded) scaled.recycle()
                        decoded.recycle()
                        output.toList()
                    }
                }
            } catch (_: Exception) {
                null
            }
            mainHandler.post { result.success(pixels) }
        }
    }

    private fun readOriginalArtwork(uriString: String?, result: MethodChannel.Result) {
        if (uriString.isNullOrBlank()) {
            result.success(null)
            return
        }
        val uri = runCatching { Uri.parse(uriString) }.getOrNull()
        if (uri == null) {
            result.success(null)
            return
        }
        artworkExecutor.execute {
            val artwork = try {
                val retriever = MediaMetadataRetriever()
                try {
                    if (uri.scheme == "file") {
                        val path = uri.path
                        if (path.isNullOrBlank()) null else {
                            retriever.setDataSource(path)
                            retriever.embeddedPicture
                        }
                    } else {
                        retriever.setDataSource(applicationContext, uri)
                        retriever.embeddedPicture
                    }
                } finally {
                    runCatching { retriever.release() }
                }
            } catch (_: Exception) {
                null
            }?.takeIf { it.isNotEmpty() && it.size <= 24 * 1024 * 1024 }
            mainHandler.post { result.success(artwork) }
        }
    }

    private fun queryVideos(result: MethodChannel.Result) {
        if (!hasVideoPermission()) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        val videos = LinkedHashMap<String, Map<String, Any>>()
        val collections = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.getExternalVolumeNames(this)
                .map { volume -> MediaStore.Video.Media.getContentUri(volume) }
                .ifEmpty { listOf(MediaStore.Video.Media.EXTERNAL_CONTENT_URI) }
        } else {
            listOf(MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
        }
        try {
            collections.forEach { collection ->
                val projection = arrayOf(
                    MediaStore.Video.Media._ID,
                    MediaStore.Video.Media.DATA,
                    MediaStore.Video.Media.DISPLAY_NAME,
                    MediaStore.Video.Media.DURATION,
                    MediaStore.Video.Media.SIZE,
                    MediaStore.Video.Media.DATE_ADDED,
                    MediaStore.MediaColumns.RELATIVE_PATH,
                )
                contentResolver.query(
                    collection,
                    projection,
                    null,
                    null,
                    "${MediaStore.Video.Media.DATE_ADDED} DESC",
                )?.use { cursor ->
                    val idIndex = cursor.getColumnIndex(MediaStore.Video.Media._ID)
                    val pathIndex = cursor.getColumnIndex(MediaStore.Video.Media.DATA)
                    val nameIndex = cursor.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
                    val durationIndex = cursor.getColumnIndex(MediaStore.Video.Media.DURATION)
                    val sizeIndex = cursor.getColumnIndex(MediaStore.Video.Media.SIZE)
                    val dateIndex = cursor.getColumnIndex(MediaStore.Video.Media.DATE_ADDED)
                    val relativeIndex = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
                    while (cursor.moveToNext()) {
                        if (idIndex < 0) continue
                        val id = cursor.getLong(idIndex)
                        val uri = ContentUris.withAppendedId(collection, id)
                        val name = if (nameIndex >= 0) {
                            cursor.getString(nameIndex) ?: "Local video"
                        } else {
                            "Local video"
                        }
                        val relative = if (relativeIndex >= 0) {
                            cursor.getString(relativeIndex).orEmpty()
                        } else {
                            ""
                        }
                        val path = if (pathIndex >= 0) {
                            cursor.getString(pathIndex).orEmpty()
                        } else {
                            ""
                        }
                        val duration = if (durationIndex >= 0) cursor.getLong(durationIndex) else 0L
                        val size = if (sizeIndex >= 0) cursor.getLong(sizeIndex) else 0L
                        val date = if (dateIndex >= 0) cursor.getLong(dateIndex) else 0L
                        val key = "${relative.lowercase()}|${name.lowercase()}|$size"
                        videos[key] = mapOf(
                            "path" to path,
                            "uri" to uri.toString(),
                            "title" to name,
                            "durationMs" to duration,
                            "sizeBytes" to size,
                            "dateAdded" to date,
                        )
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                val projection = arrayOf(
                    MediaStore.Downloads._ID,
                    MediaStore.Downloads.DISPLAY_NAME,
                    MediaStore.Downloads.MIME_TYPE,
                    MediaStore.Downloads.SIZE,
                    MediaStore.Downloads.DATE_ADDED,
                    MediaStore.MediaColumns.RELATIVE_PATH,
                )
                contentResolver.query(
                    collection,
                    projection,
                    null,
                    null,
                    "${MediaStore.Downloads.DATE_ADDED} DESC",
                )?.use { cursor ->
                    val idIndex = cursor.getColumnIndex(MediaStore.Downloads._ID)
                    val nameIndex = cursor.getColumnIndex(MediaStore.Downloads.DISPLAY_NAME)
                    val mimeIndex = cursor.getColumnIndex(MediaStore.Downloads.MIME_TYPE)
                    val sizeIndex = cursor.getColumnIndex(MediaStore.Downloads.SIZE)
                    val dateIndex = cursor.getColumnIndex(MediaStore.Downloads.DATE_ADDED)
                    val relativeIndex = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
                    while (cursor.moveToNext()) {
                        if (idIndex < 0 || nameIndex < 0) continue
                        val name = cursor.getString(nameIndex) ?: continue
                        val mime = if (mimeIndex >= 0) cursor.getString(mimeIndex).orEmpty() else ""
                        val isVideo = mime.startsWith("video/") ||
                            name.substringAfterLast('.', "").lowercase() in
                            setOf("mp4", "mkv", "webm", "mov", "avi", "3gp", "m4v", "ts")
                        if (!isVideo) continue
                        val id = cursor.getLong(idIndex)
                        val uri = ContentUris.withAppendedId(collection, id)
                        val relative = if (relativeIndex >= 0) {
                            cursor.getString(relativeIndex).orEmpty()
                        } else {
                            ""
                        }
                        val size = if (sizeIndex >= 0) cursor.getLong(sizeIndex) else 0L
                        val date = if (dateIndex >= 0) cursor.getLong(dateIndex) else 0L
                        val key = "${relative.lowercase()}|${name.lowercase()}|$size"
                        videos[key] = mapOf(
                            "path" to "",
                            "uri" to uri.toString(),
                            "title" to name,
                            "durationMs" to 0L,
                            "sizeBytes" to size,
                            "dateAdded" to date,
                        )
                    }
                }
            }
            result.success(videos.values.sortedByDescending { it["dateAdded"] as? Long ?: 0L })
        } catch (_: SecurityException) {
            result.success(videos.values.toList())
        } catch (_: Exception) {
            result.success(videos.values.toList())
        }
    }

}
