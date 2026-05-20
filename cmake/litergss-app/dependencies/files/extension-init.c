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
/* Forward declarations of extension initialization functions */
extern void Init_LiteRGSS(void);
extern void Init_SFMLAudio(void);
extern void Init_physfs(void);
extern void Init_psdk_vm_snapshot_native(void);

void initialize_litergss_extensions(void) {
    /* Initialize the ruby-physfs gem first — pokemonsdk Ruby code that
     * runs during LiteRGSS initialization may already need PhysFS::mount.
     * The gem is statically compiled into libphysfs-ruby.a (built by
     * ruby-for-android) and gets folded into librgss_runtime.a; rb_provide
     * makes `require 'physfs'` a no-op. */
    Init_physfs();
    rb_provide("physfs");

    /* PSDK VM snapshot extension (external/ruby-psdk-vm-snapshot). No
     * dependencies on the other Ruby-side modules — initialised early
     * so PSDKVMSnapshot::Native is available before any PSDK-side Ruby
     * code runs and calls capture! / restore!. */
    Init_psdk_vm_snapshot_native();
    rb_provide("psdk_vm_snapshot_native");

    /* Initialize LiteRGSS extension */
    Init_LiteRGSS();
    rb_provide("LiteRGSS");

    /* Initialize SFMLAudio extension */
    Init_SFMLAudio();
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
}