/*
 * smoke_test.c - Build artifact smoke test for librgss_runtime.
 *
 * This test verifies that the combined library (fat static archive or shared
 * wrapper) is correctly assembled by:
 *   1. Calling lightweight API functions that don't need a full Ruby runtime
 *   2. Using dlsym to verify all expected symbols are present and resolvable
 *
 * This test is only compiled and run for native (non-cross-compiled) builds.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <dlfcn.h>

#include "embedded-ruby-vm/assets-error.h"
#include "embedded-ruby-vm/assets-install.h"
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

    /* --- Expected symbol linkage (from expected_symbols.cmake) --- */
    printf("\n[Expected symbol linkage]\n");
    {
        for (int i = 0; i < RGSS_EXPECTED_SYMBOL_COUNT; i++) {
            void* sym = dlsym(RTLD_DEFAULT, rgss_expected_symbol_names[i]);
            CHECK_NOT_NULL(rgss_expected_symbol_names[i], sym);
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
