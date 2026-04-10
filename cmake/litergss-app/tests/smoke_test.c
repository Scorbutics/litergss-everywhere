/*
 * smoke_test.c - Build artifact smoke test for librgss_runtime.
 *
 * This test verifies that the combined library (fat static archive or shared
 * wrapper) is correctly assembled by:
 *   1. Calling lightweight API functions that don't need a full Ruby runtime
 *   2. Checking that key function pointers resolve to non-NULL
 *   3. Referencing extension init symbols to prove linkage
 *
 * This test is only compiled and run for native (non-cross-compiled) builds.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "embedded-ruby-vm/assets-error.h"
#include "embedded-ruby-vm/assets-install.h"
#include "embedded-ruby-vm/static/ruby-api-loader.h"

/* Proper API headers above already declare the real signatures.
 * Skip the generic void(void) declarations, keep only the symbol table. */
#define RGSS_NO_EXTERN_DECLARATIONS
#include "rgss_expected_symbols.h"

static int failures = 0;

#define CHECK(desc, expr)                                              \
    do {                                                               \
        if (expr) {                                                    \
            printf("  OK: %s\n", desc);                                \
        } else {                                                       \
            printf("  FAIL: %s\n", desc);                              \
            failures++;                                                \
        }                                                              \
    } while (0)

#define CHECK_NOT_NULL(desc, ptr) CHECK(desc, (ptr) != NULL)

int main(void) {
    printf("=== LiteRGSS runtime smoke test ===\n\n");

    /* --- assets error API --- */
    printf("[assets error API]\n");
    {
        AssetsError error;
        assets_error_init(&error);
        CHECK("assets_error_init zeroes code", error.code == ASSETS_OK);
        CHECK("assets_error_init zeroes message", error.message[0] == '\0');

        const char* msg = assets_error_string(ASSETS_OK);
        CHECK_NOT_NULL("assets_error_string returns non-NULL", msg);
    }

    /* --- assets install API --- */
    printf("\n[assets install API]\n");
    {
        const char* dir = get_default_install_dir();
        CHECK_NOT_NULL("get_default_install_dir returns non-NULL", dir);
        if (dir) {
            printf("    default install dir: %s\n", dir);
        }
    }

    /* --- Ruby API loader (static) --- */
    printf("\n[Ruby API loader]\n");
    {
        RubyAPI api;
        int rc = ruby_api_load(NULL, &api);
        CHECK("ruby_api_load succeeds", rc == 0);

        CHECK_NOT_NULL("interpreter.create",          api.interpreter.create);
        CHECK_NOT_NULL("interpreter.destroy",         api.interpreter.destroy);
        CHECK_NOT_NULL("interpreter.enqueue",         api.interpreter.enqueue);
        CHECK_NOT_NULL("interpreter.execute_sync",    api.interpreter.execute_sync);
        CHECK_NOT_NULL("interpreter.enable_logging",  api.interpreter.enable_logging);
        CHECK_NOT_NULL("interpreter.disable_logging", api.interpreter.disable_logging);
        CHECK_NOT_NULL("interpreter.get_error_message", api.interpreter.get_error_message);
        CHECK_NOT_NULL("script.create_from_content",  api.script.create_from_content);
        CHECK_NOT_NULL("script.destroy",              api.script.destroy);
        CHECK_NOT_NULL("set_custom_ext_init",         api.set_custom_ext_init);

        ruby_api_unload(&api);
    }

    /* --- Expected symbol linkage (from expected_symbols.cmake) --- */
    printf("\n[Expected symbol linkage]\n");
    {
        for (int i = 0; i < RGSS_EXPECTED_SYMBOL_COUNT; i++) {
            CHECK_NOT_NULL(rgss_expected_symbol_entries[i].name,
                           rgss_expected_symbol_entries[i].fn);
        }
    }

    /* --- Summary --- */
    printf("\n");
    if (failures > 0) {
        printf("FAILED: %d check(s) failed\n", failures);
        return 1;
    }
    printf("ALL CHECKS PASSED\n");
    return 0;
}
