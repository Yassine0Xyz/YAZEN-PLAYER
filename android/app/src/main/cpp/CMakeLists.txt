cmake_minimum_required(VERSION 3.22.1)
project(yazen_lactea_jni LANGUAGES CXX)
find_library(log-lib log)
find_library(android-lib android)

if (ANDROID_ABI STREQUAL "arm64-v8a")
    add_library(lactea_capi SHARED IMPORTED)
    set_target_properties(lactea_capi PROPERTIES
        IMPORTED_LOCATION "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}/liblactea_capi.so"
        IMPORTED_SONAME "liblactea_capi.so"
    )
    add_library(yazen_lactea_jni SHARED lactea_jni.cpp)
    target_include_directories(yazen_lactea_jni PRIVATE "${CMAKE_CURRENT_LIST_DIR}/include")
    target_compile_features(yazen_lactea_jni PRIVATE cxx_std_17)
    target_link_libraries(yazen_lactea_jni PRIVATE lactea_capi ${log-lib} ${android-lib})
else()
    # Some Flutter/AGP configurations still configure secondary ABIs even when
    # the app filters them out. Keep those configure steps harmless: the real
    # Lactea bridge and C API are arm64-only and are validated separately.
    add_library(yazen_lactea_jni SHARED lactea_jni_stub.cpp)
    target_link_libraries(yazen_lactea_jni PRIVATE ${log-lib} ${android-lib})
endif()
