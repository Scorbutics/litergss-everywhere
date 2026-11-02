/*
 * litergss-main.c
 *
 * Standalone entry point of the fat library (Linux): a `ruby` command line
 * running on the embedded runtime. An executable only has to forward main()
 * to litergss_main() (see litergss-shell.c), everything else comes from here:
 * the Ruby standard library, the extensions and the CA bundle are all
 * embedded, and extracted to the user's cache on the first start.
 *
 * Same content as embedded-ruby-vm's initialize_ruby_runtime, without its log
 * capture and communication channel: scripts own stdout and stderr. The order
 * differs: ruby_options calls Init_ext here (the VM's own call would make it run
 * twice), so our extensions come after it instead of before.
 */

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ruby.h"
#include "ruby/version.h"
#include "embedded-ruby-vm/assets-error.h"
#include "embedded-ruby-vm/assets-install.h"

/* Provided by extension-init.c */
extern void initialize_litergss_extensions(void);

#define LITERGSS_STRINGIZE_(value) #value
#define LITERGSS_STRINGIZE(value) LITERGSS_STRINGIZE_(value)
/* The directory name in the standard library: 3.0.0, 3.3.0... */
#define LITERGSS_RUBY_VERSION \
    LITERGSS_STRINGIZE(RUBY_API_VERSION_MAJOR) "." \
    LITERGSS_STRINGIZE(RUBY_API_VERSION_MINOR) "." \
    LITERGSS_STRINGIZE(RUBY_API_VERSION_TEENY)

/* One directory per Ruby variant: each would replace the other's files on every start */
static int format_install_dir(char* install_dir, size_t size)
{
    int written = snprintf(install_dir, size, "%s-" LITERGSS_RUBY_VERSION, get_default_install_dir());
    return written > 0 && (size_t) written < size ? 0 : -1;
}

/* The installer creates the last path component only: ~/.cache may not exist yet */
static int create_parent_dir(char* path)
{
    char* separator = strrchr(path, '/');
    if (separator == NULL || separator == path) {
        return 0;
    }
    *separator = '\0';
    int result = mkdir(path, 0755) == 0 || errno == EEXIST ? 0 : -1;
    *separator = '/';
    return result;
}

/* Same load path and gem layout as embedded-ruby-vm's SetupRubyEnv */
static int setup_environment(const char* install_dir)
{
    char path[3 * PATH_MAX];

    snprintf(path, sizeof(path), "%s/ruby/gems/" LITERGSS_RUBY_VERSION "/", install_dir);
    if (setenv("GEM_HOME", path, 1) != 0 || setenv("GEM_PATH", path, 1) != 0) {
        return -1;
    }
    snprintf(path, sizeof(path), "%s:%s/ruby/" LITERGSS_RUBY_VERSION "/:%s/ruby/" LITERGSS_RUBY_VERSION "/" RUBY_PLATFORM "/",
             install_dir, install_dir, install_dir);
    if (setenv("RUBYLIB", path, 1) != 0) {
        return -1;
    }

    /* Not overwritten: the caller may point them elsewhere */
    snprintf(path, sizeof(path), "%s/ruby-dist/lib/cert.pem", install_dir);
    if (setenv("SSL_CERT_FILE", path, 0) != 0) {
        return -1;
    }
    /* Where Pokemon SDK looks for its extensions and cert.pem (ruby/ruby-dist) */
    return setenv("GAMEDEPS", install_dir, 0);
}

/*
 * The files are extracted in place and the manifest written last: a second
 * start waits here, then finds them installed, instead of overwriting the
 * files the first one is loading. The lock goes with the process, even on a crash.
 */
static int lock_install_dir(const char* install_dir)
{
    char lock_path[PATH_MAX];
    int written = snprintf(lock_path, sizeof(lock_path), "%s.lock", install_dir);
    if (written <= 0 || (size_t) written >= sizeof(lock_path)) {
        errno = ENAMETOOLONG;
        return -1;
    }
    int lock_fd = open(lock_path, O_RDWR | O_CREAT | O_CLOEXEC, 0644);
    if (lock_fd >= 0 && flock(lock_fd, LOCK_EX) != 0) {
        close(lock_fd);
        return -1;
    }
    return lock_fd;
}

static int install_runtime(void)
{
    char install_dir[PATH_MAX];
    if (format_install_dir(install_dir, sizeof(install_dir)) != 0) {
        fprintf(stderr, "litergss: install directory path too long\n");
        return -1;
    }
    if (create_parent_dir(install_dir) != 0) {
        fprintf(stderr, "litergss: cannot create the parent of %s: %s\n", install_dir, strerror(errno));
        return -1;
    }

    int lock_fd = lock_install_dir(install_dir);
    if (lock_fd < 0) {
        fprintf(stderr, "litergss: cannot lock %s: %s\n", install_dir, strerror(errno));
        return -1;
    }

    AssetsError error;
    assets_error_init(&error);
    AssetsLayout* layout = assets_bootstrap(install_dir, &error);
    close(lock_fd);
    if (layout == NULL) {
        fprintf(stderr, "litergss: cannot install the runtime in %s: %s\n", install_dir, error.message);
        return -1;
    }
    assets_free_layout(layout);

    if (setup_environment(install_dir) != 0) {
        fprintf(stderr, "litergss: cannot set up the environment: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

static VALUE init_extensions(VALUE unused)
{
    (void) unused;
    initialize_litergss_extensions();
    return Qnil;
}

int litergss_main(int argc, char** argv)
{
    if (install_runtime() != 0) {
        return EXIT_FAILURE;
    }

    /* As Ruby's own main: without it the default external encoding is US-ASCII */
    setlocale(LC_CTYPE, "");

    ruby_sysinit(&argc, &argv);
    {
        RUBY_INIT_STACK;

        ruby_init();

        /* Registers Ruby's own static extensions (Init_ext), which ours need */
        void* node = ruby_options(argc, argv);

        /* Before the script runs, unless there is none: -v, a syntax error... */
        int status;
        if (ruby_executable_node(node, &status)) {
            /* A Ruby error needs a tag to land on: none is active out here */
            rb_protect(init_extensions, Qnil, &status);
            if (status != 0) {
                return ruby_cleanup(status);
            }
        }
        return ruby_run_node(node);
    }
}
