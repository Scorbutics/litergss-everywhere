# verify_symbols.cmake
# Verify that expected symbols are present in the built library using nm.
#
# This is the cross-compilation fallback. For native builds the smoke test
# provides a stronger check (compile + link + run).
#
# Required variables (passed via -D):
#   VERIFY_NM           - path to the nm tool
#   VERIFY_LIBRARY      - path to the library file (.a or .so)
#   VERIFY_SYMBOLS      - semicolon-separated list of symbol names to check
#   VERIFY_LIBRARY_TYPE - "static" or "shared"

cmake_minimum_required(VERSION 3.14)

foreach(VAR VERIFY_NM VERIFY_LIBRARY VERIFY_SYMBOLS VERIFY_LIBRARY_TYPE)
    if(NOT DEFINED ${VAR})
        message(FATAL_ERROR "verify_symbols.cmake: ${VAR} is required")
    endif()
endforeach()

if(NOT EXISTS "${VERIFY_LIBRARY}")
    message(FATAL_ERROR "Library not found: ${VERIFY_LIBRARY}")
endif()

message(STATUS "Verifying symbols in ${VERIFY_LIBRARY} (${VERIFY_LIBRARY_TYPE})")

# Run nm: --defined-only filters to symbols the library actually provides.
# For shared libraries also use -D for dynamic symbols.
if(VERIFY_LIBRARY_TYPE STREQUAL "shared")
    set(_nm_flags -D --defined-only)
else()
    set(_nm_flags --defined-only)
endif()

execute_process(
    COMMAND ${VERIFY_NM} ${_nm_flags} "${VERIFY_LIBRARY}"
    OUTPUT_VARIABLE NM_OUTPUT
    ERROR_VARIABLE NM_ERROR
    RESULT_VARIABLE NM_RESULT
)

if(NOT NM_RESULT EQUAL 0)
    message(FATAL_ERROR
        "nm failed on ${VERIFY_LIBRARY}\n"
        "Exit code: ${NM_RESULT}\n"
        "stderr: ${NM_ERROR}"
    )
endif()

# Check each expected symbol.
# nm --defined-only output lines look like: "00000000 T symbol_name"
# On macOS symbols may have an underscore prefix.
set(MISSING_SYMBOLS "")
set(FOUND_COUNT 0)
list(LENGTH VERIFY_SYMBOLS TOTAL_COUNT)

foreach(SYMBOL ${VERIFY_SYMBOLS})
    # Match the symbol name at a word boundary after a type letter
    if(NM_OUTPUT MATCHES "[ \t][A-Za-z][ \t]+_?${SYMBOL}[\n;]"
       OR NM_OUTPUT MATCHES "[ \t][A-Za-z][ \t]+_?${SYMBOL}$")
        math(EXPR FOUND_COUNT "${FOUND_COUNT} + 1")
    else()
        list(APPEND MISSING_SYMBOLS "${SYMBOL}")
        message(STATUS "  MISSING: ${SYMBOL}")
    endif()
endforeach()

list(LENGTH MISSING_SYMBOLS MISSING_COUNT)
if(MISSING_COUNT GREATER 0)
    message(FATAL_ERROR
        "\nSymbol verification FAILED!\n"
        "${MISSING_COUNT}/${TOTAL_COUNT} symbols missing from ${VERIFY_LIBRARY}:\n"
        "  ${MISSING_SYMBOLS}\n"
        "\nThis means the library is incomplete and consumers will get linker errors.\n"
        "Check that all component libraries are being linked/combined correctly."
    )
endif()

message(STATUS "Symbol verification PASSED - all ${TOTAL_COUNT} symbols found")
