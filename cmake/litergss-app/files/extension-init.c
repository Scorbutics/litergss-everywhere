/*
 * extension-init.c
 *
 * Glue code for initializing statically linked Ruby extensions.
 * Used by both Android and iOS builds.
 *
 * This file provides a unified initialization function that:
 * 1. Calls each extension's Init function directly
 * 2. Uses rb_provide() to register the extension with Ruby's require system
 * 3. Makes require 'ExtensionName' work transparently in Ruby code
 */

#include "ruby.h"

/* Forward declarations of extension initialization functions */
extern void Init_LiteRGSS(void);
extern void Init_SFMLAudio(void);

/**
 * Initialize all static Ruby extensions.
 *
 * This function should be called after ruby_init() and ruby_init_loadpath()
 * but before any Ruby code is executed.
 *
 * Platform integration:
 * - Android: Call from JNI initialization function
 * - iOS: Call from application:didFinishLaunchingWithOptions:
 */
void ruby_init_litergss_extensions(void) {
    /* Initialize LiteRGSS extension */
    Init_LiteRGSS();
    rb_provide("LiteRGSS.so");

    /* Initialize SFMLAudio extension */
    Init_SFMLAudio();
    rb_provide("SFMLAudio.so");

    /* Note: rb_provide() makes require 'ExtensionName' work transparently
     * even though the extensions are statically linked, not dynamically loaded.
     * This maintains compatibility with Ruby code that expects to use require.
     */
}
