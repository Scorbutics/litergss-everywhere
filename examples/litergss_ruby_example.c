/*
 * litergss_ruby_example.c
 *
 * Example of integrating LiteRGSS with the Embedded Ruby VM using the callback mechanism.
 *
 * This demonstrates how a game engine would initialize Ruby and the LiteRGSS extensions.
 */

#include <stdio.h>
#include <string.h>

// Include the Ruby API Loader (from embedded-ruby-vm)
// In a real project, point this to where the header is installed
#include "ruby-api-loader.h"
#include "install.h"
#include "assets-error.h"

// Forward declaration of the extension initializer
// This is provided by the compiled LiteRGSS library (extension-init.o in the archive)
//extern void initialize_litergss_extensions(void);

// TODO use extension-init.o from the litergss build instead
extern void Init_LiteRGSS(void);
extern void Init_SFMLAudio(void);
void initialize_litergss_extensions(void) {
    Init_LiteRGSS();
    Init_SFMLAudio();
}


// Log callback
static void on_log(LogListener* listener, const char* message) {
    printf("[Ruby] %s\n", message);
}

static void on_error(LogListener* listener, const char* message) {
    fprintf(stderr, "[Ruby Error] %s\n", message);
}

int main(int argc, char** argv) {
    printf("Initializing LiteRGSS Environment...\n");
    
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

    // 1. Load the Ruby API
    // For static builds, we pass NULL. For dynamic, we might pass the path to .so
    RubyAPI api;
    if (ruby_api_bootstrap(&api, NULL, NULL, NULL) != 0) {
        // Fallback for purely static build where bootstrap might not be needed/available in same way
        // or just direct load if bootstrap fails checking dynamic paths
        if (ruby_api_load(NULL, &api) != 0) {
            fprintf(stderr, "Failed to load Ruby API\n");
            return 1;
        }
    }

    // 2. Register the Custom Extension Callback
    // CRITICAL: This must be done BEFORE creating the interpreter
    printf("Registering LiteRGSS extensions callback...\n");
    api.set_custom_ext_init(initialize_litergss_extensions);

    // 3. Create the Interpreter
    LogListener listener = { .accept = on_log, .on_log_error = on_error };
    
    // Paths would typically be relative to the executable or in a standard location
    RubyInterpreter* vm = api.interpreter.create(".", "./ruby", "./lib", listener);

    if (!vm) {
        fprintf(stderr, "Failed to create Ruby interpreter\n");
        return 1;
    }

    // 4. Verify Extensions are Available
    printf("Executing verification script...\n");
    const char* check_script = 
        "begin\n"
        "  require 'LiteRGSS'\n"
        "  puts 'SUCCESS: LiteRGSS loaded!'\n"
        "  require 'SFMLAudio'\n"
        "  puts 'SUCCESS: SFMLAudio loaded!'\n"
        "  \n"
        "  # Print some info if possible (assuming LiteRGSS has some constants)\n"
        "  # puts \"LiteRGSS Version: #{LiteRGSS::VERSION}\" rescue puts 'No Version constant'\n"
        "rescue LoadError => e\n"
        "  puts \"FAILURE: Could not load extension: #{e.message}\"\n"
        "  exit(1)\n"
        "rescue Exception => e\n"
        "  puts \"FAILURE: #{e.message}\"\n"
        "  exit(1)\n"
        "end\n";

    RubyScript* script = api.script.create_from_content(check_script, strlen(check_script));
    int result = api.interpreter.execute_sync(vm, script);

    api.script.destroy(script);
    api.interpreter.destroy(vm);
    ruby_api_unload(&api);

    return result == 0 ? 0 : 1;
}
