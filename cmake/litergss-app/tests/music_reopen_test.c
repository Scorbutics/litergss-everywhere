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
 * Only Ruby and the SFMLAudio extension are started: no standard library is
 * needed. MUSIC_FIXTURE_PATH is a short OGG file (fixtures/tone.ogg).
 */

#include <stdio.h>
#include <stdlib.h>

/* Ruby headers do not build warning-free with -Wextra */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"
#include "ruby.h"
#pragma GCC diagnostic pop

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

extern void Init_SFMLAudio(void);

static const char* CHECK_SCRIPT =
    "data = File.binread('" MUSIC_FIXTURE_PATH "')\n"
    "music = SFMLAudio::Music.new\n"
    "raise 'first open_from_memory failed' unless music.open_from_memory(data)\n"
    "raise 'second open_from_memory failed' unless music.open_from_memory(data.dup)\n"
    "raise 'no duration after reopening' unless music.get_duration > 0\n";

static VALUE init_audio(VALUE unused) {
    (void)unused;
    Init_SFMLAudio();
    return Qnil;
}

int main(int argc, char** argv) {
    int state = 0;

#ifdef __GLIBC__
    mallopt(M_MMAP_THRESHOLD, 4096);
#endif

    ruby_sysinit(&argc, &argv);
    {
        RUBY_INIT_STACK;
        ruby_init();

        rb_protect(init_audio, Qnil, &state);
        if (state == 0) rb_eval_string_protect(CHECK_SCRIPT, &state);
        if (state != 0) {
            VALUE message = rb_funcall(rb_errinfo(), rb_intern("full_message"), 0);
            printf("FAIL: %s\n", StringValueCStr(message));
            ruby_cleanup(state);
            return 1;
        }
        ruby_cleanup(0);
    }

    printf("PASS: a Music opens a second buffer\n");
    return 0;
}
