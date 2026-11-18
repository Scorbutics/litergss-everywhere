/*
 * litergss_surface_jni.c
 *
 * The runtime's side of the LiteRGSS hosted-Activity flow on Android.
 *
 * The JNI bridge itself (Surface lifecycle, touch / key / gamepad events, the
 * IME request back to the host) is LiteCGSS's (Platform/Android/
 * HostSurfaceJni.cpp, in libLiteCGSS_engine.a). What stays here is what only
 * the runtime knows:
 *   - its Kotlin class, com.scorbutics.litergss.NativeSurface (kotlin/), on
 *     which the bridge registers its natives when the runtime is loaded;
 *   - its audio: SFML's (ruby-sfml-audio), paused while the game has no
 *     surface (the app in the background), whatever its scripts do.
 *
 * Compilation/packaging: compiled by embedded-ruby-vm.cmake and appended
 * (ar r) to libembedded-ruby.a, as extension-init.c is. LiteCGSS's headers are
 * staged after it, hence the declarations below (LiteCGSS/Platform/Android/
 * HostSurface.h); the link checks them.
 */

#include <jni.h>
#include <stddef.h>

typedef void (*cgss_android_host_surface_listener_t)(int attached);
void cgss_android_set_host_surface_listener(cgss_android_host_surface_listener_t listener);
int cgss_android_register_natives(JNIEnv* env, jclass hostClass);

/* SFML (Audio/Android/HostedAudio.hpp): a device pause, not a mute: music
 * goes on where it was, and SFML's streaming threads wait meanwhile. */
void sf_android_set_hosted_audio_paused(int paused);

static void on_host_surface(int attached)
{
    sf_android_set_hosted_audio_paused(attached ? 0 : 1);
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved)
{
    (void) reserved;

    JNIEnv* env = NULL;
    if ((*vm)->GetEnv(vm, (void**) &env, JNI_VERSION_1_6) != JNI_OK || env == NULL)
        return JNI_VERSION_1_6;

    /* NativeSurface (litergss-host) may not be in the app: a host running
     * scripts without a hosted window loads this library too. Found with the
     * class loader of whoever loads the library (System.loadLibrary). */
    jclass nativeSurface = (*env)->FindClass(env, "com/scorbutics/litergss/NativeSurface");
    if (nativeSurface == NULL)
    {
        (*env)->ExceptionClear(env);
        return JNI_VERSION_1_6;
    }

    if (cgss_android_register_natives(env, nativeSurface) != JNI_OK)
    {
        /* Logged (logcat); its natives then throw UnsatisfiedLinkError */
        if ((*env)->ExceptionCheck(env))
        {
            (*env)->ExceptionDescribe(env);
            (*env)->ExceptionClear(env);
        }
    }
    else
    {
        cgss_android_set_host_surface_listener(on_host_surface);
    }
    (*env)->DeleteLocalRef(env, nativeSurface);
    return JNI_VERSION_1_6;
}
