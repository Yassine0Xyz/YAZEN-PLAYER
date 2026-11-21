#include <jni.h>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>
#include "lactea.h"
namespace {
constexpr uint32_t kRate=44100;
struct Handle { LacteaEngine* engine=nullptr; uint32_t frame=0; std::chrono::steady_clock::time_point start=std::chrono::steady_clock::now(); std::vector<uint8_t> rgba; std::mutex mutex; };
std::string ToString(JNIEnv* e,jstring v){ if(!v)return {}; const char* p=e->GetStringUTFChars(v,nullptr); if(!p)return {}; std::string s(p); e->ReleaseStringUTFChars(v,p); return s; }
std::string LastError(){ const char* p=lactea_last_error(); return p?std::string(p):std::string("unknown Lactea error"); }
void Throw(JNIEnv* e,const std::string& s){ jclass c=e->FindClass("java/lang/IllegalStateException"); if(c)e->ThrowNew(c,s.c_str()); }
Handle* Get(jlong h){ return h?reinterpret_cast<Handle*>(h):nullptr; }
std::vector<float> Resample(const std::vector<float>& in,uint32_t channels,uint32_t rate,uint32_t* frames){
 *frames=0; if(!channels||!rate||in.size()<channels)return {}; size_t n=in.size()/channels; if(!n)return {};
 uint32_t used=std::min(channels,2u); size_t outN=static_cast<size_t>((static_cast<uint64_t>(n)*kRate)/rate); std::vector<float> out; out.reserve(outN*2);
 for(size_t i=0;i<outN;i++){ double src=static_cast<double>(i)*rate/kRate; size_t a=std::min(static_cast<size_t>(src),n-1),b=std::min(a+1,n-1); float t=static_cast<float>(src-a);
  float l0=std::clamp(in[a*channels],-1.f,1.f),l1=std::clamp(in[b*channels],-1.f,1.f);
  float r0=used>1?std::clamp(in[a*channels+1],-1.f,1.f):l0,r1=used>1?std::clamp(in[b*channels+1],-1.f,1.f):l1;
  out.push_back(l0+(l1-l0)*t); out.push_back(r0+(r1-r0)*t);
 }
 *frames=static_cast<uint32_t>(out.size()/2); return out;
}
}
extern "C" JNIEXPORT jlong JNICALL Java_com_yassine_yazen_LacteaNative_nativeCreate(JNIEnv* env,jclass,jint width,jint height,jbyteArray bytes,jstring name,jstring textureDir){
 if(!bytes){Throw(env,"Missing initial MilkDrop preset");return 0;} jsize len=env->GetArrayLength(bytes); std::vector<uint8_t> preset(static_cast<size_t>(len)); env->GetByteArrayRegion(bytes,0,len,reinterpret_cast<jbyte*>(preset.data())); if(env->ExceptionCheck())return 0;
 auto h=std::make_unique<Handle>(); h->rgba.resize(static_cast<size_t>(std::clamp(width,320,1440))*static_cast<size_t>(std::clamp(height,90,720))*4);
 LacteaConfig cfg; lactea_config_default(&cfg); cfg.width=static_cast<uint32_t>(std::clamp(width,320,1440)); cfg.height=static_cast<uint32_t>(std::clamp(height,90,720)); cfg.compat=LACTEA_COMPAT_AUTO;
 h->engine=lactea_create(&cfg); if(!h->engine){Throw(env,"Lactea GPU initialization failed: "+LastError());return 0;}
 std::string dir=ToString(env,textureDir); if(!dir.empty() && lactea_set_texture_dir(h->engine,dir.c_str())<0){std::string e="Lactea texture loading failed: "+LastError();lactea_destroy(h->engine);Throw(env,e);return 0;}
 std::string presetName=ToString(env,name); if(lactea_load_preset(h->engine,preset.data(),preset.size(),presetName.c_str())<0){std::string e="Initial preset failed: "+LastError();lactea_destroy(h->engine);Throw(env,e);return 0;}
 return reinterpret_cast<jlong>(h.release());
}
extern "C" JNIEXPORT jint JNICALL Java_com_yassine_yazen_LacteaNative_nativeLoadPreset(JNIEnv* env,jclass,jlong value,jbyteArray bytes,jstring name,jfloat blend){
 Handle* h=Get(value);if(!h||!bytes)return -1;jsize len=env->GetArrayLength(bytes);std::vector<uint8_t> p(static_cast<size_t>(len));env->GetByteArrayRegion(bytes,0,len,reinterpret_cast<jbyte*>(p.data()));if(env->ExceptionCheck())return -2;
 std::string n=ToString(env,name);std::lock_guard<std::mutex> g(h->mutex);LacteaStatus st=lactea_load_preset_ex(h->engine,p.data(),p.size(),n.c_str(),std::max(0.0,static_cast<double>(blend)));return st<0?static_cast<jint>(st):0;
}
extern "C" JNIEXPORT void JNICALL Java_com_yassine_yazen_LacteaNative_nativePushPcm(JNIEnv* env,jclass,jlong value,jfloatArray samples,jint channels,jint rate){
 Handle* h=Get(value);if(!h||!samples||channels<=0||rate<=0)return;jsize len=env->GetArrayLength(samples);if(len<=0)return;std::vector<float> in(static_cast<size_t>(len));env->GetFloatArrayRegion(samples,0,len,in.data());if(env->ExceptionCheck())return;uint32_t frames=0;auto stereo=Resample(in,static_cast<uint32_t>(channels),static_cast<uint32_t>(rate),&frames);if(!frames||stereo.empty())return;std::lock_guard<std::mutex> g(h->mutex);lactea_push_pcm_f32(h->engine,stereo.data(),frames,2);
}
extern "C" JNIEXPORT void JNICALL Java_com_yassine_yazen_LacteaNative_nativeResetAudio(JNIEnv*,jclass,jlong value){Handle* h=Get(value);if(!h)return;std::vector<float> silence(2048,0.f);std::lock_guard<std::mutex> g(h->mutex);lactea_push_pcm_f32(h->engine,silence.data(),1024,2);}
extern "C" JNIEXPORT jboolean JNICALL Java_com_yassine_yazen_LacteaNative_nativeRender(JNIEnv* env,jclass,jlong value,jbyteArray output){
 Handle* h=Get(value);if(!h||!output||env->GetArrayLength(output)!=static_cast<jsize>(h->rgba.size()))return JNI_FALSE;
 std::lock_guard<std::mutex> g(h->mutex);double t=std::chrono::duration<double>(std::chrono::steady_clock::now()-h->start).count();
 if(lactea_render_to_buffer(h->engine,t,h->frame++,h->rgba.data(),h->rgba.size())<0)return JNI_FALSE;
 env->SetByteArrayRegion(output,0,static_cast<jsize>(h->rgba.size()),reinterpret_cast<const jbyte*>(h->rgba.data()));return env->ExceptionCheck()?JNI_FALSE:JNI_TRUE;
}
extern "C" JNIEXPORT void JNICALL Java_com_yassine_yazen_LacteaNative_nativeDestroy(JNIEnv*,jclass,jlong value){Handle* h=Get(value);if(!h)return;{std::lock_guard<std::mutex> g(h->mutex);if(h->engine){lactea_destroy(h->engine);h->engine=nullptr;}}delete h;}
extern "C" JNIEXPORT jint JNICALL Java_com_yassine_yazen_LacteaNative_nativeVersion(JNIEnv*,jclass){return 202;}
