/*
 * music_reopen_test.c - SFMLAudio::Music opening a second buffer.
 *
 * A Music owns a copy of the buffer it streams from (music-owns-memory.patch).
 * Opening another buffer must keep the current copy until the new file is
 * open: sf::Music::openFromMemory first stops the current file, and stopping
 * seeks it back to the start, reading the current buffer (PSDK crashed when
 * a map changed its BGM).
 *
 * With glibc, M_MMAP_THRESHOLD makes every buffer copy a mapping of its own,
 * so a read of a released copy faults instead of reading stale heap memory.
 *
 * MUSIC_FIXTURE_PATH is a short OGG file (fixtures/tone.ogg).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "embedded-ruby-vm/assets-error.h"
#include "embedded-ruby-vm/assets-install.h"
#include "embedded-ruby-vm/log-listener.h"
#include "embedded-ruby-vm/ruby-api-loader.h"

#ifdef __GLIBC__
#include <malloc.h>
#endif

#ifndef MUSIC_FIXTURE_PATH
#error "MUSIC_FIXTURE_PATH must be defined"
#endif

/* Same glibc 2.38+ C23 redirect shims as smoke_test.c */
__attribute__((weak)) long __isoc23_strtol(const char *nptr, char **endptr, int base) {
    return strtol(nptr, endptr, base);
}
__attribute__((weak)) unsigned long __isoc23_strtoul(const char *nptr, char **endptr, int base) {
    return strtoul(nptr, endptr, base);
}

extern void initialize_litergss_extensions(void);

static void on_log(LogListener* listener, const char* message,
                   log_stream_t source, log_level_t level, int interpreter_id) {
    (void)listener;
    (void)source;
    (void)level;
    (void)interpreter_id;
    printf("[ruby] %s\n", message);
}

static const char* CHECK_SCRIPT =
    "require 'SFMLAudio'\n"
    "data = File.binread('" MUSIC_FIXTURE_PATH "')\n"
    "music = SFMLAudio::Music.new\n"
    "exit(10) unless music.open_from_memory(data)\n"
    "exit(11) unless music.open_from_memory(data.dup)\n"
    "exit(12) unless music.get_duration > 0\n";

int main(void) {
    AssetsError assets_error;
    AssetsLayout* layout = NULL;
    RubyInterpreter* vm = NULL;
    RubyAPI api;
    int result = 1;

#ifdef __GLIBC__
    mallopt(M_MMAP_THRESHOLD, 4096);
#endif

    assets_error_init(&assets_error);
    layout = assets_bootstrap("./test-ruby-install-music", &assets_error);
    if (layout == NULL) {
        printf("FAIL: bootstrap: %s\n", assets_error.message);
        return 1;
    }

    if (ruby_api_bootstrap(&api, NULL, NULL, NULL) != 0 && ruby_api_load(NULL, &api) != 0) {
        printf("FAIL: cannot load the Ruby API\n");
        assets_free_layout(layout);
        return 1;
    }
    api.set_custom_ext_init(initialize_litergss_extensions);

    LogListener listener;
    log_listener_init(&listener);
    listener.on_log_message = on_log;

    vm = api.interpreter.create(".", layout->ruby_stdlib_path, layout->native_libs_dir, listener);
    if (vm == NULL) {
        printf("FAIL: interpreter.create\n");
        goto cleanup;
    }

    RubyScript* script = api.script.create_from_content(CHECK_SCRIPT, strlen(CHECK_SCRIPT));
    int rc = api.interpreter.execute_sync(vm, script);
    api.script.destroy(script);
    if (rc != 0) {
        printf("FAIL: reopening a Music exited with %d\n", rc);
        goto cleanup;
    }

    printf("PASS: a Music opens a second buffer\n");
    result = 0;

cleanup:
    if (vm != NULL) api.interpreter.destroy(vm);
    ruby_api_unload(&api);
    assets_free_layout(layout);
    return result;
}
