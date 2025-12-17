# Main.cmake - Core build system initialization

# Include generic core build system modules
include(BuildHelpers)         # Generic build helpers for external dependencies
include(PlatformDetection)    # Platform and architecture detection


#[[
declare_application - Declare and configure an application build

This function sets up the complete build system for a cross-platform application
with external dependencies.

Required parameters:
  APP_NAME        - Name of the application (for logging and display)
  APP_DIR         - Directory containing application-specific configuration
  APP_DEPENDENCIES - List of dependencies to build (semicolon-separated)

Optional parameters:
  APP_VERSION     - Application version string (default: "unknown")
  APP_DESCRIPTION - Short description of the application
  PATCHES_DIR     - Custom patches directory (default: ${APP_DIR}/patches)
  DEPENDENCIES_DIR - Custom dependencies directory (default: ${APP_DIR}/dependencies)

Example usage:
  declare_application(
    APP_NAME "Ruby"
    APP_DIR "${CMAKE_SOURCE_DIR}/cmake/ruby-app"
    APP_DEPENDENCIES "ncurses;readline;gdbm;openssl;ruby"
    APP_VERSION "3.0.0"
    APP_DESCRIPTION "Ruby Programming Language"
  )
]]
function(declare_application)
    # Parse function arguments
    set(options "")
    set(oneValueArgs APP_NAME APP_DIR APP_VERSION APP_DESCRIPTION PATCHES_DIR DEPENDENCIES_DIR)
    set(multiValueArgs APP_DEPENDENCIES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Validate required arguments
    if(NOT ARG_APP_NAME)
        message(FATAL_ERROR "declare_application: APP_NAME is required")
    endif()
    if(NOT ARG_APP_DIR)
        message(FATAL_ERROR "declare_application: APP_DIR is required")
    endif()
    if(NOT ARG_APP_DEPENDENCIES)
        message(FATAL_ERROR "declare_application: APP_DEPENDENCIES is required")
    endif()

    # Set defaults for optional parameters
    if(NOT ARG_APP_VERSION)
        set(ARG_APP_VERSION "unknown")
    endif()
    if(NOT ARG_APP_DESCRIPTION)
        set(ARG_APP_DESCRIPTION "${ARG_APP_NAME} Cross-Platform Build")
    endif()
    if(NOT ARG_PATCHES_DIR)
        set(ARG_PATCHES_DIR "${ARG_APP_DIR}/patches")
    endif()
    if(NOT ARG_DEPENDENCIES_DIR)
        set(ARG_DEPENDENCIES_DIR "${ARG_APP_DIR}/dependencies")
    endif()

    # Make variables available globally
    set(APP_NAME "${ARG_APP_NAME}" PARENT_SCOPE)
    set(APP_DIR "${ARG_APP_DIR}" PARENT_SCOPE)
    set(APP_VERSION "${ARG_APP_VERSION}" PARENT_SCOPE)
    set(APP_DESCRIPTION "${ARG_APP_DESCRIPTION}" PARENT_SCOPE)
    set(APP_PATCHES_DIR "${ARG_PATCHES_DIR}" PARENT_SCOPE)
    set(APP_DEPENDENCIES_DIR "${ARG_DEPENDENCIES_DIR}" PARENT_SCOPE)
    set(APP_DEPENDENCIES "${ARG_APP_DEPENDENCIES}" PARENT_SCOPE)

    # Also set in current scope for immediate use
    set(APP_NAME "${ARG_APP_NAME}")
    set(APP_DIR "${ARG_APP_DIR}")
    set(APP_VERSION "${ARG_APP_VERSION}")
    set(APP_DESCRIPTION "${ARG_APP_DESCRIPTION}")
    set(APP_PATCHES_DIR "${ARG_PATCHES_DIR}")
    set(APP_DEPENDENCIES_DIR "${ARG_DEPENDENCIES_DIR}")
    set(APP_DEPENDENCIES "${ARG_APP_DEPENDENCIES}")

    # Project information
    message(STATUS "==========================================")
    message(STATUS "  ${ARG_APP_NAME} Cross-Platform Build System")
    if(NOT ARG_APP_VERSION STREQUAL "unknown")
        message(STATUS "  Version: ${ARG_APP_VERSION}")
    endif()
    if(ARG_APP_DESCRIPTION)
        message(STATUS "  ${ARG_APP_DESCRIPTION}")
    endif()
    message(STATUS "==========================================")

    # Load application-specific initialization (if exists)
    if(EXISTS "${ARG_APP_DIR}/Application.cmake")
        include("${ARG_APP_DIR}/Application.cmake")
    endif()

    # Load dependency configurations
    foreach(DEP ${ARG_APP_DEPENDENCIES})
        set(DEP_FILE "${ARG_DEPENDENCIES_DIR}/${DEP}.cmake")
        if(NOT EXISTS "${DEP_FILE}")
            message(FATAL_ERROR "Dependency configuration not found: ${DEP_FILE}")
        endif()
        include("${DEP_FILE}")
    endforeach()

    # Validate configuration
    include(Validation)

    # Create a top-level build target that depends on all dependency wrapper targets
    # This ensures that running 'make' builds the wrapper targets (not just the _external targets)
    # which in turn triggers any post-build steps like archive creation
    add_custom_target(app_build ALL)
    foreach(DEP ${ARG_APP_DEPENDENCIES})
        if(NOT TARGET ${DEP})
            message(FATAL_ERROR "Dependency wrapper target not found: ${DEP}")
        endif()
        add_dependencies(app_build ${DEP})
    endforeach()
    message(STATUS "Created app_build target depending on: ${ARG_APP_DEPENDENCIES}")

    # Create clean targets
    add_custom_target(clean-libs
        COMMENT "Cleaning all library build directories"
    )

    foreach(DEP ${ARG_APP_DEPENDENCIES})
        add_dependencies(clean-libs ${DEP}_clean)
    endforeach()

    add_custom_target(clean-artifacts
        COMMAND ${CMAKE_COMMAND} -E remove_directory ${BUILD_STAGING_DIR}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}
        COMMENT "Cleaning build artifacts"
    )

    add_custom_target(clean-downloads
        COMMAND ${CMAKE_COMMAND} -E remove_directory ${BUILD_DOWNLOAD_DIR}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${BUILD_DOWNLOAD_DIR}
        COMMENT "Cleaning downloaded sources"
    )

    add_custom_target(clean-cmake-files
        COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}/CMakeFiles
        COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_BINARY_DIR}/CMakeCache.txt
        COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_BINARY_DIR}/cmake_install.cmake
        COMMENT "Cleaning CMake generated files"
    )

    add_custom_target(clean-all
        DEPENDS clean-libs clean-artifacts clean-downloads
        COMMENT "Cleaning everything"
    )

    # Build directories
    message(STATUS "Build directories:")
    message(STATUS "  Downloads: ${BUILD_DOWNLOAD_DIR}")
    message(STATUS "  Staging:   ${BUILD_STAGING_DIR}")
endfunction()
