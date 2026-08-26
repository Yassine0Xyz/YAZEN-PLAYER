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
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt
import kotlin.math.sqrt

class MainActivity : AudioServiceActivity() {
    private val channelName = "yazen/local_media"
    private var visualizer: Visualizer? = null
    private var visualizerSink: EventChannel.EventSink? = null

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

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "yazen/audio_fft")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    visualizerSink = events
                    val sessionId = (arguments as? Map<*, *>)?.get("sessionId") as? Int
                    if (sessionId != null && sessionId > 0) startVisualizer(sessionId)
                }

                override fun onCancel(arguments: Any?) {
                    visualizerSink = null
                    stopVisualizer()
                }
            })

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

    private fun startVisualizer(sessionId: Int) {
        stopVisualizer()
        try {
            val captureSize = Visualizer.getCaptureSizeRange()[1].coerceAtMost(1024)
            val next = Visualizer(sessionId)
            next.captureSize = captureSize
            next.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer,
                        waveform: ByteArray,
                        samplingRate: Int,
                    ) = Unit

                    override fun onFftDataCapture(
                        visualizer: Visualizer,
                        fft: ByteArray,
                        samplingRate: Int,
                    ) {
                        val bands = ArrayList<Float>(24)
                        var index = 2
                        while (index + 1 < fft.size && bands.size < 24) {
                            val real = fft[index].toFloat()
                            val imaginary = fft[index + 1].toFloat()
                            val magnitude = sqrt(real * real + imaginary * imaginary)
                            bands.add((magnitude / 128f).coerceIn(0f, 1f))
                            index += 2
                        }
                        runOnUiThread { visualizerSink?.success(bands) }
                    }
                },
                Visualizer.getMaxCaptureRate() / 2,
                false,
                true,
            )
            next.enabled = true
            visualizer = next
        } catch (_: Exception) {
            stopVisualizer()
        }
    }

    private fun stopVisualizer() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {
        } finally {
            visualizer = null
        }
    }

    override fun onDestroy() {
        stopVisualizer()
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
