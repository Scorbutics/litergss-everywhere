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
void cgss_android_request_host_surface_close(void);

void cgss_android_inject_key_down(int androidKeyCode, int metaState, int repeatCount);
void cgss_android_inject_key_up(int androidKeyCode, int metaState);
void cgss_android_inject_text(unsigned int unicodeCodepoint);
void cgss_android_inject_focus_gained(void);
void cgss_android_inject_focus_lost(void);
void cgss_android_inject_joystick_button(int deviceId, int androidKeyCode, int pressed);
void cgss_android_inject_joystick_axis(int   deviceId,
                                       float axisX,    float axisY,
                                       float axisZ,    float axisRz,
                                       float hatX,     float hatY,
                                       float lTrigger, float rTrigger);
void cgss_android_inject_joystick_connected(int deviceId);
void cgss_android_inject_joystick_disconnected(int deviceId);

typedef void (*cgss_android_virtual_keyboard_callback_t)(int show);
void cgss_android_set_virtual_keyboard_callback(cgss_android_virtual_keyboard_callback_t cb);
void cgss_android_request_virtual_keyboard(int show);

void cgss_android_set_host_jni_context(JavaVM* vm, jobject activity);

void cgss_android_set_reuse_shared_window(int enabled);
int cgss_android_is_reuse_shared_window_enabled(void);

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

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_requestClose(JNIEnv* env, jclass clazz)
{
    (void) env;
    (void) clazz;
    cgss_android_request_host_surface_close();
}

