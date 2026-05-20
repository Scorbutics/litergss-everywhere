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

    /**
     * Forward a hardware key-down event.
     *
     * `androidKeyCode` is the raw [android.view.KeyEvent.keyCode], not a
     * pre-translated SFML key — the native side reuses SFML's existing
     * Android-to-SFML keycode table. `metaState` is
     * [android.view.KeyEvent.metaState]. `repeatCount > 0` (OS auto-
     * repeat) is silently dropped on the native side; consumers like PSDK
     * run their own software repeat handler.
     */
    @JvmStatic external fun injectKeyDown(androidKeyCode: Int, metaState: Int, repeatCount: Int)

    /** Forward a hardware key-up event. See [injectKeyDown] for argument semantics. */
    @JvmStatic external fun injectKeyUp(androidKeyCode: Int, metaState: Int)

    /**
     * Forward a single Unicode codepoint as `sf::Event::TextEntered`.
     *
     * Use for both hardware-key text (host should call
     * `KeyEvent.getUnicodeChar(metaState)` and forward the result) and
     * soft-keyboard input (TextWatcher on a hidden EditText). Codepoint 0
     * is a no-op on the native side.
     */
    @JvmStatic external fun injectText(unicodeCodepoint: Int)

    /** Forward a `sf::Event::GainedFocus`. Required after resume — without it, PSDK's `Graphics.focus?` stays false and every `Input.*?` query returns false. */
    @JvmStatic external fun injectFocusGained()

    /** Forward a `sf::Event::LostFocus`. */
    @JvmStatic external fun injectFocusLost()

    /**
     * Forward a gamepad button press/release.
     *
     * `androidKeyCode` must be one of the AKEYCODE_BUTTON_* / AKEYCODE_DPAD_*
     * values that SFML's `androidJoystickKeyToIndex` recognises. Other
     * keycodes are silently dropped.
     */
    @JvmStatic external fun injectJoystickButton(deviceId: Int, androidKeyCode: Int, pressed: Boolean)

    /**
     * Forward gamepad analog-axis state.
     *
     * Values are in Android's native [-1, 1] range; SFML scales them to
     * [-100, 100] internally. Send all axes in one call — the SFML model
     * tracks per-axis state and replaces it wholesale on each event.
     */
    @JvmStatic external fun injectJoystickAxis(
        deviceId: Int,
        axisX: Float, axisY: Float,
        axisZ: Float, axisRz: Float,
        hatX: Float,  hatY: Float,
        lTrigger: Float, rTrigger: Float,
    )

    /** Forward a gamepad-connected event. */
    @JvmStatic external fun injectJoystickConnected(deviceId: Int)

    /** Forward a gamepad-disconnected event. */
    @JvmStatic external fun injectJoystickDisconnected(deviceId: Int)

    /**
     * Listener invoked when native code requests the soft keyboard be
     * shown or hidden. The host Activity registers one via
     * [setVirtualKeyboardListener]; native code calls in via
     * cgss::android::requestVirtualKeyboard (typically through a Ruby
     * binding that opens / closes the IME).
     *
     * Threading: callback fires on whichever thread requested the
     * keyboard (Ruby render thread in practice). Listeners that touch
     * Android View state MUST hop to the UI thread themselves.
     */
    fun interface VirtualKeyboardListener {
        fun onVirtualKeyboardRequested(show: Boolean)
    }

    @Volatile
    private var virtualKeyboardListener: VirtualKeyboardListener? = null

    /**
     * Register (or clear, with null) the soft-keyboard request listener.
     * Setting a listener arms the native callback; setting null disarms.
     */
    @JvmStatic
    fun setVirtualKeyboardListener(listener: VirtualKeyboardListener?) {
        virtualKeyboardListener = listener
        nativeSetVirtualKeyboardCallback(listener != null)
    }

    /** JNI entry. Called by litergss_surface_jni.c via the registered callback. */
    @JvmStatic
    @Suppress("unused")
    private fun dispatchVirtualKeyboardRequest(show: Boolean) {
        virtualKeyboardListener?.onVirtualKeyboardRequested(show)
    }

    @JvmStatic private external fun nativeSetVirtualKeyboardCallback(armed: Boolean)
}
