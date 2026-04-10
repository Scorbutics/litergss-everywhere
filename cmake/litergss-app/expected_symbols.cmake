# expected_symbols.cmake
# Canonical list of symbols that consumers of the rgss_runtime library need.
# Shared between: verify_symbols.cmake (cross-compiled nm check) and smoke_test
# (native link + run test) via a generated header.

set(RGSS_EXPECTED_SYMBOLS
    # embedded-ruby-vm: interpreter API
    ruby_interpreter_create
    ruby_interpreter_destroy
    ruby_interpreter_enqueue
    ruby_interpreter_execute_sync
    ruby_interpreter_enable_logging
    ruby_interpreter_disable_logging
    ruby_interpreter_get_error_message
    # embedded-ruby-vm: script API
    ruby_script_create_from_content
    ruby_script_destroy
    # embedded-ruby-vm: custom extension callback
    ruby_set_custom_ext_init
    # embedded-ruby-vm: assets API
    assets_bootstrap
    assets_get_layout
    assets_free_layout
    assets_validate_layout
    install_embedded_files
    installation_needed
    assets_register_native_libs
    assets_error_init
    assets_error_string
    get_default_install_dir
    set_android_app_data_dir
    # LiteRGSS extensions
    Init_LiteRGSS
    Init_SFMLAudio
)

# Generate rgss_expected_symbols.h in the build directory.
# This header provides:
#   - extern declarations for every expected symbol
#   - RGSS_EXPECTED_SYMBOL_COUNT
#   - rgss_expected_symbol_entries[] array for iteration
function(rgss_generate_expected_symbols_header OUTPUT_DIR)
    set(_header "${OUTPUT_DIR}/rgss_expected_symbols.h")

    list(LENGTH RGSS_EXPECTED_SYMBOLS _count)

    set(_content
"/* Auto-generated from expected_symbols.cmake -- do not edit */
#ifndef RGSS_EXPECTED_SYMBOLS_H
#define RGSS_EXPECTED_SYMBOLS_H

#define RGSS_EXPECTED_SYMBOL_COUNT ${_count}

typedef struct {
    const char* name;
    void (*fn)(void);
} RgssExpectedSymbol;

/*
 * Returns a static table of all expected symbols with their addresses.
 * Uses block-scope extern declarations to avoid conflicts with any
 * API headers that declare these symbols with their real signatures.
 */
static inline const RgssExpectedSymbol* rgss_expected_symbols(void) {
")

    # Block-scope extern declarations -- these are legal C and never
    # conflict with file-scope declarations that have different signatures.
    foreach(_sym ${RGSS_EXPECTED_SYMBOLS})
        string(APPEND _content "    extern void ${_sym}();\n")
    endforeach()

    string(APPEND _content "
    static const RgssExpectedSymbol table[] = {
")

    foreach(_sym ${RGSS_EXPECTED_SYMBOLS})
        string(APPEND _content "        { \"${_sym}\", (void(*)(void))${_sym} },\n")
    endforeach()

    string(APPEND _content "    };
    return table;
}

#endif /* RGSS_EXPECTED_SYMBOLS_H */
")

    file(WRITE "${_header}" "${_content}")
    message(STATUS "Generated ${_header} (${_count} symbols)")
endfunction()
