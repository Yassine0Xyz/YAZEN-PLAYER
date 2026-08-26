package com.example.yazen

import android.Manifest
import android.app.PictureInPictureParams
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.audiofx.Visualizer
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Rational
import android.util.Size
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt

class MainActivity : AudioServiceActivity() {
    private val channelName = "yazen/local_media"
    private var audioVisualizer: Visualizer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestVideoPermission" -> result.success(requestVideoPermission())
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
                    "stop" -> {
                        stopAudioVisualizer()
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
        if (sessionId == null || sessionId <= 0) {
            result.success(false)
            return
        }
        try {
            stopAudioVisualizer()
            audioVisualizer = Visualizer(sessionId).apply {
                captureSize = Visualizer.getCaptureSizeRange()[1]
                enabled = true
            }
            result.success(true)
        } catch (_: Throwable) {
            stopAudioVisualizer()
            result.success(false)
        }
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
            if (visualizer.getFft(fft) != Visualizer.SUCCESS) {
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
            result.success(levels)
        } catch (_: Throwable) {
            stopAudioVisualizer()
            result.success(null)
        }
    }

    private fun stopAudioVisualizer() {
        try {
            audioVisualizer?.enabled = false
        } catch (_: Throwable) {
        }
        try {
            audioVisualizer?.release()
        } catch (_: Throwable) {
        }
        audioVisualizer = null
    }

    override fun onDestroy() {
        stopAudioVisualizer()
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
