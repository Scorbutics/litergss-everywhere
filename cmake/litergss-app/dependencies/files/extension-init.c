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

void initialize_litergss_extensions(void) {
    /* Initialize LiteRGSS extension */
    Init_LiteRGSS();
    rb_provide("LiteRGSS");

    /* Initialize SFMLAudio extension */
    Init_SFMLAudio();
    rb_provide("SFMLAudio");
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