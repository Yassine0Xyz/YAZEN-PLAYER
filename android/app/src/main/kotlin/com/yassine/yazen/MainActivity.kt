package com.yassine.yazen

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.LinkedHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt

class MainActivity : AudioServiceActivity() {
    private val channelName = "yazen/local_media"
    private val playerControlsChannelName = "yazen/player_controls"
    private val pipActionExtra = "yazen.video_pip_action"
    private var playerControlsChannel: MethodChannel? = null
    private var videoPipIsPlaying = false
    private var videoPipHasPrevious = false
    private var videoPipHasNext = false
    private var isInPictureInPictureMode = false
    private var pipReceiverRegistered = false
    private val videoPipActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val actionIdentifier = intent?.getStringExtra(pipActionExtra) ?: return
            if (actionIdentifier in VIDEO_PIP_ACTIONS) {
                playerControlsChannel?.invokeMethod("onVideoPipAction", actionIdentifier)
            }
        }
    }
    private val pcmTag = "YAZENPcm"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val deleteAudioRequestCode = 4207
    private var pendingVideoPermissionResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeleteIds: List<Int> = emptyList()
    private val pcmExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val lacteaPcmExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val lacteaPcmFeedPending = AtomicBoolean(false)
    private val artworkExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    // MediaStore enumeration and thumbnail decoding must never run on Flutter's
    // platform thread. Keep the two workloads isolated so a large library scan
    // cannot starve thumbnails for the currently visible video cards.
    private val videoQueryExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val videoThumbnailExecutor: ExecutorService = Executors.newFixedThreadPool(2)
    private val pendingVideoQueryResults = mutableListOf<MethodChannel.Result>()
    private var videoQueryInFlight = false
    @Volatile
    private var activityDestroyed = false
    @Volatile private var pcmGeneration = 0
    @Volatile private var pcmWorkingFile: File? = null
    @Volatile private var lacteaEnabled = false
    @Volatile private var pcmCurrentUri: String? = null
    private val lacteaSidecarRequested = AtomicBoolean(false)
    @Volatile private var pcmLastFedPositionMs: Long? = null
    @Volatile private var pcmLastFeedDurationMs = 40L
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

    companion object {
        private val VIDEO_PIP_ACTIONS = setOf(
            "video_previous",
            "video_play_pause",
            "video_stop",
            "video_next",
        )
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        cleanupLacteaPcmSidecars()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val filter = IntentFilter().apply {
                VIDEO_PIP_ACTIONS.forEach(::addAction)
            }
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(videoPipActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(videoPipActionReceiver, filter)
            }
            pipReceiverRegistered = true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "yazen/lactea").setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(LacteaNative.available)
                "getStatus" -> result.success(mapOf("available" to LacteaNative.available, "loadError" to LacteaNative.loadFailure, "nativeVersion" to if (LacteaNative.available) runCatching { LacteaNative.nativeVersion() }.getOrNull() else null))
                "setEnabled" -> { lacteaEnabled = call.argument<Boolean>("enabled") == true; result.success(null) }
                else -> result.notImplemented()
            }
        }
        flutterEngine.platformViewsController.registry.registerViewFactory("yazen/lactea_visualizer", LacteaPlatformViewFactory(messenger))
        MethodChannel(messenger, channelName)
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
                        call.argument<Int>("size") ?: 256,
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
                        call.argument<Number>("speed")?.toDouble() ?: 1.0,
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

        playerControlsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            playerControlsChannelName,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
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
                    "updateVideoPipActions" -> {
                        videoPipIsPlaying = call.argument<Boolean>("isPlaying") ?: false
                        videoPipHasPrevious = call.argument<Boolean>("hasPrevious") ?: false
                        videoPipHasNext = call.argument<Boolean>("hasNext") ?: false
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode) {
                            setPictureInPictureParams(buildPictureInPictureParams())
                        }
                        result.success(null)
                    }
                    "enterPictureInPicture" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            enterPictureInPictureMode(buildPictureInPictureParams())
                            result.success(null)
                        } else {
                            result.error("UNAVAILABLE", "Picture-in-picture requires Android 8.0 or newer.", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun buildPictureInPictureParams(): PictureInPictureParams {
        val actions = mutableListOf<RemoteAction>()
        if (videoPipHasPrevious) {
            actions.add(createVideoPipAction("video_previous", android.R.drawable.ic_media_previous, "Previous"))
        }
        actions.add(
            createVideoPipAction(
                "video_play_pause",
                if (videoPipIsPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (videoPipIsPlaying) "Pause" else "Play",
            ),
        )
        if (videoPipHasNext) {
            actions.add(createVideoPipAction("video_next", android.R.drawable.ic_media_next, "Next"))
        }
        return PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setActions(actions)
            .build()
    }

    private fun createVideoPipAction(identifier: String, icon: Int, title: String): RemoteAction {
        val intent = Intent(identifier).apply {
            action = identifier
            putExtra(pipActionExtra, identifier)
            setPackage(packageName)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            identifier.hashCode(),
            intent,
            flags,
        )
        return RemoteAction(
            android.graphics.drawable.Icon.createWithResource(this, icon),
            title,
            title,
            pendingIntent,
        )
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        this.isInPictureInPictureMode = isInPictureInPictureMode
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

    private fun cleanupLacteaPcmSidecars() { val dir=File(cacheDir,"lactea_pcm");runCatching{dir.listFiles()?.forEach{it.delete()};dir.mkdirs()} }
    private fun cleanupPcmSidecarsExcept(keep:File?){val dir=File(cacheDir,"lactea_pcm");runCatching{dir.listFiles()?.forEach{if(it!=keep)it.delete()};dir.mkdirs()}}
    private fun pcmCacheKey(uri:String)=MessageDigest.getInstance("SHA-256").digest(uri.toByteArray(Charsets.UTF_8)).joinToString(""){(it.toInt()and 255).toString(16).padStart(2,'0')}
    private fun startPcmAnalyzer(uriString:String?,result:MethodChannel.Result){
        stopPcmAnalyzer();if(uriString.isNullOrBlank()){result.success(mapOf<String,Any>("started" to false,"state" to "unavailable"));return}
        pcmCurrentUri = uriString
        lacteaSidecarRequested.set(false)
        val generation=++pcmGeneration;val cached=pcmCache[uriString]
        if(cached!=null&&(cached.pcmFile?.isFile==true||!lacteaEnabled)){if(lacteaEnabled)cleanupPcmSidecarsExcept(cached.pcmFile);pcmResult=cached;pcmWorkingFile=cached.pcmFile;pcmProgressFrames=cached.frames.toMutableList();pcmState="ready";pcmFailure=null;result.success(mapOf<String,Any>("started" to true,"mode" to "pcm_cache","state" to "ready"));return}
        val pcmFile=if(lacteaEnabled)File(cacheDir,"lactea_pcm/${pcmCacheKey(uriString)}.pcm") else null
        if(pcmFile!=null){cleanupPcmSidecarsExcept(pcmFile);pcmFile.parentFile?.mkdirs();lacteaSidecarRequested.set(true)};pcmWorkingFile=pcmFile
        pcmState="preparing";pcmResult=null;pcmProgressFrames=mutableListOf();pcmFailure=null
        result.success(mapOf<String,Any>("started" to true,"mode" to "pcm_file","state" to "preparing"))
        pcmExecutor.execute {
            val analysis=PcmSpectrumAnalyzer(contentResolver){generation!=pcmGeneration}.analyze(Uri.parse(uriString),pcmOutputFile=pcmFile){frames->mainHandler.post{if(generation==pcmGeneration)pcmProgressFrames.addAll(frames)}}
            mainHandler.post{if(generation!=pcmGeneration)return@post;lacteaSidecarRequested.set(false);if(analysis==null){pcmState=if(pcmProgressFrames.isEmpty())"unavailable" else "ready";if(pcmProgressFrames.isEmpty()){pcmFailure=if(lacteaEnabled)"lactea_pcm_decode_failed" else "decoder_failed";pcmWorkingFile?.delete();pcmWorkingFile=null}else if(pcmFile!=null){pcmWorkingFile=pcmFile}}else{pcmCache[uriString]=analysis;pcmResult=analysis;pcmWorkingFile=analysis.pcmFile;pcmProgressFrames=analysis.frames.toMutableList();pcmState="ready";pcmFailure=null;Log.i(pcmTag,"PCM ready frames=${analysis.frames.size} rate=${analysis.sampleRate}")}}
        }
    }

    private fun readPcmAnalyzer(positionMs: Long, speed: Double, result: MethodChannel.Result) {
        feedLacteaPcm(positionMs, speed)
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

    private fun ensureLacteaPcmSidecar() {
        val uriString = pcmCurrentUri ?: return
        if (!lacteaEnabled || pcmFailure == "lactea_pcm_decode_failed" || pcmWorkingFile != null || !lacteaSidecarRequested.compareAndSet(false, true)) return
        val cached = pcmCache[uriString]
        if (cached?.pcmFile?.isFile == true) {
            pcmResult = cached; pcmWorkingFile = cached.pcmFile; lacteaSidecarRequested.set(false); return
        }
        val file = File(cacheDir, "lactea_pcm/${pcmCacheKey(uriString)}.pcm")
        cleanupPcmSidecarsExcept(file); file.parentFile?.mkdirs()
        val generation = ++pcmGeneration
        pcmWorkingFile = file; pcmResult = null; pcmProgressFrames = mutableListOf(); pcmState = "preparing"; pcmFailure = null
        pcmExecutor.execute {
            val analysis = PcmSpectrumAnalyzer(contentResolver) { generation != pcmGeneration }
                .analyze(Uri.parse(uriString), pcmOutputFile = file) { frames ->
                    mainHandler.post { if (generation == pcmGeneration) pcmProgressFrames.addAll(frames) }
                }
            mainHandler.post {
                if (generation != pcmGeneration) { lacteaSidecarRequested.set(false); return@post }
                lacteaSidecarRequested.set(false)
                if (analysis == null) {
                    pcmState = if (pcmProgressFrames.isEmpty()) "unavailable" else "ready"
                    if (pcmProgressFrames.isEmpty()) { pcmFailure = "lactea_pcm_decode_failed"; pcmWorkingFile?.delete(); pcmWorkingFile = null }
                } else {
                    pcmCache[uriString] = analysis; pcmResult = analysis; pcmWorkingFile = analysis.pcmFile
                    pcmProgressFrames = analysis.frames.toMutableList(); pcmState = "ready"; pcmFailure = null
                }
            }
        }
    }

    private fun feedLacteaPcm(positionMs:Long,speed:Double){
        if(!lacteaEnabled||LacteaSessionRegistry.activeCount==0||!LacteaNative.available)return
        val file=pcmResult?.pcmFile?:pcmWorkingFile
        if(file==null||!file.isFile){if(pcmWorkingFile?.isFile!=true)pcmWorkingFile=null;ensureLacteaPcmSidecar();return}
        val rate=pcmResult?.pcmSampleRate?:22050;val duration=(40.0*speed.coerceIn(.25,3.0)).toInt().coerceIn(8,160);val pos=positionMs.coerceAtLeast(0);val generation=pcmGeneration
        if(!lacteaPcmFeedPending.compareAndSet(false,true))return
        lacteaPcmExecutor.execute{try{if(generation!=pcmGeneration||!file.isFile)return@execute;val start=pos*rate/1000L;val wanted=(rate.toLong()*duration/1000L).toInt().coerceIn(128,8192)
            RandomAccessFile(file,"r").use{f->val offset=start*4L;val available=((f.length()-offset)/4L).coerceAtLeast(0);val count=minOf(wanted.toLong(),available).toInt();if(count<64||generation!=pcmGeneration)return@use
                val bytes=ByteArray(count*4);f.seek(offset);f.readFully(bytes);if(generation!=pcmGeneration)return@use
                val b=ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);val samples=FloatArray(count*2){(b.short.toInt()/32768f).coerceIn(-1f,1f)}
                val expected=pcmLastFedPositionMs?.plus(pcmLastFeedDurationMs);if(expected!=null&&kotlin.math.abs(pos-expected)>180L)LacteaSessionRegistry.resetAudio()
                if(generation==pcmGeneration){LacteaSessionRegistry.pushPcm(samples,2,rate);pcmLastFedPositionMs=pos;pcmLastFeedDurationMs=count.toLong()*1000L/rate}
            }
        }catch(e:Exception){Log.w(pcmTag,"Lactea PCM slice failed",e)}finally{lacteaPcmFeedPending.set(false)}}
    }
    private fun stopPcmAnalyzer(){pcmGeneration++;pcmCurrentUri=null;lacteaSidecarRequested.set(false);pcmState="idle";pcmResult=null;pcmProgressFrames=mutableListOf();pcmFailure=null;val old=pcmWorkingFile;pcmWorkingFile=null;if(old!=null&&pcmCache.values.none{it.pcmFile==old})runCatching{old.delete()};pcmLastFedPositionMs=null;pcmLastFeedDurationMs=40L;lacteaPcmExecutor.execute{LacteaSessionRegistry.resetAudio()}}

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
        val uri = runCatching { Uri.parse(uriString) }.getOrNull()
        if (uri == null || uri.scheme != "content") {
            result.success(null)
            return
        }
        val width = requestedWidth.coerceIn(160, 1200)
        try {
            videoThumbnailExecutor.execute {
                var bitmap: Bitmap? = null
                val bytes = try {
                    bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
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
                    bitmap?.let { thumbnail ->
                        ByteArrayOutputStream().use { output ->
                            if (thumbnail.compress(Bitmap.CompressFormat.JPEG, 86, output)) {
                                output.toByteArray()
                            } else {
                                null
                            }
                        }
                    }
                } catch (_: SecurityException) {
                    null
                } catch (_: Exception) {
                    null
                } finally {
                    bitmap?.recycle()
                }
                mainHandler.post {
                    if (!activityDestroyed) {
                        result.success(bytes)
                    } else {
                        runCatching {
                            result.error("activity_destroyed", "The activity closed during thumbnail loading.", null)
                        }
                    }
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            result.error("thumbnail_executor_closed", "Thumbnail loading is unavailable because the activity is closing.", null)
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

    private fun readOriginalArtwork(
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
        val targetSize = requestedSize.coerceIn(16, 2048)
        artworkExecutor.execute {
            val artwork = try {
                val retriever = MediaMetadataRetriever()
                val embedded = try {
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
                embedded?.takeIf { it.isNotEmpty() && it.size <= 24 * 1024 * 1024 }?.let {
                    decodeEmbeddedArtworkThumbnail(it, targetSize)
                }
            } catch (_: Exception) {
                null
            }
            mainHandler.post { result.success(artwork) }
        }
    }

    /** Decode embedded cover art near its display size, not at source resolution. */
    private fun decodeEmbeddedArtworkThumbnail(
        encoded: ByteArray,
        targetSize: Int,
    ): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(encoded, 0, encoded.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sampleSize = 1
        while (
            maxOf(bounds.outWidth, bounds.outHeight) / (sampleSize * 2) >= targetSize
        ) {
            sampleSize *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        val decoded = BitmapFactory.decodeByteArray(encoded, 0, encoded.size, options)
            ?: return null
        var outputBitmap: Bitmap? = null
        try {
            val scale = minOf(
                1.0,
                targetSize.toDouble() / maxOf(decoded.width, decoded.height),
            )
            val width = (decoded.width * scale).roundToInt().coerceAtLeast(1)
            val height = (decoded.height * scale).roundToInt().coerceAtLeast(1)
            val rendered = if (width != decoded.width || height != decoded.height) {
                Bitmap.createScaledBitmap(decoded, width, height, true)
            } else {
                decoded
            }
            outputBitmap = rendered
            val output = ByteArrayOutputStream()
            try {
                if (!rendered.compress(Bitmap.CompressFormat.JPEG, 86, output)) return null
                return output.toByteArray()
            } finally {
                output.close()
            }
        } finally {
            if (outputBitmap != null && outputBitmap !== decoded) outputBitmap?.recycle()
            decoded.recycle()
        }
    }

    private fun queryVideos(result: MethodChannel.Result) {
        if (activityDestroyed) {
            result.error("activity_destroyed", "The activity is closing.", null)
            return
        }
        if (!hasVideoPermission()) {
            result.success(emptyList<Map<String, Any>>())
            return
        }

        // Coalesce concurrent refresh requests into one MediaStore traversal.
        // The Flutter side also bounds thumbnail demand, so this executor never
        // competes with thumbnail decoding on the platform thread.
        pendingVideoQueryResults.add(result)
        if (videoQueryInFlight) return
        videoQueryInFlight = true
        try {
            videoQueryExecutor.execute {
                val videos = runCatching { queryVideosBlocking() }
                mainHandler.post {
                    videoQueryInFlight = false
                    if (activityDestroyed) return@post
                    val waiting = pendingVideoQueryResults.toList()
                    pendingVideoQueryResults.clear()
                    waiting.forEach { pending ->
                        runCatching {
                            videos.fold(
                                onSuccess = { pending.success(it) },
                                onFailure = {
                                    pending.error(
                                        "video_query_failed",
                                        it.message ?: "Unable to scan local videos.",
                                        null,
                                    )
                                },
                            )
                        }
                    }
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            videoQueryInFlight = false
            pendingVideoQueryResults.remove(result)
            result.error("video_query_unavailable", "Video indexing is unavailable because the activity is closing.", null)
        }
    }

    private fun queryVideosBlocking(): List<Map<String, Any>> {
        if (!hasVideoPermission()) return emptyList()
        val videos = LinkedHashMap<String, Map<String, Any>>()
        try {
            val collections = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.getExternalVolumeNames(this)
                    .map { volume -> MediaStore.Video.Media.getContentUri(volume) }
                    .ifEmpty { listOf(MediaStore.Video.Media.EXTERNAL_CONTENT_URI) }
            } else {
                listOf(MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
            }
            collections.forEach { collection ->
                val projection = arrayOf(
                    MediaStore.Video.Media._ID,
                    MediaStore.Video.Media.DATA,
                    MediaStore.Video.Media.DISPLAY_NAME,
                    MediaStore.Video.Media.DURATION,
                    MediaStore.Video.Media.SIZE,
                    MediaStore.Video.Media.DATE_ADDED,
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
                    while (cursor.moveToNext()) {
                        if (idIndex < 0) continue
                        val id = cursor.getLong(idIndex)
                        val uri = ContentUris.withAppendedId(collection, id)
                        val name = if (nameIndex >= 0) {
                            cursor.getString(nameIndex) ?: "Local video"
                        } else {
                            "Local video"
                        }
                        val path = if (pathIndex >= 0) {
                            cursor.getString(pathIndex).orEmpty()
                        } else {
                            ""
                        }
                        val duration = if (durationIndex >= 0) cursor.getLong(durationIndex) else 0L
                        val size = if (sizeIndex >= 0) cursor.getLong(sizeIndex) else 0L
                        val date = if (dateIndex >= 0) cursor.getLong(dateIndex) else 0L
                        // URI identity avoids collisions between two same-named
                        // videos that happen to have the same byte size.
                        videos[uri.toString()] = mapOf(
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
                        val size = if (sizeIndex >= 0) cursor.getLong(sizeIndex) else 0L
                        val date = if (dateIndex >= 0) cursor.getLong(dateIndex) else 0L
                        videos.putIfAbsent(
                            uri.toString(),
                            mapOf(
                                "path" to "",
                                "uri" to uri.toString(),
                                "title" to name,
                                "durationMs" to 0L,
                                "sizeBytes" to size,
                                "dateAdded" to date,
                            ),
                        )
                    }
                }
            }
        } catch (_: SecurityException) {
            // Return the successfully scanned subset when permission is partial
            // or revoked during traversal.
        } catch (_: Exception) {
            // A provider failure should not crash the Activity or Flutter UI.
        }
        return videos.values.sortedByDescending { it["dateAdded"] as? Long ?: 0L }
    }

    override fun onDestroy() {
        if (pipReceiverRegistered) {
            runCatching { unregisterReceiver(videoPipActionReceiver) }
            pipReceiverRegistered = false
        }
        playerControlsChannel = null
        stopPcmAnalyzer()
        activityDestroyed = true
        val waiting = pendingVideoQueryResults.toList()
        pendingVideoQueryResults.clear()
        waiting.forEach { pending ->
            runCatching {
                pending.error("activity_destroyed", "The activity was closed during video indexing.", null)
            }
        }
        videoQueryExecutor.shutdownNow()
        videoThumbnailExecutor.shutdownNow()
        pcmExecutor.shutdownNow()
        lacteaPcmExecutor.shutdownNow()
        artworkExecutor.shutdownNow()
        super.onDestroy()
    }

}
