/**********************************************************************************************
*
*   raylib_android_hosted.h - the host side of PLATFORM_ANDROID_HOSTED
*
*   PLATFORM_ANDROID_HOSTED renders into a surface an Android application owns (a SurfaceView's
*   Surface, as an ANativeWindow), instead of owning a NativeActivity like PLATFORM_ANDROID.
*   The application hands its surface and its input to raylib through these functions;
*   raylib keeps rendering on the thread that called InitWindow().
*
*   Threading:
*     - The host functions (RaylibHosted*) are safe to call from any thread (the UI thread,
*       typically), before or after InitWindow(). They only record what changed.
*     - The render thread applies it: every EndDrawing() (PollInputEvents()), and
*       RaylibHostedPump() for a render loop that is not drawing (paused, surface gone).
*     - The EGL context lives on the render thread for raylib's whole lifetime; a surface
*       going away (the app in the background) only drops its EGL window surface: textures,
*       shaders and buffers survive.
*
*   Before any surface is attached (or between a detach and the next attach), the context is
*   current on a 1x1 offscreen surface: GL calls work, nothing is shown.
*
*   Sizes are the surface's pixels: GetScreenWidth()/GetScreenHeight() follow the surface,
*   whatever InitWindow() asked for.
*
*   LICENSE: zlib/libpng, as raylib.
*
**********************************************************************************************/

#ifndef RAYLIB_ANDROID_HOSTED_H
#define RAYLIB_ANDROID_HOSTED_H

#include <stdbool.h>

#if defined(__cplusplus)
extern "C" {
#endif

// Surface lifecycle (host thread)
void RaylibHostedSetWindow(void *nativeWindow, int width, int height);  // An ANativeWindow*: raylib takes its own reference
void RaylibHostedClearWindow(void);                                     // The surface is going away: stop presenting to it
void RaylibHostedResize(int width, int height);                         // The surface changed size
bool RaylibHostedGetSurfaceSize(int *width, int *height);               // The host's surface size (false: never attached), before InitWindow() too
bool RaylibHostedIsReady(void);                                         // InitWindow() done (events have a window to reach)

// Window events (host thread)
void RaylibHostedPushFocus(bool gained);
void RaylibHostedPushClose(void);                                       // WindowShouldClose() becomes true
bool RaylibHostedMakeCurrent(bool current);                             // Render thread: the GL context current on the calling thread (true) or released from it (false)
void RaylibHostedClearClose(void);                                      // Render thread: WindowShouldClose() false again, queued closes dropped (the next window)
int RaylibHostedPopFocusChange(void);                                   // Render thread: the next focus change applied, in order: 1 gained, 0 lost, -1 none

// Input (host thread). Positions in surface pixels.
#define RAYLIB_HOSTED_TOUCH_DOWN 0
#define RAYLIB_HOSTED_TOUCH_MOVE 1
#define RAYLIB_HOSTED_TOUCH_UP   2
void RaylibHostedPushTouch(int phase, int pointerId, float x, float y);
void RaylibHostedPushKey(int androidKeyCode, bool down);                // An AKEYCODE_*: mapped like PLATFORM_ANDROID
void RaylibHostedPushText(unsigned int codepoint);                      // GetCharPressed()
void RaylibHostedPushGamepadButton(int deviceId, int androidKeyCode, bool pressed);
void RaylibHostedPushGamepadAxes(int deviceId, float x, float y, float z, float rz,
                                 float hatX, float hatY, float leftTrigger, float rightTrigger);
void RaylibHostedPushGamepadConnected(int deviceId, bool connected);    // Device ids get gamepad slots 0..MAX_GAMEPADS-1

// Render thread: apply what the host sent (surface switch, input). EndDrawing() does it too.
void RaylibHostedPump(void);

#if defined(__cplusplus)
}
#endif

#endif // RAYLIB_ANDROID_HOSTED_H
