/*
 * extension-init.c
 *
 * Callback-based initialization for statically linked LiteRGSS extensions.
 * Compatible with embedded-ruby-vm custom extension callback mechanism.
 *
 * This file provides a unified initialization function that:
 * 1. Calls each extension's Init function directly
 * 2. Is valid to use as a callback for ruby_set_custom_ext_init()
 */

#include "ruby.h"
#include "embedded-ruby-vm/ruby-custom-ext.h"

/**
 * Initialize all LiteRGSS Ruby extensions.
 *
 * This callback is designed to be registered with embedded-ruby-vm via:
 *   api.set_custom_ext_init(initialize_litergss_extensions);
 *
 * It will be invoked automatically during Ruby VM initialization,
 * after Init_ext() but before Ruby starts executing scripts.
 *
 * The extensions will be available via require statements:
 *   require 'LiteRGSS'
 *   require 'SFMLAudio'
 */
/* The extensions' init functions: Init_<name>, where an Android shared build
 * names them lib<name> (cmake/litergss-app/ruby-extension-names.cmake) */
#ifndef LITERGSS_INIT_FUNCTION
#define LITERGSS_INIT_FUNCTION Init_LiteRGSS
#endif
#ifndef SFMLAUDIO_INIT_FUNCTION
#define SFMLAUDIO_INIT_FUNCTION Init_SFMLAudio
#endif

/* Forward declarations of extension initialization functions */
extern void LITERGSS_INIT_FUNCTION(void);
extern void SFMLAUDIO_INIT_FUNCTION(void);
extern void Init_physfs(void);
/* ruby-client.c: registers ruby/litergss with embedded-ruby-vm's install */
extern void litergss_register_ruby_client(void);

#ifdef LITERGSS_USE_TRACY
/* Tracy C API (tracy/TracyC.h, TRACY_MANUAL_LIFETIME), libTracyClient.a.
 * Declared here: TracyC.h only declares them under Tracy's own defines. */
extern void ___tracy_startup_profiler(void);
extern int ___tracy_profiler_started(void);

/* LiteCGSS is built with TRACY_MANUAL_LIFETIME: its zones crash until the
 * profiler is started, and no Ruby code can do it (upstream expects the
 * caller of LiteRGSS_tracy.so to). Started before any LiteCGSS code runs,
 * once per process: the VM may be initialised again (soft reset), the
 * profiler outlives it. Never shut down: LiteCGSS objects freed by the
 * last GC still open zones. TRACY_ON_DEMAND: nothing is recorded until a
 * Tracy server connects (Android: adb forward tcp:8086 tcp:8086). */
static void litergss_start_tracy(void) {
    if (!___tracy_profiler_started()) {
        ___tracy_startup_profiler();
    }
}
#endif

void initialize_litergss_extensions(void) {
#ifdef LITERGSS_USE_TRACY
    litergss_start_tracy();
#endif

    /* Initialize the ruby-physfs gem first — pokemonsdk Ruby code that
     * runs during LiteRGSS initialization may already need PhysFS::mount.
     * The gem is statically compiled into libphysfs-ruby.a (built by
     * ruby-for-android) and gets folded into librgss_runtime.a; rb_provide
     * makes `require 'physfs'` a no-op. */
    Init_physfs();
    rb_provide("physfs");

    /* Initialize LiteRGSS extension */
    LITERGSS_INIT_FUNCTION();
    rb_provide("LiteRGSS");
#ifdef LITERGSS_USE_TRACY
    /* Upstream's name for a Tracy build: scripts requiring it get this one */
    rb_provide("LiteRGSS_tracy");
#endif

    /* Initialize SFMLAudio extension */
    SFMLAUDIO_INIT_FUNCTION();
    rb_provide("SFMLAudio");

    /* Inject the PhysFS gem's reentrant Monitor into LiteRGSS so that
     * LiteCGSS's direct PHYSFS_* calls (font streams, image loaders, etc.)
     * serialise behind the SAME GVL-aware lock as the physfs gem's own
     * entry points. Without this, two Ruby Threads can race on PhysFS's
     * internal pthread stateLock from opposite sides of the gem boundary,
     * producing the GVL-vs-stateLock inversion deadlock that physfs's
     * Monitor was added to prevent (see physfs/ext/physfs/PhysFSLock.h).
     *
     * Safe to call unconditionally here: both gems are now initialised,
     * and LiteRGSS.vfs_lock= validates the lock at install time. */
    {
        VALUE physfs_mod  = rb_const_get(rb_cObject, rb_intern("PhysFS"));
        VALUE litergss_m  = rb_const_get(rb_cObject, rb_intern("LiteRGSS"));
        VALUE monitor     = rb_funcall(physfs_mod, rb_intern("monitor"), 0);
        rb_funcall(litergss_m, rb_intern("vfs_lock="), 1, monitor);
    }
}

/**
 * Auto-register LiteRGSS extensions callback.
 *
 * This constructor function runs automatically when the library loads,
 * before main() is called. It registers the extension initializer with
 * the embedded-ruby-vm so extensions are available when Ruby starts.
 *
 * Works on: GCC, Clang (Linux, macOS, Android, iOS)
 */
__attribute__((constructor))
static void auto_register_litergss_extensions(void) {
    ruby_set_custom_ext_init(initialize_litergss_extensions);
    /* Ruby client code shipped with the runtime (ruby/litergss): extracted
     * with the Ruby standard library, so `require 'litergss/touch_overlay'`
     * loads it. Registered before the VM installs its assets. */
    litergss_register_ruby_client();
}