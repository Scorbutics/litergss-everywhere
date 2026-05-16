/*
 * litergss_surface_jni.c
 *
 * JNI bridge for the LiteRGSS hosted-Activity flow on Android.
 *
 * Java/Kotlin side: a regular Activity owns a SurfaceView; its
 *   SurfaceHolder.Callback hands Surface objects across to native code.
 * Native side: this file converts each Surface to an ANativeWindow* and
 *   forwards lifecycle / input events into the LiteCGSS host-surface adapter
 *   (cgss_android_* C-linkage shims exported by libLiteCGSS_engine.a), which
 *   in turn drives the SFML hosted-mode API.
 *
 * Compilation/packaging: this file is compiled by the litergss-everywhere
 * orchestrator in cmake/litergss-app/dependencies/embedded-ruby-vm.cmake and
 * appended (ar r) to libembedded-ruby.a, the same way extension-init.c is —
 * giving it a guaranteed presence in the final fat librgss_runtime.a without
 * any modification to upstream embedded-ruby-vm sources.
 *
 * The cgss_android_* symbols are declared inline rather than #include'd from
 * <LiteCGSS/Platform/Android/HostSurface.h> because that header is staged
 * later in the dependency chain (litecgss runs after embedded-ruby-vm). The
 * declarations here must mirror the C-linkage block in HostSurface.h
 * exactly; link-time resolution checks the rest.
 *
 * Threading: attach/detach/resized are typically invoked from the Android UI
 * thread (SurfaceHolder.Callback). They only manipulate ActivityStates,
 * acquire/release the ANativeWindow, and call eglInitialize once — none of
 * which require a GL context. The actual EGL surface bind (and all
 * subsequent rendering) happens on the render thread when
 * LiteRGSS::DisplayWindow.new is invoked from Ruby. Per the project rule
 * "Ruby VM thread = draw thread", this single thread owns the EGL context
 * for its entire lifetime.
 *
 * Touch injection methods are safe to call from the UI thread too — SFML's
 * event queue is mutex-guarded.
 */

#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <jni.h>
#include <stddef.h>

/* Forward declarations of LiteCGSS's C-linkage hosted-surface API.
 * Definitions live in litergss2/external/litecgss/src/src/LiteCGSS/Platform/
 * Android/HostSurface.cpp. Keep these in sync with the extern "C" block in
 * LiteCGSS/Platform/Android/HostSurface.h. */
void cgss_android_attach_host_surface(void* nativeWindow, int width, int height);
void cgss_android_detach_host_surface(void);
void cgss_android_notify_host_surface_resized(int width, int height);
void cgss_android_inject_touch_down(int pointerId, float x, float y);
void cgss_android_inject_touch_move(int pointerId, float x, float y);
void cgss_android_inject_touch_up(int pointerId, float x, float y);

/* Single live ANativeWindow*, mirroring the singleton model on the LiteCGSS
 * side. The reference is acquired by ANativeWindow_fromSurface (which
 * increments the refcount) and released here on detach / re-attach. */
static ANativeWindow* g_window = NULL;


JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_attach(JNIEnv* env, jclass clazz,
                                                  jobject surface,
                                                  jint width, jint height)
{
    (void) clazz;

    if (surface == NULL)
        return;

    ANativeWindow* nextWindow = ANativeWindow_fromSurface(env, surface);
    if (nextWindow == NULL)
        return;

    /* If a previous Surface is still held (e.g. orientation change without a
     * detach), release it before swapping in the new one. The hosted-mode
     * adapter on the C++ side updates states.window when called twice in a
     * row, so the order (release-then-attach) is safe. */
    if (g_window != NULL)
    {
        ANativeWindow_release(g_window);
        g_window = NULL;
    }

    g_window = nextWindow;
    cgss_android_attach_host_surface(g_window, (int) width, (int) height);
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_resized(JNIEnv* env, jclass clazz,
                                                   jint width, jint height)
{
    (void) env;
    (void) clazz;
    cgss_android_notify_host_surface_resized((int) width, (int) height);
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_detach(JNIEnv* env, jclass clazz)
{
    (void) env;
    (void) clazz;

    cgss_android_detach_host_surface();

    if (g_window != NULL)
    {
        ANativeWindow_release(g_window);
        g_window = NULL;
    }
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_injectTouchDown(JNIEnv* env, jclass clazz,
                                                           jint pointerId,
                                                           jfloat x, jfloat y)
{
    (void) env;
    (void) clazz;
    cgss_android_inject_touch_down((int) pointerId, (float) x, (float) y);
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_injectTouchMove(JNIEnv* env, jclass clazz,
                                                           jint pointerId,
                                                           jfloat x, jfloat y)
{
    (void) env;
    (void) clazz;
    cgss_android_inject_touch_move((int) pointerId, (float) x, (float) y);
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_injectTouchUp(JNIEnv* env, jclass clazz,
                                                         jint pointerId,
                                                         jfloat x, jfloat y)
{
    (void) env;
    (void) clazz;
    cgss_android_inject_touch_up((int) pointerId, (float) x, (float) y);
}
