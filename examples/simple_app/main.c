/*
 * Simple LiteRGSS Application using the Fat Library
 *
 * This example demonstrates how to use the fat librgss_runtime.a library
 * in your own application. The fat library contains:
 * - Ruby runtime (libruby-static.a, libruby-ext.a)
 * - Embedded Ruby VM wrapper (libembedded-ruby.a)
 * - LiteRGSS graphics library
 * - All dependencies (SFML, OpenAL, codecs, etc.)
 *
 * Build instructions:
 *   mkdir build && cd build
 *   cmake ..
 *   make
 *   ./simple_app
 */

#include <stdio.h>
#include <string.h>

// Include the Ruby API Loader from embedded-ruby-vm
#include "embedded-ruby-vm/ruby-api-loader.h"
#include "embedded-ruby-vm/install.h"
#include "embedded-ruby-vm/assets-error.h"
#include "ruby/ruby.h"

// Extension initializer provided by LiteRGSS
// This function is compiled into the fat library
// TODO use extension-init.o from the litergss build instead
extern void Init_LiteRGSS(void);
extern void Init_SFMLAudio(void);
void initialize_litergss_extensions(void) {
    fprintf(stdout, "      - Initializing LiteRGSS extensions...\n");
    Init_LiteRGSS();
    rb_provide("LiteRGSS");
    Init_SFMLAudio();
    rb_provide("SFMLAudio");
    fprintf(stdout, "      ✓ LiteRGSS extensions initialized\n");
}

// Logging callbacks
static void on_log(LogListener* listener, const char* message) {
    printf("[Ruby] %s\n", message);
}

static void on_error(LogListener* listener, const char* message) {
    fprintf(stderr, "[Ruby Error] %s\n", message);
}

int main(int argc, char** argv) {

        
    AssetsError assets_error;
    AssetsLayout* layout = NULL;

    /* Configuration */
    const char* install_dir = "./test-ruby-install";  /* Where to extract assets */
    const char* ruby_base_dir = NULL;                 /* Will be set from layout */
    const char* execution_location = ".";             /* Working directory */
    const char* native_libs_dir = NULL;               /* Will be set from layout */


    printf("=== Bootstrapping Ruby Runtime ===\n");
    printf("Install directory: %s\n\n", install_dir);

    assets_error_init(&assets_error);
    layout = assets_bootstrap(install_dir, &assets_error);

    if (layout == NULL) {
        fprintf(stderr, "Bootstrap failed: %s\n", assets_error.message);
        if (assets_error.context[0] != '\0') {
            fprintf(stderr, "  Context: %s\n", assets_error.context);
        }
        return 1;
    }

    ruby_base_dir = layout->ruby_stdlib_path;
    native_libs_dir = layout->native_libs_dir;

    printf("✓ Bootstrap complete\n");
    printf("  Ruby stdlib: %s\n", ruby_base_dir);
    printf("  Native libs: %s\n\n", native_libs_dir);

    printf("==============================================\n");
    printf("  LiteRGSS Simple Application\n");
    printf("  Using Fat Library: librgss_runtime.a\n");
    printf("==============================================\n\n");

    // Step 1: Load the Ruby API
    // For static builds, pass NULL (the Ruby runtime is already linked in)
    printf("[1/4] Loading Ruby API...\n");
    RubyAPI api;

    // Try bootstrap first (handles both dynamic and static scenarios)
    if (ruby_api_bootstrap(&api, NULL, NULL, native_libs_dir) != 0) {
        // Fallback to direct load for static builds
        if (ruby_api_load(NULL, &api) != 0) {
            fprintf(stderr, "ERROR: Failed to load Ruby API\n");
            return 1;
        }
    }
    printf("      ✓ Ruby API loaded successfully\n\n");

    // Step 2: Register LiteRGSS Extensions
    // CRITICAL: This must be done BEFORE creating the interpreter
    printf("[2/4] Registering LiteRGSS extensions...\n");
    api.set_custom_ext_init(initialize_litergss_extensions);
    printf("      ✓ Extensions registered\n\n");

    // Step 3: Create the Ruby Interpreter
    printf("[3/4] Creating Ruby interpreter...\n");
    LogListener listener = {
        .accept = on_log,
        .on_log_error = on_error
    };

    // Create interpreter with paths
    // In production, these would point to your game's script directories
    RubyInterpreter* vm = api.interpreter.create(
        execution_location,
        ruby_base_dir,
        native_libs_dir,
        listener
    );

    if (!vm) {
        fprintf(stderr, "ERROR: Failed to create Ruby interpreter\n");
        ruby_api_unload(&api);
        return 1;
    }
    printf("      ✓ Interpreter created\n\n");

    // Step 4: Verify Extensions and Run Test Script
    printf("[4/4] Running verification script...\n\n");

    const char* test_script =
        "puts '--- Testing LiteRGSS Extensions ---'\n"
        "puts ''\n"
        "\n"
        "# Test LiteRGSS\n"
        "begin\n"
        "  require 'LiteRGSS'\n"
        "  puts '[✓] LiteRGSS loaded successfully'\n"
        "rescue LoadError => e\n"
        "  puts '[✗] Failed to load LiteRGSS: ' + e.message\n"
        "  exit(1)\n"
        "end\n"
        "\n"
        "# Test SFMLAudio\n"
        "begin\n"
        "  require 'SFMLAudio'\n"
        "  puts '[✓] SFMLAudio loaded successfully'\n"
        "rescue LoadError => e\n"
        "  puts '[✗] Failed to load SFMLAudio: ' + e.message\n"
        "  exit(1)\n"
        "end\n"
        "\n"
        "puts ''\n"
        "puts '--- All Extensions Loaded Successfully! ---'\n"
        "puts ''\n"
        "\n"
        "# Display Ruby version\n"
        "puts \"Ruby Version: #{RUBY_VERSION}\"\n"
        "puts \"Ruby Platform: #{RUBY_PLATFORM}\"\n"
        "\n"
        "puts ''\n"
        "puts 'You can now use LiteRGSS in your game!'\n";

    RubyScript* script = api.script.create_from_content(test_script, strlen(test_script));
    int result = api.interpreter.execute_sync(vm, script);

    // Cleanup
    api.script.destroy(script);
    api.interpreter.destroy(vm);
    ruby_api_unload(&api);

    printf("\n==============================================\n");
    if (result == 0) {
        printf("  SUCCESS: Application completed successfully\n");
    } else {
        printf("  FAILURE: Application exited with errors\n");
    }
    printf("==============================================\n");

    return result == 0 ? 0 : 1;
}
