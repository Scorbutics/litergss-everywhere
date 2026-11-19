/**********************************************************************************************
*
*   rcore_android_hosted - Functions to manage window, graphics device and inputs
*
*   PLATFORM: ANDROID_HOSTED
*       - Android (ARM, ARM64, x86_64), rendering into a surface the application owns
*
*   An Android application keeps its own Activity and SurfaceView, and hands their Surface
*   (an ANativeWindow) and their input to raylib through raylib_android_hosted.h. Unlike
*   PLATFORM_ANDROID, raylib does not own a NativeActivity, has no android_main() and no
*   asset-manager fopen() redirection: files are read from the file system.
*
*   The render thread is the one calling InitWindow(): it owns the EGL context for raylib's
*   lifetime. The host's calls (any thread) are recorded under a lock and applied by the
*   render thread at its next PollInputEvents() (EndDrawing()) or RaylibHostedPump().
*
*   DEPENDENCIES:
*       - Android NDK: android, log, EGL, GLESv2 / GLESv3
*       - gestures: Gestures system for touch-ready devices
*
*   LICENSE: zlib/libpng
*
*   Based on rcore_android.c and rcore_template.c,
*   Copyright (c) 2013-2026 Ramon Santamaria (@raysan5) and contributors
*
*   This software is provided "as-is", without any express or implied warranty. In no event
*   will the authors be held liable for any damages arising from the use of this software.
*
*   Permission is granted to anyone to use this software for any purpose, including commercial
*   applications, and to alter it and redistribute it freely, subject to the following restrictions:
*
*     1. The origin of this software must not be misrepresented; you must not claim that you
*     wrote the original software. If you use this software in a product, an acknowledgment
*     in the product documentation would be appreciated but is not required.
*
*     2. Altered source versions must be plainly marked as such, and must not be misrepresented
*     as being the original software.
*
*     3. This notice may not be removed or altered from any source distribution.
*
**********************************************************************************************/

#include <android/keycodes.h>           // Required for: AKEYCODE_*
#include <android/log.h>                // Required for: __android_log_vprint() (raylib's TraceLog)
#include <android/native_window.h>      // Required for: ANativeWindow_*
#include <EGL/egl.h>                    // Native platform windowing system interface
#include <pthread.h>                    // Required for: pthread_mutex_*
#include <time.h>                       // Required for: clock_gettime()

#include "raylib_android_hosted.h"

//----------------------------------------------------------------------------------
// Types and Structures Definition
//----------------------------------------------------------------------------------
typedef struct {
    EGLDisplay device;                  // Native display device
    EGLConfig config;                   // Graphic config
    EGLContext context;                 // Graphic context: lives as long as raylib
    EGLSurface pbuffer;                 // 1x1 offscreen surface: current while no window is attached
    EGLSurface surface;                 // Window surface of the attached window (EGL_NO_SURFACE if none)
    ANativeWindow *window;              // The attached window (raylib's own reference), render thread only
} PlatformData;

typedef enum {
    HOSTED_FOCUS = 0,
    HOSTED_CLOSE,
    HOSTED_TOUCH,
    HOSTED_KEY,
    HOSTED_TEXT,
    HOSTED_GAMEPAD_BUTTON,
    HOSTED_GAMEPAD_AXES,
    HOSTED_GAMEPAD_CONNECTED
} HostedEventType;

typedef struct {
    HostedEventType type;
    int a, b, c;                        // focus: gained | touch: phase, id | key: code, down | gamepad: device, code, pressed/connected
    unsigned int codepoint;             // text
    float f[8];                         // touch: x, y | gamepad axes
} HostedEvent;

#define HOSTED_EVENT_QUEUE_SIZE 512

typedef struct {
    pthread_mutex_t lock;
    // Surface handed by the host, applied by the render thread
    bool windowChanged;
    ANativeWindow *window;              // Pending window (raylib's own reference), or NULL
    bool resized;
    int width, height;                  // Surface size the host reported
    // Events, oldest first
    HostedEvent events[HOSTED_EVENT_QUEUE_SIZE];
    int head, count;
    bool overflowWarned;
} HostedShared;

typedef struct {
    int deviceId[MAX_GAMEPADS];         // Android device id of each gamepad slot (-1: free)
    int pointId[MAX_TOUCH_POINTS];      // Active touch points, in pressing order
    Vector2 position[MAX_TOUCH_POINTS];
    int pointCount;
    // Pressed since the last PollInputEvents() (the frame): raylib keeps
    // input as state, read once a frame, so a release of one of these waits
    // for the next frame, or a press and its release would cancel out
    // (a quick tap seen by nobody). See HostedTakeEvents().
    struct { HostedEventType type; int id, code; double time; } recentPress[64];
    int recentPressCount;
} HostedInput;

// The longest a release waits for its press' frame: past it (no frame is
// being drawn), it goes through rather than leave the button held
#define HOSTED_RELEASE_HOLD_SECONDS 0.1

//----------------------------------------------------------------------------------
// Global Variables Definition
//----------------------------------------------------------------------------------
extern CoreData CORE;                   // Global CORE state context

static PlatformData platform = { 0 };   // Platform specific data
static HostedShared shared = { .lock = PTHREAD_MUTEX_INITIALIZER };
static HostedInput hostedInput = { 0 };
static bool platformReady = false;      // InitPlatform() done (read by the host thread)

