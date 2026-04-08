# ParseDependencies.cmake
# Parses dependency .cmake files to extract download URLs, versions, and hashes.
# Designed to be included by other scripts (GenerateDockerfile.cmake, PreloadDeps.cmake).
#
# After calling parse_all_dependencies(), the following variables are set in parent scope:
#   DEP_COUNT          - Number of dependencies found
#   DEP_<i>_NAME       - Name of dependency i (0-indexed)
#   DEP_<i>_VERSION    - Version string
#   DEP_<i>_TYPE       - "url" or "git"
#   DEP_<i>_URL        - Download URL (for url type)
#   DEP_<i>_HASH       - Hash string e.g. "SHA256=..." (for url type)
#   DEP_<i>_FILENAME   - Archive filename derived from URL (for url type)
#   DEP_<i>_GIT_URL    - Git repository URL (for git type)
#   DEP_<i>_GIT_TAG    - Git tag/branch (for git type)

# Parse a single dependency .cmake file and extract variables
# Results stored in DEP_<index>_* variables in parent scope
function(parse_dependency_file FILE_PATH INDEX)
    file(READ "${FILE_PATH}" CONTENT)

    # Skip files that don't use add_external_dependency (e.g. embedded-ruby-vm uses ExternalProject_Add directly)
    string(FIND "${CONTENT}" "add_external_dependency(" HAS_ADD_DEP)
    if(HAS_ADD_DEP EQUAL -1)
        set(DEP_${INDEX}_NAME "" PARENT_SCOPE)
        return()
    endif()

    # Step 1: Extract all set(VAR "value") calls into local variables
    # Match: set(VARNAME "value") - handles both quoted and ${}-containing values
    string(REGEX MATCHALL "set\\([A-Za-z0-9_]+ \"[^\"]*\"\\)" ALL_SETS "${CONTENT}")
    foreach(S ${ALL_SETS})
        string(REGEX MATCH "set\\(([A-Za-z0-9_]+) \"([^\"]*)\"\\)" _ "${S}")
        if(CMAKE_MATCH_1)
            set(_VAR_${CMAKE_MATCH_1} "${CMAKE_MATCH_2}")
        endif()
    endforeach()

    # Step 2: Extract dependency name from add_external_dependency(NAME xxx ...)
    set(DEP_NAME "")
    string(REGEX MATCH "add_external_dependency\\([^)]*NAME[ \t\r\n]+([a-zA-Z0-9_-]+)" _ "${CONTENT}")
    if(CMAKE_MATCH_1)
        set(DEP_NAME "${CMAKE_MATCH_1}")
    else()
        # Fallback: derive from filename
        get_filename_component(DEP_NAME "${FILE_PATH}" NAME_WE)
    endif()

    # Step 3: Find version, url, hash, git vars by scanning all extracted variables
    # We look for *_VERSION, *_URL, *_HASH, *_GIT_URL, *_GIT_TAG
    # We prefer variables whose prefix matches the dependency name (e.g. LIBOGG_VERSION
    # is preferred over RUBY_MINOR_VERSION when parsing libogg.cmake)
    set(DEP_VERSION "")
    set(DEP_URL "")
    set(DEP_HASH "")
    set(DEP_GIT_URL "")
    set(DEP_GIT_TAG "")

    # Build a name prefix for prioritization (e.g. "libogg" -> "LIBOGG")
    string(TOUPPER "${DEP_NAME}" NAME_UPPER)
    string(REPLACE "-" "_" NAME_UPPER "${NAME_UPPER}")

    # First pass: collect candidates, preferring variables that start with the dep name prefix
    get_cmake_property(ALL_VARS VARIABLES)

    # Pass 1: Look for variables matching the dep name prefix (high priority)
    foreach(VAR ${ALL_VARS})
        if(NOT VAR MATCHES "^_VAR_")
            continue()
        endif()
        string(SUBSTRING "${VAR}" 5 -1 ORIG_NAME)  # Strip _VAR_ prefix

        # Only consider variables starting with the dep name prefix
        if(NOT ORIG_NAME MATCHES "^${NAME_UPPER}")
            continue()
        endif()

        if(ORIG_NAME MATCHES "_VERSION$" AND NOT DEP_VERSION)
            set(DEP_VERSION "${${VAR}}")
            set(VERSION_VAR_NAME "${ORIG_NAME}")
        elseif(ORIG_NAME MATCHES "_URL$" AND NOT ORIG_NAME MATCHES "_GIT_URL$" AND NOT DEP_URL)
            set(DEP_URL "${${VAR}}")
        elseif(ORIG_NAME MATCHES "_HASH$" AND NOT DEP_HASH)
            set(DEP_HASH "${${VAR}}")
        elseif(ORIG_NAME MATCHES "_GIT_URL$" AND NOT DEP_GIT_URL)
            set(DEP_GIT_URL "${${VAR}}")
        elseif(ORIG_NAME MATCHES "_GIT_TAG$" AND NOT DEP_GIT_TAG)
            set(DEP_GIT_TAG "${${VAR}}")
        endif()
    endforeach()

    # Pass 2: Fall back to any matching variable (for deps with non-standard naming)
    foreach(VAR ${ALL_VARS})
        if(NOT VAR MATCHES "^_VAR_")
            continue()
        endif()
        string(SUBSTRING "${VAR}" 5 -1 ORIG_NAME)  # Strip _VAR_ prefix

        if(ORIG_NAME MATCHES "_VERSION$" AND NOT DEP_VERSION)
            set(DEP_VERSION "${${VAR}}")
            set(VERSION_VAR_NAME "${ORIG_NAME}")
        elseif(ORIG_NAME MATCHES "_URL$" AND NOT ORIG_NAME MATCHES "_GIT_URL$" AND NOT DEP_URL)
            set(DEP_URL "${${VAR}}")
        elseif(ORIG_NAME MATCHES "_HASH$" AND NOT DEP_HASH)
            set(DEP_HASH "${${VAR}}")
        elseif(ORIG_NAME MATCHES "_GIT_URL$" AND NOT DEP_GIT_URL)
            set(DEP_GIT_URL "${${VAR}}")
        elseif(ORIG_NAME MATCHES "_GIT_TAG$" AND NOT DEP_GIT_TAG)
            set(DEP_GIT_TAG "${${VAR}}")
        endif()
    endforeach()

    # Step 4: Resolve ${VAR} references in URL (e.g. ${LIBOGG_VERSION} -> 1.3.4)
    if(DEP_URL AND DEP_VERSION AND VERSION_VAR_NAME)
        string(REPLACE "\${${VERSION_VAR_NAME}}" "${DEP_VERSION}" DEP_URL "${DEP_URL}")
    endif()

    # Also try resolving any remaining ${} references from our extracted variables
    string(REGEX MATCHALL "\\$\\{[A-Za-z_]+\\}" REFS "${DEP_URL}")
    foreach(REF ${REFS})
        string(REGEX MATCH "\\$\\{([A-Za-z_]+)\\}" _ "${REF}")
        set(REF_NAME "${CMAKE_MATCH_1}")
        if(DEFINED _VAR_${REF_NAME})
            string(REPLACE "${REF}" "${_VAR_${REF_NAME}}" DEP_URL "${DEP_URL}")
        endif()
    endforeach()

    # Step 5: Derive archive filename from URL
    set(DEP_FILENAME "")
    if(DEP_URL)
        # Get last path component of URL
        string(REGEX MATCH "[^/]+$" DEP_FILENAME "${DEP_URL}")
    endif()

    # Step 6: Set results in parent scope
    set(DEP_${INDEX}_NAME "${DEP_NAME}" PARENT_SCOPE)
    set(DEP_${INDEX}_VERSION "${DEP_VERSION}" PARENT_SCOPE)

    if(DEP_URL)
        set(DEP_${INDEX}_TYPE "url" PARENT_SCOPE)
        set(DEP_${INDEX}_URL "${DEP_URL}" PARENT_SCOPE)
        set(DEP_${INDEX}_HASH "${DEP_HASH}" PARENT_SCOPE)
        set(DEP_${INDEX}_FILENAME "${DEP_FILENAME}" PARENT_SCOPE)
    elseif(DEP_GIT_URL)
        set(DEP_${INDEX}_TYPE "git" PARENT_SCOPE)
        set(DEP_${INDEX}_GIT_URL "${DEP_GIT_URL}" PARENT_SCOPE)
        set(DEP_${INDEX}_GIT_TAG "${DEP_GIT_TAG}" PARENT_SCOPE)
    else()
        set(DEP_${INDEX}_TYPE "" PARENT_SCOPE)
    endif()
