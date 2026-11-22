package com.yassine.yazen

import android.content.Context
import android.app.ActivityManager
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

private data class LacteaPreset(val title: String, val assetPath: String)
internal object LacteaSessionRegistry {
    private val lock=Any(); private val handles=LinkedHashMap<Int,Long>()
    val activeCount:Int get()=synchronized(lock){handles.size}
    fun register(id:Int,h:Long)=synchronized(lock){handles[id]=h}
    fun unregister(id:Int)=synchronized(lock){handles.remove(id)}
    fun pushPcm(samples:FloatArray,channels:Int,rate:Int)=synchronized(lock){handles.values.toList().forEach{LacteaNative.nativePushPcm(it,samples,channels,rate)}}
    fun resetAudio()=synchronized(lock){handles.values.toList().forEach{LacteaNative.nativeResetAudio(it)}}
}
internal class LacteaPlatformViewFactory(private val messenger:BinaryMessenger):PlatformViewFactory(StandardMessageCodec.INSTANCE){
    override fun create(context:Context,viewId:Int,args:Any?):PlatformView {
        val playing=(args as? Map<*,*>)?.get("playing") as? Boolean ?: false
        return LacteaPlatformView(context,viewId,playing,messenger)
    }
}
private class LacteaPlatformView(private val context:Context,private val viewId:Int,initiallyPlaying:Boolean,messenger:BinaryMessenger):PlatformView,MethodChannel.MethodCallHandler{
    private data class Quality(val name:String,val width:Int,val height:Int,val fps:Int)
    companion object {
        private const val TAG="YAZENLactea";private const val AUTO_MS=40_000L
        private fun selectQuality(context:Context):Quality {
            val memory= (context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager)
                ?.memoryInfo?.totalMem?.div(1024L*1024L) ?: 4096L
            val cores=Runtime.getRuntime().availableProcessors()
            return when {
                memory<4096L || cores<=4 -> Quality("Saver",400,124,18)
                memory<7168L || cores<=6 -> Quality("Balanced",540,168,24)
                else -> Quality("High",720,224,30)
            }
        }
    }
    private val quality=selectQuality(context)
    private val W=quality.width;private val H=quality.height;private val framePeriodMs=(1000L/quality.fps).coerceAtLeast(1L)
    private val root=FrameLayout(context).apply{setBackgroundColor(Color.rgb(5,8,16))}
    private val image=ImageView(context).apply{scaleType=ImageView.ScaleType.FIT_XY;setBackgroundColor(Color.rgb(5,8,16))}
    private val title=TextView(context).apply{setTextColor(Color.WHITE);textSize=9f;letterSpacing=.08f;setPadding(dp(8),dp(5),dp(8),dp(5));setBackgroundColor(0x88070B16.toInt());text="LACTEA / INITIALIZING"}
    private val main=Handler(Looper.getMainLooper());private val renderer=Executors.newSingleThreadScheduledExecutor();private val channel=MethodChannel(messenger,"yazen/lactea_view_$viewId")
    private val presets=loadPresets();@Volatile private var handle=0L;@Volatile private var playing=initiallyPlaying;@Volatile private var disposed=false
    @Volatile private var windowActive=true
    @Volatile private var index=0;@Volatile private var lastAttempted=0;@Volatile private var switching=false;@Volatile private var lastSwitch=SystemClock.elapsedRealtime()
    private var failures=0;private var task:ScheduledFuture<*>?=null;private var bitmap:Bitmap?=null
    private val rgbaBuffer=ByteArray(W*H*4);private val pixelBuffer=IntArray(W*H);private val framePostPending=java.util.concurrent.atomic.AtomicBoolean(false)
    init {
        root.addView(image,FrameLayout.LayoutParams(-1,-1));root.addView(title,FrameLayout.LayoutParams(-2,-2,Gravity.TOP or Gravity.START).apply{setMargins(dp(8),dp(8),0,0)})
        channel.setMethodCallHandler(this);bitmap=Bitmap.createBitmap(W,H,Bitmap.Config.ARGB_8888);image.setImageBitmap(bitmap)
        root.viewTreeObserver.addOnWindowFocusChangeListener(object:ViewTreeObserver.OnWindowFocusChangeListener{
            override fun onWindowFocusChanged(hasFocus:Boolean){windowActive=hasFocus;if(hasFocus&&playing)start() else if(!hasFocus)stop()}
        })
        if(LacteaNative.available) renderer.execute {
            val first=presets.firstOrNull();val bytes=first?.let(::readPreset)
            val creation = if(first==null) Result.failure(IllegalStateException("No MilkDrop presets were packaged")) else if(bytes==null) Result.failure(IllegalStateException("Could not read the first MilkDrop preset asset")) else runCatching{LacteaNative.nativeCreate(W,H,bytes,first.title,textureDirectory())}
            val created = creation.getOrDefault(0L)
            val failure = creation.exceptionOrNull()?.let { it.message ?: it.javaClass.simpleName }
            main.post {
                if(disposed){if(created!=0L)runCatching{LacteaNative.nativeDestroy(created)};return@post}
                handle=created
                if(created!=0L){LacteaSessionRegistry.register(viewId,created);title.text="LACTEA / ${first!!.title.uppercase()} · ${quality.name}";channel.invokeMethod("engineReady",mapOf("presetCount" to presets.size,"quality" to quality.name,"width" to W,"height" to H,"fps" to quality.fps));renderer.execute{render()};if(playing)start()}
                else { val reason=failure ?: "Native engine returned a null handle";Log.e(TAG,"Lactea initialization failed: $reason");title.text="LACTEA / INITIALIZATION FAILED";channel.invokeMethod("engineError",mapOf("reason" to reason)) }
            }
        } else title.text="LACTEA / NATIVE LIBRARY MISSING"
    }
    private fun dp(v:Int)=(v*context.resources.displayMetrics.density).toInt()
    private fun loadPresets():List<LacteaPreset>{
        val list=runCatching{context.assets.list("lactea/curated").orEmpty().filter{it.endsWith(".milk",true)||it.endsWith(".milk2",true)}.sortedWith(compareBy<String>{if(it.endsWith(".milk2",true))0 else 1}.thenBy{it.lowercase()}).map{f->
            val stem=f.substringBeforeLast('.').lowercase().removePrefix("presets__").removePrefix("milk2__").removePrefix("milkdrop3__").removePrefix("milkdrop2__").replace('_','-')
            val label=when(stem){"aurora-cathedral"->"Aurora Cathedral";"tramonto-sul-golfo"->"Tramonto sul Golfo";"liquid-chrome-kaleidoscope"->"Liquid Chrome Kaleidoscope";"nebula-forge"->"Nebula Forge";"bioluminescent-abyss"->"Bioluminescent Abyss";"neon-sacred-geometry"->"Neon Sacred Geometry";"event-horizon"->"Event Horizon";"fractal-sanctum"->"Fractal Sanctum";"crystal-cathedral"->"Crystal Cathedral";"liquid-silk"->"Liquid Silk";"hyperspace"->"Hyperspace";"cymatic-prism"->"Cymatic Prism";else->stem.replace('-',' ').split(' ').joinToString(" "){it.replaceFirstChar{c->c.uppercase()}}}
            LacteaPreset(label,"lactea/curated/$f")
        }}.getOrDefault(emptyList())
        return list
    }
    private fun readPreset(p:LacteaPreset)=runCatching{context.assets.open(p.assetPath).use{it.readBytes()}}.getOrNull()
    private fun textureDirectory():String{
        val dir=File(context.cacheDir,"lactea_textures");val marker=File(context.cacheDir,".lactea_textures_version")
        val version=runCatching{context.assets.open("lactea/curated/UPSTREAM_COMMIT.txt").bufferedReader().use{it.readText().trim()}}.getOrDefault("missing-upstream-marker")
        if(!dir.exists()||runCatching{marker.readText().trim()}.getOrDefault("")!=version){dir.deleteRecursively();dir.mkdirs();copyAssets("lactea/textures",dir);marker.writeText(version)}
        return if(dir.listFiles().isNullOrEmpty())"" else dir.absolutePath
    }
    private fun copyAssets(path:String,target:File){val children=runCatching{context.assets.list(path).orEmpty()}.getOrDefault(emptyArray());if(children.isEmpty()){runCatching{target.parentFile?.mkdirs();context.assets.open(path).use{input->target.outputStream().use{input.copyTo(it)}}};return};target.mkdirs();children.forEach{copyAssets("$path/$it",File(target,it))}}
    private fun start(){if(disposed||!windowActive||task!=null||handle==0L)return;task=renderer.scheduleAtFixedRate({render()},0,framePeriodMs,TimeUnit.MILLISECONDS)}
    private fun stop(){task?.cancel(false);task=null}
    private fun render(){
        val h=handle;if(h==0L||disposed||!windowActive||!framePostPending.compareAndSet(false,true))return
        if(playing&&SystemClock.elapsedRealtime()-lastSwitch>=AUTO_MS)nextPreset()
        val ok=runCatching{LacteaNative.nativeRender(h,rgbaBuffer)}.getOrDefault(false)
        if(!ok){framePostPending.set(false);failures++;if(failures>=3){stop();main.post{if(!disposed)channel.invokeMethod("engineError",mapOf("reason" to "native render failed"))}};return}
        failures=0;var p=0
        for(i in pixelBuffer.indices){val r=rgbaBuffer[p++].toInt()and 255;val g=rgbaBuffer[p++].toInt()and 255;val b=rgbaBuffer[p++].toInt()and 255;p++;pixelBuffer[i]=(0xff shl 24)or(r shl 16)or(g shl 8)or b}
        main.post{try{if(!disposed){bitmap?.setPixels(pixelBuffer,0,W,0,0,W,H);image.invalidate()}}finally{framePostPending.set(false)}}
    }
    private fun nextPreset(){val h=handle;if(h==0L||disposed||switching||presets.size<2)return;switching=true;val next=(lastAttempted+1)%presets.size;lastAttempted=next;val preset=presets[next]
        renderer.execute{val bytes=readPreset(preset);val status=if(bytes==null)-1 else runCatching{LacteaNative.nativeLoadPreset(h,bytes,preset.title,2.4f)}.getOrDefault(-1);lastSwitch=SystemClock.elapsedRealtime();if(status==0&&!disposed){index=next;lastAttempted=next;main.post{if(!disposed)title.text="LACTEA / ${preset.title.uppercase()}"};if(!playing)render()};switching=false}
    }
    override fun onMethodCall(call:MethodCall,result:MethodChannel.Result){when(call.method){"isReady"->result.success(handle!=0L);"setPlaying"->{playing=call.argument<Boolean>("playing")==true;if(playing)start()else{stop();if(windowActive)renderer.execute{render()}};result.success(null)};"nextPreset"->{nextPreset();result.success(null)};else->result.notImplemented()}}
    override fun getView():View=root
    override fun dispose(){if(disposed)return;disposed=true;stop();channel.setMethodCallHandler(null);renderer.shutdownNow();val stopped=runCatching{renderer.awaitTermination(2,TimeUnit.SECONDS)}.getOrDefault(false);LacteaSessionRegistry.unregister(viewId);val h=handle;handle=0L;if(h!=0L&&stopped)runCatching{LacteaNative.nativeDestroy(h)}else if(h!=0L)Log.w(TAG,"Retaining native handle: renderer did not stop");bitmap?.recycle();bitmap=null}
}