//----------------------------------------------------------------------------------
// Local Variables Definition
//----------------------------------------------------------------------------------
// Android key codes to raylib keys: as PLATFORM_ANDROID (rcore_android.c)
#define KEYCODE_MAP_SIZE 162
static const KeyboardKey mapKeycode[KEYCODE_MAP_SIZE] = {
    KEY_NULL,           // AKEYCODE_UNKNOWN
    0,                  // AKEYCODE_SOFT_LEFT
    0,                  // AKEYCODE_SOFT_RIGHT
    0,                  // AKEYCODE_HOME
    KEY_BACK,           // AKEYCODE_BACK
    0,                  // AKEYCODE_CALL
    0,                  // AKEYCODE_ENDCALL
    KEY_ZERO,           // AKEYCODE_0
    KEY_ONE,            // AKEYCODE_1
    KEY_TWO,            // AKEYCODE_2
    KEY_THREE,          // AKEYCODE_3
    KEY_FOUR,           // AKEYCODE_4
    KEY_FIVE,           // AKEYCODE_5
    KEY_SIX,            // AKEYCODE_6
    KEY_SEVEN,          // AKEYCODE_7
    KEY_EIGHT,          // AKEYCODE_8
    KEY_NINE,           // AKEYCODE_9
    0,                  // AKEYCODE_STAR
    0,                  // AKEYCODE_POUND
    KEY_UP,             // AKEYCODE_DPAD_UP
    KEY_DOWN,           // AKEYCODE_DPAD_DOWN
    KEY_LEFT,           // AKEYCODE_DPAD_LEFT
    KEY_RIGHT,          // AKEYCODE_DPAD_RIGHT
    0,                  // AKEYCODE_DPAD_CENTER
    KEY_VOLUME_UP,      // AKEYCODE_VOLUME_UP
    KEY_VOLUME_DOWN,    // AKEYCODE_VOLUME_DOWN
    0,                  // AKEYCODE_POWER
    0,                  // AKEYCODE_CAMERA
    0,                  // AKEYCODE_CLEAR
    KEY_A,              // AKEYCODE_A
    KEY_B,              // AKEYCODE_B
    KEY_C,              // AKEYCODE_C
    KEY_D,              // AKEYCODE_D
    KEY_E,              // AKEYCODE_E
    KEY_F,              // AKEYCODE_F
    KEY_G,              // AKEYCODE_G
    KEY_H,              // AKEYCODE_H
    KEY_I,              // AKEYCODE_I
    KEY_J,              // AKEYCODE_J
    KEY_K,              // AKEYCODE_K
    KEY_L,              // AKEYCODE_L
    KEY_M,              // AKEYCODE_M
    KEY_N,              // AKEYCODE_N
    KEY_O,              // AKEYCODE_O
    KEY_P,              // AKEYCODE_P
    KEY_Q,              // AKEYCODE_Q
    KEY_R,              // AKEYCODE_R
    KEY_S,              // AKEYCODE_S
    KEY_T,              // AKEYCODE_T
    KEY_U,              // AKEYCODE_U
    KEY_V,              // AKEYCODE_V
    KEY_W,              // AKEYCODE_W
    KEY_X,              // AKEYCODE_X
    KEY_Y,              // AKEYCODE_Y
    KEY_Z,              // AKEYCODE_Z
    KEY_COMMA,          // AKEYCODE_COMMA
    KEY_PERIOD,         // AKEYCODE_PERIOD
    KEY_LEFT_ALT,       // AKEYCODE_ALT_LEFT
    KEY_RIGHT_ALT,      // AKEYCODE_ALT_RIGHT
    KEY_LEFT_SHIFT,     // AKEYCODE_SHIFT_LEFT
    KEY_RIGHT_SHIFT,    // AKEYCODE_SHIFT_RIGHT
    KEY_TAB,            // AKEYCODE_TAB
    KEY_SPACE,          // AKEYCODE_SPACE
    0,                  // AKEYCODE_SYM
    0,                  // AKEYCODE_EXPLORER
    0,                  // AKEYCODE_ENVELOPE
    KEY_ENTER,          // AKEYCODE_ENTER
    KEY_BACKSPACE,      // AKEYCODE_DEL
    KEY_GRAVE,          // AKEYCODE_GRAVE
    KEY_MINUS,          // AKEYCODE_MINUS
    KEY_EQUAL,          // AKEYCODE_EQUALS
    KEY_LEFT_BRACKET,   // AKEYCODE_LEFT_BRACKET
    KEY_RIGHT_BRACKET,  // AKEYCODE_RIGHT_BRACKET
    KEY_BACKSLASH,      // AKEYCODE_BACKSLASH
    KEY_SEMICOLON,      // AKEYCODE_SEMICOLON
    KEY_APOSTROPHE,     // AKEYCODE_APOSTROPHE
    KEY_SLASH,          // AKEYCODE_SLASH
    0,                  // AKEYCODE_AT
    0,                  // AKEYCODE_NUM
    0,                  // AKEYCODE_HEADSETHOOK
    0,                  // AKEYCODE_FOCUS
    0,                  // AKEYCODE_PLUS
    KEY_MENU,           // AKEYCODE_MENU
    0,                  // AKEYCODE_NOTIFICATION
    0,                  // AKEYCODE_SEARCH
    0,                  // AKEYCODE_MEDIA_PLAY_PAUSE
    0,                  // AKEYCODE_MEDIA_STOP
    0,                  // AKEYCODE_MEDIA_NEXT
    0,                  // AKEYCODE_MEDIA_PREVIOUS
    0,                  // AKEYCODE_MEDIA_REWIND
    0,                  // AKEYCODE_MEDIA_FAST_FORWARD
    0,                  // AKEYCODE_MUTE
    KEY_PAGE_UP,        // AKEYCODE_PAGE_UP
    KEY_PAGE_DOWN,      // AKEYCODE_PAGE_DOWN
    0,                  // AKEYCODE_PICTSYMBOLS
    0,                  // AKEYCODE_SWITCH_CHARSET
    0,                  // AKEYCODE_BUTTON_A
    0,                  // AKEYCODE_BUTTON_B
    0,                  // AKEYCODE_BUTTON_C
    0,                  // AKEYCODE_BUTTON_X
    0,                  // AKEYCODE_BUTTON_Y
    0,                  // AKEYCODE_BUTTON_Z
    0,                  // AKEYCODE_BUTTON_L1
    0,                  // AKEYCODE_BUTTON_R1
    0,                  // AKEYCODE_BUTTON_L2
    0,                  // AKEYCODE_BUTTON_R2
    0,                  // AKEYCODE_BUTTON_THUMBL
    0,                  // AKEYCODE_BUTTON_THUMBR
    0,                  // AKEYCODE_BUTTON_START
    0,                  // AKEYCODE_BUTTON_SELECT
    0,                  // AKEYCODE_BUTTON_MODE
    KEY_ESCAPE,         // AKEYCODE_ESCAPE
    KEY_DELETE,         // AKEYCODE_FORWARD_DELL
    KEY_LEFT_CONTROL,   // AKEYCODE_CTRL_LEFT
    KEY_RIGHT_CONTROL,  // AKEYCODE_CTRL_RIGHT
    KEY_CAPS_LOCK,      // AKEYCODE_CAPS_LOCK
    KEY_SCROLL_LOCK,    // AKEYCODE_SCROLL_LOCK
    KEY_LEFT_SUPER,     // AKEYCODE_META_LEFT
    KEY_RIGHT_SUPER,    // AKEYCODE_META_RIGHT
    0,                  // AKEYCODE_FUNCTION
    KEY_PRINT_SCREEN,   // AKEYCODE_SYSRQ
    KEY_PAUSE,          // AKEYCODE_BREAK
    KEY_HOME,           // AKEYCODE_MOVE_HOME
    KEY_END,            // AKEYCODE_MOVE_END
    KEY_INSERT,         // AKEYCODE_INSERT
    0,                  // AKEYCODE_FORWARD
    0,                  // AKEYCODE_MEDIA_PLAY
    0,                  // AKEYCODE_MEDIA_PAUSE
    0,                  // AKEYCODE_MEDIA_CLOSE
    0,                  // AKEYCODE_MEDIA_EJECT
    0,                  // AKEYCODE_MEDIA_RECORD
    KEY_F1,             // AKEYCODE_F1
    KEY_F2,             // AKEYCODE_F2
    KEY_F3,             // AKEYCODE_F3
    KEY_F4,             // AKEYCODE_F4
    KEY_F5,             // AKEYCODE_F5
    KEY_F6,             // AKEYCODE_F6
    KEY_F7,             // AKEYCODE_F7
    KEY_F8,             // AKEYCODE_F8
    KEY_F9,             // AKEYCODE_F9
    KEY_F10,            // AKEYCODE_F10
    KEY_F11,            // AKEYCODE_F11
    KEY_F12,            // AKEYCODE_F12
    KEY_NUM_LOCK,       // AKEYCODE_NUM_LOCK
    KEY_KP_0,           // AKEYCODE_NUMPAD_0
    KEY_KP_1,           // AKEYCODE_NUMPAD_1
    KEY_KP_2,           // AKEYCODE_NUMPAD_2
    KEY_KP_3,           // AKEYCODE_NUMPAD_3
    KEY_KP_4,           // AKEYCODE_NUMPAD_4
    KEY_KP_5,           // AKEYCODE_NUMPAD_5
    KEY_KP_6,           // AKEYCODE_NUMPAD_6
    KEY_KP_7,           // AKEYCODE_NUMPAD_7
    KEY_KP_8,           // AKEYCODE_NUMPAD_8
    KEY_KP_9,           // AKEYCODE_NUMPAD_9
    KEY_KP_DIVIDE,      // AKEYCODE_NUMPAD_DIVIDE
    KEY_KP_MULTIPLY,    // AKEYCODE_NUMPAD_MULTIPLY
    KEY_KP_SUBTRACT,    // AKEYCODE_NUMPAD_SUBTRACT
    KEY_KP_ADD,         // AKEYCODE_NUMPAD_ADD
    KEY_KP_DECIMAL,     // AKEYCODE_NUMPAD_DOT
    0,                  // AKEYCODE_NUMPAD_COMMA
    KEY_KP_ENTER,       // AKEYCODE_NUMPAD_ENTER
    KEY_KP_EQUAL        // AKEYCODE_NUMPAD_EQUALS
};

