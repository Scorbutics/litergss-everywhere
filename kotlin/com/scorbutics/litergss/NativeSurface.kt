package com.scorbutics.litergss

import android.view.Surface

/**
 * Kotlin entry point for the LiteRGSS hosted-Activity flow on Android.
 *
 * Pair this with a [android.view.SurfaceView] (or TextureView): on
 * [android.view.SurfaceHolder.Callback.surfaceCreated] call [attach] with the
 * holder's Surface and current width/height, then forward
 * [android.view.SurfaceHolder.Callback.surfaceChanged] to [resized] and
 * [android.view.SurfaceHolder.Callback.surfaceDestroyed] to [detach]. Touch
 * events captured by the host View's [android.view.View.OnTouchListener]
 * should be split into per-pointer down/move/up calls and routed to
 * [injectTouchDown] / [injectTouchMove] / [injectTouchUp].
 *
 * Threading: [attach], [detach] and [resized] are typically invoked from the
 * Android UI thread (SurfaceHolder.Callback). They only manipulate global
 * state and acquire/release the ANativeWindow — none of them touch GL. The
 * actual EGL surface bind happens lazily on the render thread when
 * `LiteRGSS::DisplayWindow.new` runs from Ruby, per the project rule
 * "Ruby VM thread = draw thread".
 *
 * The library that exports these symbols is `librgss_runtime.so`, the same
 * .so produced by `litergss-everywhere/external/embedded-ruby-vm/kmp-publish/
 * wrapper/CMakeLists.txt`. Callers that already configured
 * `LibraryConfig.libraryName = "rgss_runtime"` and triggered any
 * Ruby-VM-related load path will have the lib loaded already; this object
 * adds a defensive [System.loadLibrary] for hosts that only do graphics.
 */
object NativeSurface {

    init {
        // Idempotent — if the JVM already loaded "rgss_runtime" (e.g. via
        // the embedded-ruby-vm KMP module's NativeLibraryLoader), this is
        // a no-op. Otherwise it loads it now.
        try {
            System.loadLibrary("rgss_runtime")
        } catch (_: UnsatisfiedLinkError) {
            // Caller is expected to load the lib by some other means
            // (e.g. through the embedded-ruby-vm KMP loader). Fall through.
        }
    }

    /**
     * Attach a [Surface] to LiteRGSS. The native side acquires a reference to
     * the underlying ANativeWindow that is released by [detach] (or by a
     * subsequent [attach] if it gets called twice without an intervening
     * [detach], e.g. on configuration changes).
     */
    @JvmStatic external fun attach(surface: Surface, width: Int, height: Int)

    /** Notify LiteRGSS the hosted surface has been resized. */
    @JvmStatic external fun resized(width: Int, height: Int)

    /** Release the hosted surface. Call before the SurfaceView is destroyed. */
    @JvmStatic external fun detach()

    /** Forward an Android pointer-down event into SFML's queue. */
    @JvmStatic external fun injectTouchDown(pointerId: Int, x: Float, y: Float)

    /** Forward an Android pointer-move event into SFML's queue. */
    @JvmStatic external fun injectTouchMove(pointerId: Int, x: Float, y: Float)

    /** Forward an Android pointer-up event into SFML's queue. */
    @JvmStatic external fun injectTouchUp(pointerId: Int, x: Float, y: Float)
}
