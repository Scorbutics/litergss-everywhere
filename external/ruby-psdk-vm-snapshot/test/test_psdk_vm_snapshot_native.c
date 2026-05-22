/*
 * test_psdk_vm_snapshot_native.c
 *
 * C harness that drives the Ruby minitest suite for the
 * psdk_vm_snapshot_native extension. The harness:
 *
 *   1. Bootstraps the Ruby runtime (asset extraction).
 *   2. Creates an interpreter via direct calls to the embedded-ruby-vm
 *      C API (function prototypes are forward-declared below since
 *      embedded-ruby-vm doesn't currently ship a clean public header
 *      for them).
 *   3. Reads test/test_psdk_vm_snapshot_native.rb from disk
 *      (CMake passes its absolute path via -DTEST_RUBY_SCRIPT_PATH=...).
 *   4. Executes the script synchronously and returns its exit code.
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

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "embedded-ruby-vm/log-listener.h"
#include "embedded-ruby-vm/assets-install.h"
#include "embedded-ruby-vm/assets-error.h"

/* The embedded-ruby-vm release tarball ships only public headers, and
 * ruby-interpreter.h is currently flagged private — it conflates the
 * actual public API (function prototypes below) with internal struct
 * layout. Declare the prototypes we need locally as opaque so the
 * harness can call them directly through the statically-linked fat
 * archive. If the API surface drifts, the linker will catch it.
 *
 * If embedded-ruby-vm ever splits its public/private headers cleanly
 * (function prototypes promoted to a real public header), delete this
 * block and #include the public header instead. */
typedef struct RubyInterpreter RubyInterpreter;
typedef struct RubyScript RubyScript;

extern RubyInterpreter* ruby_interpreter_create(const char* application_path,
                                                const char* ruby_base_directory,
                                                const char* native_libs_location,
                                                LogListener listener);
extern void ruby_interpreter_destroy(RubyInterpreter* interpreter);
extern int  ruby_interpreter_execute_sync(RubyInterpreter* interpreter,
                                          RubyScript* script);

extern RubyScript* ruby_script_create_from_content(const char* content, size_t length);
extern void        ruby_script_destroy(RubyScript* script);

#ifndef TEST_RUBY_SCRIPT_PATH
#  error "TEST_RUBY_SCRIPT_PATH must be set via -DTEST_RUBY_SCRIPT_PATH=..."
#endif

static FILE* g_log = NULL;

static void on_log(LogListener* listener, const char* line,
                   log_stream_t source, log_level_t level,
                   int interpreter_id) {
    (void)listener;
    (void)source;
    /* interpreter_id is informational here: the registry already routed
     * this line to us (we're registered for exactly one id). The only
     * potentially-interesting value is LOG_NATIVE_INTERPRETER_ID, which
     * tells the head-of-registry listener it's receiving a native-side
     * untagged line — this single-listener test doesn't care. */
    (void)interpreter_id;
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

    /* extension-init.c's constructor (statically linked into the fat
     * archive) has already called ruby_set_custom_ext_init with a
     * callback that runs every bundled Init_* (including ours). We
     * don't override that — doing so would skip LiteRGSS / SFMLAudio /
     * physfs initialisation. */

    LogListener listener = {
        .context = NULL,
        .user_data = NULL,
        .on_log_message = on_log,
    };

    interpreter = ruby_interpreter_create(
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

    script = ruby_script_create_from_content(script_content, script_len);
    if (!script) {
        fprintf(stderr, "Failed to create RubyScript\n");
        result = 14; goto cleanup;
    }

    /* Execute. Returns the exit code from the Ruby side — the .rb
     * file calls exit(0/1) based on Minitest.run's result. */
    result = ruby_interpreter_execute_sync(interpreter, script);

cleanup:
    if (script) ruby_script_destroy(script);
    if (interpreter) ruby_interpreter_destroy(interpreter);
    free(script_content);
    if (layout) assets_free_layout(layout);
    if (g_log) fclose(g_log);
    return result;
}