//----------------------------------------------------------------------------------
// Module Internal Functions Declaration
//----------------------------------------------------------------------------------
int InitPlatform(void);                 // Initialize platform (graphics, inputs and more)
void ClosePlatform(void);               // Close platform

static bool InitGraphicsDevice(void);   // Initialize EGL display, context and offscreen surface
static void HostedApply(void);          // Render thread: apply the host's surface changes and input
static void HostedSetSize(int width, int height);
static GamepadButton AndroidTranslateGamepadButton(int button);

//----------------------------------------------------------------------------------
// Module Functions Definition: Host side (raylib_android_hosted.h)
//----------------------------------------------------------------------------------

static void HostedQueue(const HostedEvent *event)
{
    pthread_mutex_lock(&shared.lock);
    if (shared.count < HOSTED_EVENT_QUEUE_SIZE)
    {
        shared.events[(shared.head + shared.count)%HOSTED_EVENT_QUEUE_SIZE] = *event;
        shared.count++;
    }
    else if (!shared.overflowWarned)
    {
        shared.overflowWarned = true;
        __android_log_print(ANDROID_LOG_WARN, "raylib", "ANDROID_HOSTED: input queue full, events dropped (is the render loop running?)");
    }
    pthread_mutex_unlock(&shared.lock);
}

void RaylibHostedSetWindow(void *nativeWindow, int width, int height)
{
    ANativeWindow *window = (ANativeWindow *)nativeWindow;
    if (window != NULL) ANativeWindow_acquire(window);

    pthread_mutex_lock(&shared.lock);
    if (shared.window != NULL) ANativeWindow_release(shared.window);    // Replaced before the render thread took it
    shared.window = window;
    shared.windowChanged = true;
    shared.width = width;
    shared.height = height;
    shared.resized = true;
    pthread_mutex_unlock(&shared.lock);
}

void RaylibHostedClearWindow(void)
{
    RaylibHostedSetWindow(NULL, 0, 0);
}

void RaylibHostedResize(int width, int height)
{
    pthread_mutex_lock(&shared.lock);
    shared.width = width;
    shared.height = height;
    shared.resized = true;
    pthread_mutex_unlock(&shared.lock);
}

bool RaylibHostedGetSurfaceSize(int *width, int *height)
{
    // The host's surface, known from its first attach on, InitWindow() or
    // not: the "monitor" of a hosted window (its last size while detached)
    pthread_mutex_lock(&shared.lock);
    bool known = (shared.width > 0) && (shared.height > 0);
    if (known)
    {
        *width = shared.width;
        *height = shared.height;
    }
    pthread_mutex_unlock(&shared.lock);
    return known;
}

bool RaylibHostedIsReady(void)
{
    pthread_mutex_lock(&shared.lock);
    bool ready = platformReady;
    pthread_mutex_unlock(&shared.lock);
    return ready;
}

// The focus changes applied, in order, until popped (render thread only).
// IsWindowFocused() alone loses a trip to the background: the LostFocus and
// the GainedFocus are both applied before a frame could see it change.
#define HOSTED_FOCUS_CHANGES 16
static int focusChanges[HOSTED_FOCUS_CHANGES];
static int focusChangesHead = 0;
static int focusChangesCount = 0;

int RaylibHostedPopFocusChange(void)
{
    if (focusChangesCount == 0) return -1;
    const int change = focusChanges[focusChangesHead];
    focusChangesHead = (focusChangesHead + 1)%HOSTED_FOCUS_CHANGES;
    focusChangesCount--;
    return change;
}

void RaylibHostedPushFocus(bool gained)
{
    HostedEvent event = { .type = HOSTED_FOCUS, .a = gained };
    HostedQueue(&event);
}

void RaylibHostedPushClose(void)
{
    HostedEvent event = { .type = HOSTED_CLOSE };
    HostedQueue(&event);
}

bool RaylibHostedMakeCurrent(bool current)
{
    // The context follows the thread doing GL work (LiteCGSS moves it with
    // Ruby's GVL): released on one thread, made current on the next, bound
    // to the window surface, or to the offscreen one while detached
    if (platform.context == EGL_NO_CONTEXT) return false;
    if (!current) return eglMakeCurrent(platform.device, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT) == EGL_TRUE;
    EGLSurface surface = (platform.surface != EGL_NO_SURFACE)? platform.surface : platform.pbuffer;
    return eglMakeCurrent(platform.device, surface, surface, platform.context) == EGL_TRUE;
}