/* ------------------------------------------------------------------
 * Hosted input injection: hardware keys, text, focus, gamepad. All
 * thin pass-throughs to cgss_android_inject_*; translation from
 * Android keycodes to sf::Keyboard / SFML joystick indices happens on
 * the SFML side (HostedAndroidWindow.cpp).
 * ------------------------------------------------------------------ */

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_injectKeyDown(JNIEnv* env, jclass clazz,
                                                          jint androidKeyCode,
                                                          jint metaState,
                                                          jint repeatCount)
{
    (void) env;
    (void) clazz;
    cgss_android_inject_key_down((int) androidKeyCode,
                                 (int) metaState,
                                 (int) repeatCount);
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_injectKeyUp(JNIEnv* env, jclass clazz,
                                                        jint androidKeyCode,
                                                        jint metaState)
{
    (void) env;
    (void) clazz;
    cgss_android_inject_key_up((int) androidKeyCode, (int) metaState);
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_injectText(JNIEnv* env, jclass clazz,
                                                       jint unicodeCodepoint)
{
    (void) env;
    (void) clazz;
    cgss_android_inject_text((unsigned int) unicodeCodepoint);
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_injectFocusGained(JNIEnv* env, jclass clazz)
{
    (void) env;
    (void) clazz;
    cgss_android_inject_focus_gained();
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_injectFocusLost(JNIEnv* env, jclass clazz)
{
    (void) env;
    (void) clazz;
    cgss_android_inject_focus_lost();
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_injectJoystickButton(JNIEnv* env, jclass clazz,
                                                                 jint deviceId,
                                                                 jint androidKeyCode,
                                                                 jboolean pressed)
{
    (void) env;
    (void) clazz;
    cgss_android_inject_joystick_button((int) deviceId,
                                        (int) androidKeyCode,
                                        pressed == JNI_TRUE ? 1 : 0);
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_injectJoystickAxis(JNIEnv* env, jclass clazz,
                                                               jint deviceId,
                                                               jfloat axisX,    jfloat axisY,
                                                               jfloat axisZ,    jfloat axisRz,
                                                               jfloat hatX,     jfloat hatY,
                                                               jfloat lTrigger, jfloat rTrigger)
{
    (void) env;
    (void) clazz;
    cgss_android_inject_joystick_axis((int) deviceId,
                                      (float) axisX,    (float) axisY,
                                      (float) axisZ,    (float) axisRz,
                                      (float) hatX,     (float) hatY,
                                      (float) lTrigger, (float) rTrigger);
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_injectJoystickConnected(JNIEnv* env, jclass clazz,
                                                                    jint deviceId)
{
    (void) env;
    (void) clazz;
    cgss_android_inject_joystick_connected((int) deviceId);
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_injectJoystickDisconnected(JNIEnv* env, jclass clazz,
                                                                       jint deviceId)
{
    (void) env;
    (void) clazz;
    cgss_android_inject_joystick_disconnected((int) deviceId);
}

/* ------------------------------------------------------------------
 * IME bridge: native -> Java callback. Ruby (via cgss::android::
 * requestVirtualKeyboard) calls into our static `g_virtualKeyboardThunk`,
 * which uses the cached JavaVM to attach the current thread and invoke
 * NativeSurface.dispatchVirtualKeyboardRequest(Boolean) on the Kotlin
 * side. The Kotlin side fans out to the registered VirtualKeyboardListener.
 *
 * Threading: invoked from whichever thread calls requestVirtualKeyboard
 * (typically the Ruby render thread). Listeners on the Java side that
 * touch View state are responsible for hopping to the UI thread.
 * ------------------------------------------------------------------ */

static JavaVM*   g_jvm                       = NULL;
static jclass    g_nativeSurfaceClass        = NULL;  /* global ref */
static jmethodID g_dispatchVirtualKeyboardMid = NULL;

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved)
{
    (void) reserved;
    g_jvm = vm;

    JNIEnv* env = NULL;
    if ((*vm)->GetEnv(vm, (void**) &env, JNI_VERSION_1_6) != JNI_OK || env == NULL) {
        /* Should never happen — caller is Android's ART. Without the JVM
         * pointer the IME callback can't function; return JNI_ERR so
         * System.loadLibrary fails loudly rather than silently leaving
         * the IME bridge dead. */
        return JNI_ERR;
    }

    /* Resolve and pin a global ref to NativeSurface so it survives across
     * JNIEnv detaches. FindClass returns a local ref; NewGlobalRef
     * promotes it. */
    jclass local = (*env)->FindClass(env, "com/scorbutics/litergss/NativeSurface");
    if (local == NULL) return JNI_ERR;
    g_nativeSurfaceClass = (jclass) (*env)->NewGlobalRef(env, local);
    (*env)->DeleteLocalRef(env, local);
    if (g_nativeSurfaceClass == NULL) return JNI_ERR;

    /* Resolve the static dispatch method. Method IDs are valid for the
     * class's lifetime; the global ref above keeps the class alive. */
    g_dispatchVirtualKeyboardMid = (*env)->GetStaticMethodID(
        env, g_nativeSurfaceClass, "dispatchVirtualKeyboardRequest", "(Z)V");
    if (g_dispatchVirtualKeyboardMid == NULL) return JNI_ERR;

    return JNI_VERSION_1_6;
}

static void virtual_keyboard_thunk(int show)
{
    if (g_jvm == NULL || g_nativeSurfaceClass == NULL || g_dispatchVirtualKeyboardMid == NULL) {
        return;
    }

    JNIEnv* env = NULL;
    int     attached = 0;
    jint    rc = (*g_jvm)->GetEnv(g_jvm, (void**) &env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if ((*g_jvm)->AttachCurrentThread(g_jvm, &env, NULL) != JNI_OK) {
            return;
        }
        attached = 1;
    } else if (rc != JNI_OK || env == NULL) {
        return;
    }

    (*env)->CallStaticVoidMethod(env, g_nativeSurfaceClass,
                                 g_dispatchVirtualKeyboardMid,
                                 show ? JNI_TRUE : JNI_FALSE);

    /* Swallow any pending exception so it doesn't cascade across the
     * JNI boundary into native code that can't handle it. Listener
     * exceptions are programmer errors; just log and continue. */
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
    }

    if (attached) {
        (*g_jvm)->DetachCurrentThread(g_jvm);
    }
}

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_nativeSetVirtualKeyboardCallback(JNIEnv* env, jclass clazz,
                                                                             jboolean armed)
{
    (void) env;
    (void) clazz;
    cgss_android_set_virtual_keyboard_callback(armed == JNI_TRUE ? virtual_keyboard_thunk : NULL);
}

/* ------------------------------------------------------------------
 * Host Activity registration. SFML's hosted-mode JNI fallbacks (the
 * virtual-keyboard path in particular) need both a JavaVM* (already
 * cached as g_jvm above) and an Activity jobject — neither is
 * available via SurfaceHolder.Callback. The host Activity registers
 * itself once in onCreate and clears in onDestroy. Cached on the
 * LiteCGSS side; reapplied across attach/detach surface cycles.
 * ------------------------------------------------------------------ */

JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_nativeSetHostActivity(JNIEnv* env, jclass clazz,
                                                                  jobject activity)
{
    (void) env;
    (void) clazz;
    /* g_jvm is set in JNI_OnLoad; activity may be NULL to clear. */
    cgss_android_set_host_jni_context(g_jvm, activity);
}

/* ------------------------------------------------------------------
 * Shared-RenderWindow opt-in. Set by the host activity (GameActivity)
 * before its PsdkInterpreter starts so cgss::DisplayWindow's ctor
 * picks sharedGameWindow() over the per-instance owned variant. See
 * cgss::android::setReuseSharedWindow's KDoc for the lifecycle caveats.
 * ------------------------------------------------------------------ */
JNIEXPORT void JNICALL
Java_com_scorbutics_litergss_NativeSurface_setReuseSharedWindow(JNIEnv* env, jclass clazz,
                                                                 jboolean enabled)
{
    (void) env;
    (void) clazz;
    cgss_android_set_reuse_shared_window(enabled == JNI_TRUE ? 1 : 0);
}

JNIEXPORT jboolean JNICALL
Java_com_scorbutics_litergss_NativeSurface_isReuseSharedWindowEnabled(JNIEnv* env, jclass clazz)
{
    (void) env;
    (void) clazz;
    return cgss_android_is_reuse_shared_window_enabled() ? JNI_TRUE : JNI_FALSE;
}