endfunction()

# Parse all dependency files in a directory
# Sets DEP_COUNT and DEP_<i>_* variables in parent scope
function(parse_all_dependencies DEPS_DIR)
    file(GLOB DEP_FILES "${DEPS_DIR}/*.cmake")
    list(SORT DEP_FILES)

    set(IDX 0)
    foreach(DEP_FILE ${DEP_FILES})
        parse_dependency_file("${DEP_FILE}" ${IDX})

        # Only count if we got a valid dependency
        if(DEP_${IDX}_NAME AND DEP_${IDX}_TYPE)
            # Propagate all variables to parent scope
            set(DEP_${IDX}_NAME "${DEP_${IDX}_NAME}" PARENT_SCOPE)
            set(DEP_${IDX}_VERSION "${DEP_${IDX}_VERSION}" PARENT_SCOPE)
            set(DEP_${IDX}_TYPE "${DEP_${IDX}_TYPE}" PARENT_SCOPE)
            set(DEP_${IDX}_URL "${DEP_${IDX}_URL}" PARENT_SCOPE)
            set(DEP_${IDX}_HASH "${DEP_${IDX}_HASH}" PARENT_SCOPE)
            set(DEP_${IDX}_FILENAME "${DEP_${IDX}_FILENAME}" PARENT_SCOPE)
            set(DEP_${IDX}_GIT_URL "${DEP_${IDX}_GIT_URL}" PARENT_SCOPE)
            set(DEP_${IDX}_GIT_TAG "${DEP_${IDX}_GIT_TAG}" PARENT_SCOPE)
            math(EXPR IDX "${IDX} + 1")
        endif()
    endforeach()

    set(DEP_COUNT ${IDX} PARENT_SCOPE)
endfunction()