void RaylibHostedClearClose(void)
{
    // A close request ends one window: the next one (raylib keeps its window
    // and context across them) starts open, a close still queued included
    pthread_mutex_lock(&shared.lock);
    int kept = 0;
    for (int i = 0; i < shared.count; i++)
    {
        const HostedEvent event = shared.events[(shared.head + i)%HOSTED_EVENT_QUEUE_SIZE];
        if (event.type != HOSTED_CLOSE) shared.events[(shared.head + kept++)%HOSTED_EVENT_QUEUE_SIZE] = event;
    }
    shared.count = kept;
    pthread_mutex_unlock(&shared.lock);
    CORE.Window.shouldClose = false;
}

void RaylibHostedPushTouch(int phase, int pointerId, float x, float y)
{
    HostedEvent event = { .type = HOSTED_TOUCH, .a = phase, .b = pointerId, .f = { x, y } };
    HostedQueue(&event);
}

void RaylibHostedPushKey(int androidKeyCode, bool down)
{
    HostedEvent event = { .type = HOSTED_KEY, .a = androidKeyCode, .b = down };
    HostedQueue(&event);
}

void RaylibHostedPushText(unsigned int codepoint)
{
    HostedEvent event = { .type = HOSTED_TEXT, .codepoint = codepoint };
    HostedQueue(&event);
}

void RaylibHostedPushGamepadButton(int deviceId, int androidKeyCode, bool pressed)
{
    HostedEvent event = { .type = HOSTED_GAMEPAD_BUTTON, .a = deviceId, .b = androidKeyCode, .c = pressed };
    HostedQueue(&event);
}

void RaylibHostedPushGamepadAxes(int deviceId, float x, float y, float z, float rz,
                                 float hatX, float hatY, float leftTrigger, float rightTrigger)
{
    HostedEvent event = { .type = HOSTED_GAMEPAD_AXES, .a = deviceId,
                          .f = { x, y, z, rz, hatX, hatY, leftTrigger, rightTrigger } };
    HostedQueue(&event);
}

void RaylibHostedPushGamepadConnected(int deviceId, bool connected)
{
    HostedEvent event = { .type = HOSTED_GAMEPAD_CONNECTED, .a = deviceId, .c = connected };
    HostedQueue(&event);
}

