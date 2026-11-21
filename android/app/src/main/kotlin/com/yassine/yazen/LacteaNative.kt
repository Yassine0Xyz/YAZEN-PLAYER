package com.yassine.yazen

internal object LacteaNative {
    @Volatile var loadFailure: String? = null
        private set
    val available: Boolean by lazy {
        try { System.loadLibrary("yazen_lactea_jni"); true }
        catch (error: UnsatisfiedLinkError) { loadFailure = error.message ?: "UnsatisfiedLinkError"; false }
        catch (error: SecurityException) { loadFailure = error.message ?: "SecurityException"; false }
    }
    @JvmStatic external fun nativeCreate(width: Int, height: Int, preset: ByteArray, name: String, textureDirectory: String): Long
    @JvmStatic external fun nativeLoadPreset(handle: Long, preset: ByteArray, name: String, blendSeconds: Float): Int
    @JvmStatic external fun nativePushPcm(handle: Long, samples: FloatArray, channels: Int, sampleRate: Int)
    @JvmStatic external fun nativeResetAudio(handle: Long)
    @JvmStatic external fun nativeRender(handle: Long, output: ByteArray): Boolean
    @JvmStatic external fun nativeDestroy(handle: Long)
    @JvmStatic external fun nativeVersion(): Int
}
