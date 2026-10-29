/*
 * music_reopen_test.c - SFMLAudio::Music opening a second buffer.
 *
 * A Music owns a copy of the buffer it streams from (music-owns-memory.patch).
 * Opening another buffer must keep the current copy until the new file is
 * open: sf::Music::openFromMemory first stops the current file, and stopping
 * seeks it back to the start, reading the current buffer (PSDK crashed when
 * a map changed its BGM). Freeing the Music (at ruby_cleanup) stops it too,
 * so the buffer must also outlive sf::Music's destructor.
 *
 * Built with AddressSanitizer: its memcpy interceptor reports a read of a
 * released copy, which the runtime (not instrumented) would otherwise get
 * away with, the memory still being mapped.
 *
 * Only Ruby and the SFMLAudio extension are started: no standard library is
 * needed. MUSIC_FIXTURE_PATH and MUSIC_LONGER_FIXTURE_PATH are OGG files of
 * different sizes (fixtures/tone.ogg, fixtures/tone-long.ogg): a copy of the
 * same size could reuse the current buffer in place, releasing nothing. The
 * first one is 2 s long.
 */

#include <stdio.h>
#include <stdlib.h>

#include "ruby.h"

#if !defined(MUSIC_FIXTURE_PATH) || !defined(MUSIC_LONGER_FIXTURE_PATH)
#error "MUSIC_FIXTURE_PATH and MUSIC_LONGER_FIXTURE_PATH must be defined"
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
    "music = SFMLAudio::Music.new\n"
    "raise 'first open_from_memory failed' unless music.open_from_memory(File.binread('" MUSIC_FIXTURE_PATH "'))\n"
    /* Away from the start, as a playing BGM */
    "music.set_playing_offset(1.0)\n"
    "raise 'second open_from_memory failed' unless music.open_from_memory(File.binread('" MUSIC_LONGER_FIXTURE_PATH "'))\n"
    "raise 'no duration after reopening' unless music.get_duration > 0\n";

static VALUE init_audio(VALUE unused) {
    (void)unused;
    Init_SFMLAudio();
    return Qnil;
}

int main(int argc, char** argv) {
    int state = 0;

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
