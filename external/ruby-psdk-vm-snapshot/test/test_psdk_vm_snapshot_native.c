/*
 * test_psdk_vm_snapshot_native.c
 *
 * C harness that drives the Ruby minitest suite for the
 * psdk_vm_snapshot_native extension. The harness:
 *
 *   1. Bootstraps the Ruby runtime (asset extraction → API load).
 *   2. Reads test/test_psdk_vm_snapshot_native.rb from disk
 *      (CMake passes its absolute path via -DTEST_RUBY_SCRIPT_PATH=...).
 *   3. Executes the script synchronously and returns its exit code.
 *
 * Registration of Init_psdk_vm_snapshot_native + rb_provide is handled
 * by extension-init.c's __attribute__((constructor)) auto-register,
 * which is statically linked into the fat library we depend on. So we
 * don't call ruby_set_custom_ext_init here — doing so would *replace*
 * the constructor's callback and skip initialising LiteRGSS / SFMLAudio
 * / physfs alongside our extension.
 *
 * The .rb file uses minitest directly and exits with Minitest.run's
 * status — see the file's tail comment for why we don't use the
 * usual `require 'minitest/autorun'` form.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Always use the shared loader. The static variant transitively
 * includes private headers (embedded-ruby-vm/ruby-interpreter.h,
 * ruby-script.h) that aren't shipped in the embedded-ruby-vm release
 * tarball — the prebuilt archive only ships public headers. The shared
 * loader resolves the API via dlsym at runtime; combined with the
 * test binary's -rdynamic flag, statically-linked symbols in the fat
 * archive are visible via dlopen(NULL), and shared-build symbols come
 * in through rgss_runtime.so's normal dynamic load. One code path,
 * both link modes. */
#include "embedded-ruby-vm/shared/ruby-api-loader.h"
#include "embedded-ruby-vm/assets-install.h"
#include "embedded-ruby-vm/assets-error.h"

#ifndef TEST_RUBY_SCRIPT_PATH
#  error "TEST_RUBY_SCRIPT_PATH must be set via -DTEST_RUBY_SCRIPT_PATH=..."
#endif

static FILE* g_log = NULL;

static void on_log(LogListener* listener, const char* line,
                   log_stream_t source, log_level_t level) {
    (void)listener;
    (void)source;
    const char* prefix = (level == LOG_LEVEL_ERROR) ? "[Ruby Error]" : "[Ruby]";
    fprintf(stderr, "%s %s\n", prefix, line);
    if (g_log) {
        fprintf(g_log, "%s %s\n", prefix, line);
        fflush(g_log);
    }
}

/* Read a text file into a freshly-malloc'd NUL-terminated buffer.
 * Returns NULL on error; caller owns the buffer. */
static char* read_file(const char* path, size_t* out_len) {
    FILE* f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "Failed to open test script: %s\n", path);
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long size = ftell(f);
    if (size < 0) { fclose(f); return NULL; }
    if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return NULL; }

    char* buf = (char*)malloc((size_t)size + 1);
    if (!buf) { fclose(f); return NULL; }

    size_t got = fread(buf, 1, (size_t)size, f);
    fclose(f);
    if (got != (size_t)size) { free(buf); return NULL; }
    buf[size] = '\0';
    if (out_len) *out_len = (size_t)size;
    return buf;
}

int main(int argc, char* argv[]) {
    (void)argc; (void)argv;

    int result = 0;
    RubyAPI api;
    AssetsError assets_error;
    AssetsLayout* layout = NULL;
    RubyInterpreter* interpreter = NULL;
    RubyScript* script = NULL;
    char* script_content = NULL;
    size_t script_len = 0;

    g_log = fopen("test_psdk_vm_snapshot_native.log", "w");

    /* Bootstrap Ruby runtime (extract stdlib, load native libs). */
    assets_error_init(&assets_error);
    layout = assets_bootstrap("./test-psdk-vm-snapshot-install", &assets_error);
    if (!layout) {
        fprintf(stderr, "Bootstrap failed: %s\n", assets_error.message);
        result = 10; goto cleanup;
    }

    /* Resolve API symbols. dlopen(NULL) returns a handle whose symbol
     * scope covers the main executable plus everything dynamically
     * linked into it — works for both link modes:
     *   - static: the fat archive's symbols are in the executable's
     *     own object code, exported via -rdynamic.
     *   - shared: rgss_runtime.so is a dynamic dep of the executable,
     *     so its symbols are reachable via the main-program handle.
     * We don't go through ruby_api_bootstrap because it requires a
     * concrete .so path (which doesn't exist for static builds). */
    if (ruby_api_load(NULL, &api) != 0) {
        fprintf(stderr, "ruby_api_load(NULL) failed\n");
        result = 11; goto cleanup;
    }

    /* extension-init.c's constructor has already called
     * api.set_custom_ext_init() with a callback that runs every bundled
     * Init_* (including ours). Don't overwrite that. */

    LogListener listener = {
        .context = NULL,
        .user_data = NULL,
        .on_log_message = on_log,
    };

    interpreter = api.interpreter.create(
        ".",                       /* execution_location */
        layout->ruby_stdlib_path,  /* ruby_base_dir */
        layout->native_libs_dir,   /* native_libs_dir */
        listener
    );
    if (!interpreter) {
        fprintf(stderr, "Failed to create Ruby interpreter\n");
        result = 12; goto cleanup;
    }

    /* Load the minitest script content. */
    script_content = read_file(TEST_RUBY_SCRIPT_PATH, &script_len);
    if (!script_content) {
        result = 13; goto cleanup;
    }

    script = api.script.create_from_content(script_content, script_len);
    if (!script) {
        fprintf(stderr, "Failed to create RubyScript\n");
        result = 14; goto cleanup;
    }

    /* Execute. Returns the exit code from the Ruby side — we wrote the
     * .rb to call exit(0/1) based on Minitest.run's result. */
    result = api.interpreter.execute_sync(interpreter, script);

cleanup:
    if (script) api.script.destroy(script);
    if (interpreter) api.interpreter.destroy(interpreter);
    free(script_content);
    if (layout) assets_free_layout(layout);
    if (g_log) fclose(g_log);
    return result;
}
