package com.yassine.yazen

import android.Manifest
import android.app.PictureInPictureParams
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.audiofx.Visualizer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
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
    private val visualizerTag = "YAZENVisualizer"
    private var audioVisualizer: Visualizer? = null
    private var activeVisualizerSessionId: Int? = null
    private var lastFftDiagnosticMs = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pcmExecutor: ExecutorService = Executors.newSingleThreadExecutor()
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
                    "requestVideoPermission" -> result.success(requestVideoPermission())
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
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yazen/audio_visualizer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startAudioVisualizer(call.argument<Int>("sessionId"), result)
                    "read" -> readAudioVisualizer(result)
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
                        stopAudioVisualizer()
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

    private fun startAudioVisualizer(sessionId: Int?, result: MethodChannel.Result) {
        // Prefer just_audio's session. If it is unavailable or rejected by the
        // device, use Android's global output mix. Both paths read real FFT
        // data; the fallback is not a synthetic animation.
        val candidates = listOfNotNull(sessionId?.takeIf { it > 0 }, 0).distinct()
        Log.d(visualizerTag, "start requested sessionId=${sessionId ?: 0} candidates=$candidates")
        stopAudioVisualizer()
        for (candidate in candidates) {
            try {
                val captureSize = Visualizer.getCaptureSizeRange()[1]
                audioVisualizer = Visualizer(candidate).apply {
                    this.captureSize = captureSize
                    scalingMode = Visualizer.SCALING_MODE_NORMALIZED
                    enabled = true
                }
                val mode = if (candidate == 0) "global_mix" else "track_session"
                activeVisualizerSessionId = candidate
                Log.i(
                    visualizerTag,
                    "attached mode=$mode sessionId=$candidate captureSize=$captureSize",
                )
                result.success(
                    mapOf<String, Any>(
                        "started" to true,
                        "mode" to mode,
                        "sessionId" to candidate,
                    ),
                )
                return
            } catch (error: Throwable) {
                Log.w(
                    visualizerTag,
                    "attach failed sessionId=$candidate type=${error::class.java.simpleName} message=${error.message}",
                )
                stopAudioVisualizer()
            }
        }
        Log.e(visualizerTag, "no visualizer session could be attached")
        result.success(mapOf<String, Any>("started" to false, "mode" to "unavailable"))
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
                visualizerTag,
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
        Log.i(visualizerTag, "pcm start requested uri=$uriString")
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
                    Log.w(visualizerTag, "pcm analysis unavailable uri=$uriString frames=${pcmProgressFrames.size}")
                } else {
                    pcmCache[uriString] = analysis
                    pcmResult = analysis
                    pcmProgressFrames = analysis.frames.toMutableList()
                    pcmState = "ready"
                    Log.i(
                        visualizerTag,
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
            result.success(mapOf<String, Any>("state" to "preparing"))
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

    private fun readAudioVisualizer(result: MethodChannel.Result) {
        val visualizer = audioVisualizer
        if (visualizer == null || !visualizer.enabled) {
            result.success(null)
            return
        }
        try {
            // FFT returns interleaved real/imaginary signed bytes. Skip the
            // DC component and convert each bin to a normalized magnitude so
            // Dart can render genuine Bass-to-Treble energy bands.
            val fft = ByteArray(visualizer.captureSize)
            val fftResult = visualizer.getFft(fft)
            if (fftResult != Visualizer.SUCCESS) {
                Log.w(visualizerTag, "getFft failed result=$fftResult")
                result.success(null)
                return
            }
            val levels = mutableListOf<Float>()
            var index = 2
            while (index + 1 < fft.size) {
                val real = fft[index].toInt()
                val imaginary = fft[index + 1].toInt()
                val magnitude = kotlin.math.sqrt(
                    (real * real + imaginary * imaginary).toFloat(),
                ) / 128f
                levels.add(magnitude.coerceIn(0f, 1f))
                index += 2
            }
            val now = SystemClock.elapsedRealtime()
            if (now - lastFftDiagnosticMs >= 2000L) {
                lastFftDiagnosticMs = now
                val maximum = levels.maxOrNull() ?: 0f
                val average = if (levels.isEmpty()) 0f else levels.average().toFloat()
                Log.d(
                    visualizerTag,
                    "fft ok session=${activeVisualizerSessionId ?: 0} bins=${levels.size} max=${"%.3f".format(maximum)} avg=${"%.3f".format(average)}",
                )
            }
            result.success(levels)
        } catch (error: Throwable) {
            Log.e(
                visualizerTag,
                "read failed type=${error::class.java.simpleName} message=${error.message}",
            )
            stopAudioVisualizer()
            result.success(null)
        }
    }

    private fun stopAudioVisualizer() {
        val hadVisualizer = audioVisualizer != null
        try {
            audioVisualizer?.enabled = false
        } catch (error: Throwable) {
            Log.w(visualizerTag, "disable failed message=${error.message}")
        }
        try {
            audioVisualizer?.release()
        } catch (error: Throwable) {
            Log.w(visualizerTag, "release failed message=${error.message}")
        }
        audioVisualizer = null
        activeVisualizerSessionId = null
        if (hadVisualizer) Log.d(visualizerTag, "stopped")
    }

    override fun onDestroy() {
        stopAudioVisualizer()
        stopPcmAnalyzer()
        pcmExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun videoPermission(): String = if (Build.VERSION.SDK_INT >= 33) {
        Manifest.permission.READ_MEDIA_VIDEO
    } else {
        Manifest.permission.READ_EXTERNAL_STORAGE
    }

    private fun hasVideoPermission(): Boolean =
        checkSelfPermission(videoPermission()) == PackageManager.PERMISSION_GRANTED

    private fun requestVideoPermission(): Boolean {
        if (hasVideoPermission()) return true
        requestPermissions(arrayOf(videoPermission()), 9001)
        return false
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

    private fun queryVideos(result: MethodChannel.Result) {
        if (!hasVideoPermission()) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DURATION,
        )
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                "${MediaStore.Video.Media.DATE_ADDED} DESC",
            )
            val videos = mutableListOf<Map<String, Any>>()
            cursor?.use {
                val idIndex = it.getColumnIndex(MediaStore.Video.Media._ID)
                val pathIndex = it.getColumnIndex(MediaStore.Video.Media.DATA)
                val nameIndex = it.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
                val durationIndex = it.getColumnIndex(MediaStore.Video.Media.DURATION)
                while (it.moveToNext()) {
                    if (idIndex < 0) continue
                    val id = it.getLong(idIndex)
                    val contentUri = ContentUris.withAppendedId(
                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                        id,
                    ).toString()
                    val path = if (pathIndex >= 0) it.getString(pathIndex) ?: "" else ""
                    val title = if (nameIndex >= 0) {
                        it.getString(nameIndex) ?: "Local video"
                    } else {
                        "Local video"
                    }
                    videos.add(
                        mapOf(
                            "path" to path,
                            "uri" to contentUri,
                            "title" to title,
                            "durationMs" to if (durationIndex >= 0) it.getLong(durationIndex) else 0L,
                        ),
                    )
                }
            }
            result.success(videos)
        } catch (_: SecurityException) {
            result.success(emptyList<Map<String, Any>>())
        } catch (_: Exception) {
            result.success(emptyList<Map<String, Any>>())
        } finally {
            cursor?.close()
        }
    }
}