void RaylibHostedPump(void)
{
    if (CORE.Window.ready) HostedApply();
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Window and Graphics Device
//----------------------------------------------------------------------------------

// Check if application should close
bool WindowShouldClose(void)
{
    if (CORE.Window.ready) return CORE.Window.shouldClose;
    else return true;
}

void ToggleFullscreen(void) { TRACELOG(LOG_WARNING, "ToggleFullscreen() not available on target platform"); }
void ToggleBorderlessWindowed(void) { TRACELOG(LOG_WARNING, "ToggleBorderlessWindowed() not available on target platform"); }
void MaximizeWindow(void) { TRACELOG(LOG_WARNING, "MaximizeWindow() not available on target platform"); }
void MinimizeWindow(void) { TRACELOG(LOG_WARNING, "MinimizeWindow() not available on target platform"); }
void RestoreWindow(void) { TRACELOG(LOG_WARNING, "RestoreWindow() not available on target platform"); }

// Set window configuration state using flags
void SetWindowState(unsigned int flags)
{
    if (FLAG_IS_SET(flags, FLAG_WINDOW_ALWAYS_RUN)) FLAG_SET(CORE.Window.flags, FLAG_WINDOW_ALWAYS_RUN);
}

// Clear window configuration state flags
void ClearWindowState(unsigned int flags)
{
    if (FLAG_IS_SET(flags, FLAG_WINDOW_ALWAYS_RUN)) FLAG_CLEAR(CORE.Window.flags, FLAG_WINDOW_ALWAYS_RUN);
}

void SetWindowIcon(Image image) { TRACELOG(LOG_WARNING, "SetWindowIcon() not available on target platform"); }
void SetWindowIcons(Image *images, int count) { TRACELOG(LOG_WARNING, "SetWindowIcons() not available on target platform"); }
void SetWindowTitle(const char *title) { CORE.Window.title = title; }
void SetWindowPosition(int x, int y) { TRACELOG(LOG_WARNING, "SetWindowPosition() not available on target platform"); }
void SetWindowMonitor(int monitor) { TRACELOG(LOG_WARNING, "SetWindowMonitor() not available on target platform"); }

void SetWindowMinSize(int width, int height)
{
    CORE.Window.screenMin.width = width;
    CORE.Window.screenMin.height = height;
}

void SetWindowMaxSize(int width, int height)
{
    CORE.Window.screenMax.width = width;
    CORE.Window.screenMax.height = height;
}

// The surface's size is the host's: nothing to resize here
void SetWindowSize(int width, int height) { TRACELOG(LOG_WARNING, "SetWindowSize() not available on target platform (the host sizes the surface)"); }
void SetWindowOpacity(float opacity) { TRACELOG(LOG_WARNING, "SetWindowOpacity() not available on target platform"); }
void SetWindowFocused(void) { TRACELOG(LOG_WARNING, "SetWindowFocused() not available on target platform"); }

// The attached ANativeWindow (NULL if none)
void *GetWindowHandle(void) { return platform.window; }

int GetMonitorCount(void) { return 1; }
int GetCurrentMonitor(void) { return 0; }
Vector2 GetMonitorPosition(int monitor) { return (Vector2){ 0, 0 }; }
int GetMonitorWidth(int monitor) { return CORE.Window.display.width; }
int GetMonitorHeight(int monitor) { return CORE.Window.display.height; }
int GetMonitorPhysicalWidth(int monitor) { return 0; }
int GetMonitorPhysicalHeight(int monitor) { return 0; }
int GetMonitorRefreshRate(int monitor) { return 60; }
const char *GetMonitorName(int monitor) { return ""; }
Vector2 GetWindowPosition(void) { return (Vector2){ 0, 0 }; }
Vector2 GetWindowScaleDPI(void) { return (Vector2){ 1.0f, 1.0f }; }

// The host's clipboard is the host's business
void SetClipboardText(const char *text) { TRACELOG(LOG_WARNING, "SetClipboardText() not available on target platform"); }
const char *GetClipboardText(void) { return NULL; }
Image GetClipboardImage(void) { Image image = { 0 }; return image; }

void ShowCursor(void) { CORE.Input.Mouse.cursorHidden = false; }
void HideCursor(void) { CORE.Input.Mouse.cursorHidden = true; }
void EnableCursor(void) { CORE.Input.Mouse.cursorLocked = false; }
void DisableCursor(void) { CORE.Input.Mouse.cursorLocked = true; }

// Swap back buffer with front buffer (screen drawing)
void SwapScreenBuffer(void)
{
    if (platform.surface != EGL_NO_SURFACE) eglSwapBuffers(platform.device, platform.surface);
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Misc
//----------------------------------------------------------------------------------

// Get elapsed time measure in seconds since InitTimer()
double GetTime(void)
{
    struct timespec ts = { 0 };
    clock_gettime(CLOCK_MONOTONIC, &ts);
    unsigned long long int nanoSeconds = (unsigned long long int)ts.tv_sec*1000000000LLU + (unsigned long long int)ts.tv_nsec;
    return (double)(nanoSeconds - CORE.Time.base)*1e-9;
}

// The host opens URLs (an Intent from its Activity)
void OpenURL(const char *url) { TRACELOG(LOG_WARNING, "OpenURL() not available on target platform (ask the host)"); }

//----------------------------------------------------------------------------------
// Module Functions Definition: Inputs
//----------------------------------------------------------------------------------

int SetGamepadMappings(const char *mappings) { TRACELOG(LOG_WARNING, "SetGamepadMappings() not available on target platform"); return 0; }
void SetGamepadVibration(int gamepad, float leftMotor, float rightMotor, float duration) { TRACELOG(LOG_WARNING, "SetGamepadVibration() not available on target platform"); }

void SetMousePosition(int x, int y)
{
    CORE.Input.Mouse.currentPosition = (Vector2){ (float)x, (float)y };
    CORE.Input.Mouse.previousPosition = CORE.Input.Mouse.currentPosition;
}

void SetMouseCursor(int cursor) { TRACELOG(LOG_WARNING, "SetMouseCursor() not available on target platform"); }
const char *GetKeyName(int key) { return ""; }

// Register all input events: the previous frame's states, then what the host sent
void PollInputEvents(void)
{
    // A new frame: the releases waiting for one can go
    hostedInput.recentPressCount = 0;

#if SUPPORT_GESTURES_SYSTEM
    // NOTE: Gestures update must be called every frame to reset gestures correctly
    UpdateGestures();
#endif

    // Reset keys/chars pressed registered
    CORE.Input.Keyboard.keyPressedQueueCount = 0;
    CORE.Input.Keyboard.charPressedQueueCount = 0;
    for (int i = 0; i < MAX_KEYBOARD_KEYS; i++)
    {
        CORE.Input.Keyboard.previousKeyState[i] = CORE.Input.Keyboard.currentKeyState[i];
        CORE.Input.Keyboard.keyRepeatInFrame[i] = 0;
    }

    // Reset last gamepad button registered state, register previous gamepad states
    CORE.Input.Gamepad.lastButtonPressed = 0;
    for (int i = 0; i < MAX_GAMEPADS; i++)
    {
        if (CORE.Input.Gamepad.ready[i])
        {
            for (int k = 0; k < MAX_GAMEPAD_BUTTONS; k++) CORE.Input.Gamepad.previousButtonState[i][k] = CORE.Input.Gamepad.currentButtonState[i][k];
        }
    }

    // Register previous touch and mouse states
    for (int i = 0; i < MAX_TOUCH_POINTS; i++) CORE.Input.Touch.previousTouchState[i] = CORE.Input.Touch.currentTouchState[i];
    for (int i = 0; i < MAX_MOUSE_BUTTONS; i++) CORE.Input.Mouse.previousButtonState[i] = CORE.Input.Mouse.currentButtonState[i];
    CORE.Input.Mouse.previousPosition = CORE.Input.Mouse.currentPosition;
    CORE.Window.resizedLastFrame = false;

    HostedApply();
}

//----------------------------------------------------------------------------------
// Module Internal Functions Definition
//----------------------------------------------------------------------------------

// Initialize platform: graphics, inputs and more
int InitPlatform(void)
{
    // Set some default window flags
    FLAG_CLEAR(CORE.Window.flags, FLAG_WINDOW_HIDDEN);
    FLAG_CLEAR(CORE.Window.flags, FLAG_WINDOW_MINIMIZED);
    FLAG_SET(CORE.Window.flags, FLAG_WINDOW_MAXIMIZED);
    FLAG_CLEAR(CORE.Window.flags, FLAG_WINDOW_UNFOCUSED);
    FLAG_SET(CORE.Window.flags, FLAG_FULLSCREEN_MODE);

    for (int i = 0; i < MAX_GAMEPADS; i++) hostedInput.deviceId[i] = -1;
    hostedInput.pointCount = 0;

    if (!InitGraphicsDevice()) return -1;

    // Until a surface is attached, the size InitWindow() asked for
    HostedSetSize(CORE.Window.screen.width, CORE.Window.screen.height);

    // Load OpenGL extensions
    // NOTE: GL procedures address loader is required to load extensions
    rlLoadExtensions(eglGetProcAddress);

    CORE.Window.ready = true;
    pthread_mutex_lock(&shared.lock);
    platformReady = true;
    pthread_mutex_unlock(&shared.lock);

    // A surface attached before InitWindow(): bind it now
    HostedApply();

    InitTimer();
    CORE.Storage.basePath = GetWorkingDirectory();

    TRACELOG(LOG_INFO, "PLATFORM: ANDROID_HOSTED: Initialized successfully");
    return 0;
}

// Close platform
void ClosePlatform(void)
{
    pthread_mutex_lock(&shared.lock);
    platformReady = false;
    if (shared.window != NULL) ANativeWindow_release(shared.window);
    shared.window = NULL;
    shared.windowChanged = false;
    shared.count = 0;
    pthread_mutex_unlock(&shared.lock);

    if (platform.device != EGL_NO_DISPLAY)
    {
        eglMakeCurrent(platform.device, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (platform.surface != EGL_NO_SURFACE) eglDestroySurface(platform.device, platform.surface);
        if (platform.pbuffer != EGL_NO_SURFACE) eglDestroySurface(platform.device, platform.pbuffer);
        if (platform.context != EGL_NO_CONTEXT) eglDestroyContext(platform.device, platform.context);
        eglTerminate(platform.device);
    }
    platform.surface = EGL_NO_SURFACE;
    platform.pbuffer = EGL_NO_SURFACE;
    platform.context = EGL_NO_CONTEXT;
    platform.device = EGL_NO_DISPLAY;
    if (platform.window != NULL) ANativeWindow_release(platform.window);
    platform.window = NULL;
}

// EGL display, config, context, and the offscreen surface current while no window is attached
static bool InitGraphicsDevice(void)
{
    const bool es3 = (rlGetVersion() == RL_OPENGL_ES_30);

    EGLint samples = 0;
    EGLint sampleBuffer = 0;
    if (FLAG_IS_SET(CORE.Window.flags, FLAG_MSAA_4X_HINT))
    {
        samples = 4;
        sampleBuffer = 1;
        TRACELOG(LOG_INFO, "DISPLAY: Trying to enable MSAA x4");
    }

    const EGLint framebufferAttribs[] = {
        EGL_RENDERABLE_TYPE, es3? EGL_OPENGL_ES3_BIT : EGL_OPENGL_ES2_BIT,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT | EGL_PBUFFER_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_SAMPLE_BUFFERS, sampleBuffer,
        EGL_SAMPLES, samples,
        EGL_NONE
    };

    const EGLint contextAttribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, es3? 3 : 2,
        EGL_NONE
    };

    platform.device = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (platform.device == EGL_NO_DISPLAY || eglInitialize(platform.device, NULL, NULL) == EGL_FALSE)
    {
        TRACELOG(LOG_WARNING, "DISPLAY: Failed to initialize EGL device");
        return false;
    }

    EGLint numConfigs = 0;
    if (eglChooseConfig(platform.device, framebufferAttribs, &platform.config, 1, &numConfigs) == EGL_FALSE || numConfigs < 1)
    {
        TRACELOG(LOG_WARNING, "DISPLAY: No EGL config for OpenGL ES %s", es3? "3" : "2");
        return false;
    }

    eglBindAPI(EGL_OPENGL_ES_API);
    platform.context = eglCreateContext(platform.device, platform.config, EGL_NO_CONTEXT, contextAttribs);
    if (platform.context == EGL_NO_CONTEXT)
    {
        TRACELOG(LOG_WARNING, "DISPLAY: Failed to create EGL context");
        return false;
    }

    const EGLint pbufferAttribs[] = { EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE };
    platform.pbuffer = eglCreatePbufferSurface(platform.device, platform.config, pbufferAttribs);
    platform.surface = EGL_NO_SURFACE;
    if (platform.pbuffer == EGL_NO_SURFACE ||
        eglMakeCurrent(platform.device, platform.pbuffer, platform.pbuffer, platform.context) == EGL_FALSE)
    {
        TRACELOG(LOG_WARNING, "DISPLAY: Failed to make the EGL context current");
        return false;
    }

    TRACELOG(LOG_INFO, "DISPLAY: Device initialized successfully (OpenGL ES %s)", es3? "3" : "2");
    return true;
}

// Screen, render and framebuffer size: the surface's pixels, drawn 1:1
static void HostedSetSize(int width, int height)
{
    if ((width <= 0) || (height <= 0)) return;

    CORE.Window.display.width = width;
    CORE.Window.display.height = height;
    CORE.Window.screen.width = width;
    CORE.Window.screen.height = height;
    CORE.Window.render.width = width;
    CORE.Window.render.height = height;
    CORE.Window.currentFbo.width = width;
    CORE.Window.currentFbo.height = height;
    CORE.Window.renderOffset.x = 0;
    CORE.Window.renderOffset.y = 0;
    CORE.Window.screenScale = MatrixIdentity();
    CORE.Window.resizedLastFrame = true;
}

// Render thread: switch EGL surfaces if the host attached / detached one
static void HostedApplySurface(ANativeWindow *window, int width, int height)
{
    // The old window surface goes first (the context stays, current on the offscreen surface)
    eglMakeCurrent(platform.device, platform.pbuffer, platform.pbuffer, platform.context);
    if (platform.surface != EGL_NO_SURFACE)
    {
        eglDestroySurface(platform.device, platform.surface);
        platform.surface = EGL_NO_SURFACE;
    }
    if (platform.window != NULL) ANativeWindow_release(platform.window);
    platform.window = window;   // Takes over the reference RaylibHostedSetWindow() acquired

    if (window == NULL)
    {
        TRACELOG(LOG_INFO, "ANDROID_HOSTED: Surface detached");
        return;
    }

    // EGL_NATIVE_VISUAL_ID is guaranteed to be accepted by ANativeWindow_setBuffersGeometry()
    EGLint format = 0;
    eglGetConfigAttrib(platform.device, platform.config, EGL_NATIVE_VISUAL_ID, &format);
    ANativeWindow_setBuffersGeometry(window, 0, 0, format);     // The surface's own size

    platform.surface = eglCreateWindowSurface(platform.device, platform.config, window, NULL);
    if ((platform.surface == EGL_NO_SURFACE) ||
        (eglMakeCurrent(platform.device, platform.surface, platform.surface, platform.context) == EGL_FALSE))
    {
        TRACELOG(LOG_WARNING, "ANDROID_HOSTED: Failed to bind the attached surface (EGL error 0x%x)", eglGetError());
        if (platform.surface != EGL_NO_SURFACE) eglDestroySurface(platform.device, platform.surface);
        platform.surface = EGL_NO_SURFACE;
        eglMakeCurrent(platform.device, platform.pbuffer, platform.pbuffer, platform.context);
        return;
    }

    EGLint surfaceWidth = 0, surfaceHeight = 0;
    eglQuerySurface(platform.device, platform.surface, EGL_WIDTH, &surfaceWidth);
    eglQuerySurface(platform.device, platform.surface, EGL_HEIGHT, &surfaceHeight);
    if ((surfaceWidth <= 0) || (surfaceHeight <= 0))
    {
        surfaceWidth = width;
        surfaceHeight = height;
    }
    HostedSetSize(surfaceWidth, surfaceHeight);
    SetupViewport(surfaceWidth, surfaceHeight);
    TRACELOG(LOG_INFO, "ANDROID_HOSTED: Surface attached (%i x %i)", surfaceWidth, surfaceHeight);
}

// Gamepad slot of an Android device id (a free one when allocate), -1 if none
static int HostedGamepadSlot(int deviceId, bool allocate)
{
    for (int i = 0; i < MAX_GAMEPADS; i++) if (hostedInput.deviceId[i] == deviceId) return i;
    if (!allocate) return -1;
    for (int i = 0; i < MAX_GAMEPADS; i++)
    {
        if (hostedInput.deviceId[i] == -1)
        {
            hostedInput.deviceId[i] = deviceId;
            CORE.Input.Gamepad.ready[i] = true;
            CORE.Input.Gamepad.axisCount[i] = 6;
            snprintf(CORE.Input.Gamepad.name[i], MAX_GAMEPAD_NAME_LENGTH, "Android gamepad %i", deviceId);
            return i;
        }
    }
    return -1;
}

// Touch points to raylib's touch state. Unlike PLATFORM_ANDROID, touches don't
// drive the mouse (raylib maps currentTouchState to IsMouseButtonDown): a game
// gets touch events only, as with SFML's Android. A mouse driven by the first
// finger made every touch a click too, the on-screen gamepad's included (PSDK's
// menus took the click over its B). Touches as an alternative way to move the
// mouse, if wanted, belong where they can be told apart: the touch overlay,
// which forwards the touches outside its buttons to the game.
static void HostedUpdateTouchState(void)
{
    CORE.Input.Touch.pointCount = hostedInput.pointCount;
    for (int i = 0; i < hostedInput.pointCount; i++)
    {
        CORE.Input.Touch.pointId[i] = hostedInput.pointId[i];
        CORE.Input.Touch.position[i] = hostedInput.position[i];
    }
}

static void HostedTouch(int phase, int pointerId, float x, float y)
{
    int index = -1;
    for (int i = 0; i < hostedInput.pointCount; i++) if (hostedInput.pointId[i] == pointerId) index = i;

    if (phase == RAYLIB_HOSTED_TOUCH_UP)
    {
        if (index >= 0)
        {
            for (int i = index; i < hostedInput.pointCount - 1; i++)
            {
                hostedInput.pointId[i] = hostedInput.pointId[i + 1];
                hostedInput.position[i] = hostedInput.position[i + 1];
            }
            hostedInput.pointCount--;
        }
    }
    else
    {
        if (index < 0)
        {
            if (hostedInput.pointCount >= MAX_TOUCH_POINTS) return;
            index = hostedInput.pointCount++;
            hostedInput.pointId[index] = pointerId;
        }
        hostedInput.position[index] = (Vector2){ x, y };
    }

#if SUPPORT_GESTURES_SYSTEM
    GestureEvent gestureEvent = { 0 };
    gestureEvent.touchAction = (phase == RAYLIB_HOSTED_TOUCH_DOWN)? TOUCH_ACTION_DOWN :
                               (phase == RAYLIB_HOSTED_TOUCH_UP)? TOUCH_ACTION_UP : TOUCH_ACTION_MOVE;
    gestureEvent.pointCount = 1;
    gestureEvent.pointId[0] = pointerId;
    gestureEvent.position[0] = (Vector2){ x/(float)GetScreenWidth(), y/(float)GetScreenHeight() };
    ProcessGestureEvent(gestureEvent);
#endif

    HostedUpdateTouchState();
}

static void HostedKey(int keycode, bool down)
{
    KeyboardKey key = ((keycode > 0) && (keycode < KEYCODE_MAP_SIZE))? mapKeycode[keycode] : KEY_NULL;
    if (key == KEY_NULL) return;

    if (down)
    {
        if (CORE.Input.Keyboard.currentKeyState[key]) CORE.Input.Keyboard.keyRepeatInFrame[key] = 1;
        CORE.Input.Keyboard.currentKeyState[key] = 1;
        if (CORE.Input.Keyboard.keyPressedQueueCount < MAX_KEY_PRESSED_QUEUE)
        {
            CORE.Input.Keyboard.keyPressedQueue[CORE.Input.Keyboard.keyPressedQueueCount] = key;
            CORE.Input.Keyboard.keyPressedQueueCount++;
        }
    }
    else CORE.Input.Keyboard.currentKeyState[key] = 0;
}

static void HostedGamepadAxes(int slot, const float *axes)
{
    CORE.Input.Gamepad.axisState[slot][GAMEPAD_AXIS_LEFT_X] = axes[0];
    CORE.Input.Gamepad.axisState[slot][GAMEPAD_AXIS_LEFT_Y] = axes[1];
    CORE.Input.Gamepad.axisState[slot][GAMEPAD_AXIS_RIGHT_X] = axes[2];
    CORE.Input.Gamepad.axisState[slot][GAMEPAD_AXIS_RIGHT_Y] = axes[3];
    CORE.Input.Gamepad.axisState[slot][GAMEPAD_AXIS_LEFT_TRIGGER] = axes[6]*2.0f - 1.0f;
    CORE.Input.Gamepad.axisState[slot][GAMEPAD_AXIS_RIGHT_TRIGGER] = axes[7]*2.0f - 1.0f;

    // The hat is the D-pad
    const float hatX = axes[4], hatY = axes[5];
    CORE.Input.Gamepad.currentButtonState[slot][GAMEPAD_BUTTON_LEFT_FACE_RIGHT] = (hatX > 0.5f);
    CORE.Input.Gamepad.currentButtonState[slot][GAMEPAD_BUTTON_LEFT_FACE_LEFT] = (hatX < -0.5f);
    CORE.Input.Gamepad.currentButtonState[slot][GAMEPAD_BUTTON_LEFT_FACE_DOWN] = (hatY > 0.5f);
    CORE.Input.Gamepad.currentButtonState[slot][GAMEPAD_BUTTON_LEFT_FACE_UP] = (hatY < -0.5f);
}

// The press an event makes (true), or the release (false); other events: neither
static bool HostedPressOf(const HostedEvent *event, bool *press, int *id, int *code)
{
    switch (event->type)
    {
        case HOSTED_TOUCH: *press = (event->a != RAYLIB_HOSTED_TOUCH_UP); *id = event->b; *code = 0; return (event->a != RAYLIB_HOSTED_TOUCH_MOVE);
        case HOSTED_KEY: *press = event->b; *id = 0; *code = event->a; return true;
        case HOSTED_GAMEPAD_BUTTON: *press = event->c; *id = event->a; *code = event->b; return true;
        default: return false;
    }
}

// Under shared.lock: how many of the queued events this frame takes. It stops
// at the release of something pressed in this frame (a tap shorter than a
// frame), which the next frame takes, unless it has waited long enough.
static int HostedTakeEvents(void)
{
    const double now = GetTime();
    int taken = 0;
    for (; taken < shared.count; taken++)
    {
        const HostedEvent *event = &shared.events[(shared.head + taken)%HOSTED_EVENT_QUEUE_SIZE];
        bool press = false;
        int id = 0, code = 0;
        if (!HostedPressOf(event, &press, &id, &code)) continue;

        int recent = -1;
        for (int i = 0; i < hostedInput.recentPressCount; i++)
        {
            if ((hostedInput.recentPress[i].type == event->type) && (hostedInput.recentPress[i].id == id) &&
                (hostedInput.recentPress[i].code == code)) recent = i;
        }
        if (press)
        {
            if ((recent < 0) && (hostedInput.recentPressCount < (int)(sizeof(hostedInput.recentPress)/sizeof(hostedInput.recentPress[0]))))
            {
                recent = hostedInput.recentPressCount++;
                hostedInput.recentPress[recent].type = event->type;
                hostedInput.recentPress[recent].id = id;
                hostedInput.recentPress[recent].code = code;
            }
            if (recent >= 0) hostedInput.recentPress[recent].time = now;
        }
        else if ((recent >= 0) && ((now - hostedInput.recentPress[recent].time) < HOSTED_RELEASE_HOLD_SECONDS)) break;
    }
    return taken;
}

// Render thread: the host's surface changes, then its events, in order
static void HostedApply(void)
{
    HostedEvent events[HOSTED_EVENT_QUEUE_SIZE];
    int count = 0;
    bool windowChanged = false, resized = false;
    ANativeWindow *window = NULL;
    int width = 0, height = 0;

    pthread_mutex_lock(&shared.lock);
    if (shared.windowChanged)
    {
        windowChanged = true;
        window = shared.window;     // The reference moves to the render thread
        shared.window = NULL;
        shared.windowChanged = false;
    }
    if (shared.resized)
    {
        resized = true;
        width = shared.width;
        height = shared.height;
        shared.resized = false;
    }
    const int taken = HostedTakeEvents();
    for (count = 0; count < taken; count++) events[count] = shared.events[(shared.head + count)%HOSTED_EVENT_QUEUE_SIZE];
    shared.head = (shared.head + taken)%HOSTED_EVENT_QUEUE_SIZE;
    shared.count -= taken;
    if (shared.count == 0) shared.head = 0;
    shared.overflowWarned = false;
    pthread_mutex_unlock(&shared.lock);

    if (windowChanged) HostedApplySurface(window, width, height);
    else if (resized && (platform.surface != EGL_NO_SURFACE))
    {
        // The window surface follows its window: read its new size back
        EGLint surfaceWidth = 0, surfaceHeight = 0;
        eglQuerySurface(platform.device, platform.surface, EGL_WIDTH, &surfaceWidth);
        eglQuerySurface(platform.device, platform.surface, EGL_HEIGHT, &surfaceHeight);
        if ((surfaceWidth <= 0) || (surfaceHeight <= 0)) { surfaceWidth = width; surfaceHeight = height; }
        HostedSetSize(surfaceWidth, surfaceHeight);
        SetupViewport(surfaceWidth, surfaceHeight);
    }

    for (int i = 0; i < count; i++)
    {
        const HostedEvent *event = &events[i];
        switch (event->type)
        {
            case HOSTED_FOCUS:
            {
                if (event->a) FLAG_CLEAR(CORE.Window.flags, FLAG_WINDOW_UNFOCUSED);
                else FLAG_SET(CORE.Window.flags, FLAG_WINDOW_UNFOCUSED);
                // Full: the oldest change goes (a reader that stopped reading)
                if (focusChangesCount == HOSTED_FOCUS_CHANGES) RaylibHostedPopFocusChange();
                focusChanges[(focusChangesHead + focusChangesCount)%HOSTED_FOCUS_CHANGES] = event->a? 1 : 0;
                focusChangesCount++;
            } break;
            case HOSTED_CLOSE: CORE.Window.shouldClose = true; break;
            case HOSTED_TOUCH: HostedTouch(event->a, event->b, event->f[0], event->f[1]); break;
            case HOSTED_KEY: HostedKey(event->a, event->b); break;
            case HOSTED_TEXT:
            {
                if (CORE.Input.Keyboard.charPressedQueueCount < MAX_CHAR_PRESSED_QUEUE)
                {
                    CORE.Input.Keyboard.charPressedQueue[CORE.Input.Keyboard.charPressedQueueCount] = (int)event->codepoint;
                    CORE.Input.Keyboard.charPressedQueueCount++;
                }
            } break;
            case HOSTED_GAMEPAD_BUTTON:
            {
                const int slot = HostedGamepadSlot(event->a, true);
                const GamepadButton button = AndroidTranslateGamepadButton(event->b);
                if ((slot >= 0) && (button != GAMEPAD_BUTTON_UNKNOWN))
                {
                    CORE.Input.Gamepad.currentButtonState[slot][button] = event->c? 1 : 0;
                    if (event->c) CORE.Input.Gamepad.lastButtonPressed = button;
                }
            } break;
            case HOSTED_GAMEPAD_AXES:
            {
                const int slot = HostedGamepadSlot(event->a, true);
                if (slot >= 0) HostedGamepadAxes(slot, event->f);
            } break;
            case HOSTED_GAMEPAD_CONNECTED:
            {
                const int slot = HostedGamepadSlot(event->a, event->c);
                if ((slot >= 0) && !event->c)
                {
                    hostedInput.deviceId[slot] = -1;
                    CORE.Input.Gamepad.ready[slot] = false;
                    memset(CORE.Input.Gamepad.currentButtonState[slot], 0, sizeof(CORE.Input.Gamepad.currentButtonState[slot]));
                    memset(CORE.Input.Gamepad.axisState[slot], 0, sizeof(CORE.Input.Gamepad.axisState[slot]));
                }
            } break;
            default: break;
        }
    }
}

// Android gamepad key codes to raylib buttons: as PLATFORM_ANDROID (rcore_android.c)
static GamepadButton AndroidTranslateGamepadButton(int button)
{
    switch (button)
    {
        case AKEYCODE_BUTTON_A: return GAMEPAD_BUTTON_RIGHT_FACE_DOWN;
        case AKEYCODE_BUTTON_B: return GAMEPAD_BUTTON_RIGHT_FACE_RIGHT;
        case AKEYCODE_BUTTON_X: return GAMEPAD_BUTTON_RIGHT_FACE_LEFT;
        case AKEYCODE_BUTTON_Y: return GAMEPAD_BUTTON_RIGHT_FACE_UP;
        case AKEYCODE_BUTTON_L1: return GAMEPAD_BUTTON_LEFT_TRIGGER_1;
        case AKEYCODE_BUTTON_R1: return GAMEPAD_BUTTON_RIGHT_TRIGGER_1;
        case AKEYCODE_BUTTON_L2: return GAMEPAD_BUTTON_LEFT_TRIGGER_2;
        case AKEYCODE_BUTTON_R2: return GAMEPAD_BUTTON_RIGHT_TRIGGER_2;
        case AKEYCODE_BUTTON_THUMBL: return GAMEPAD_BUTTON_LEFT_THUMB;
        case AKEYCODE_BUTTON_THUMBR: return GAMEPAD_BUTTON_RIGHT_THUMB;
        case AKEYCODE_BUTTON_START: return GAMEPAD_BUTTON_MIDDLE_RIGHT;
        case AKEYCODE_BUTTON_SELECT: return GAMEPAD_BUTTON_MIDDLE_LEFT;
        case AKEYCODE_BUTTON_MODE: return GAMEPAD_BUTTON_MIDDLE;
        // On some (most?) gamepads dpad events are reported as axis motion instead
        case AKEYCODE_DPAD_DOWN: return GAMEPAD_BUTTON_LEFT_FACE_DOWN;
        case AKEYCODE_DPAD_RIGHT: return GAMEPAD_BUTTON_LEFT_FACE_RIGHT;
        case AKEYCODE_DPAD_LEFT: return GAMEPAD_BUTTON_LEFT_FACE_LEFT;
        case AKEYCODE_DPAD_UP: return GAMEPAD_BUTTON_LEFT_FACE_UP;
        default: return GAMEPAD_BUTTON_UNKNOWN;
    }
}
