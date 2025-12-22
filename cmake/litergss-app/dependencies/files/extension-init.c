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

/* Forward declarations of extension initialization functions */
extern void Init_LiteRGSS(void);
extern void Init_SFMLAudio(void);

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
void initialize_litergss_extensions(void) {
    /* Initialize LiteRGSS extension */
    Init_LiteRGSS();

    /* Initialize SFMLAudio extension */
    Init_SFMLAudio();

    /* Note: No need for rb_provide() - the statically linked extensions
     * are automatically resolvable via Ruby's require mechanism.
     */
}
