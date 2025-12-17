# ValidateConfiguration.cmake
# Validates that all required CMake variables have been set by the platform configuration
# This ensures the build system is properly initialized before proceeding

message(STATUS "==========================================")
message(STATUS "Validating build configuration...")
message(STATUS "==========================================")

# Define required variables that MUST be set by platform modules
set(REQUIRED_VARIABLES
    TARGET_PLATFORM
    TARGET_ARCH
    HOST_TRIPLET
    HOST_SHORT
    BUILD_ENV
    BUILD_DOWNLOAD_DIR
    BUILD_STAGING_DIR
    PLATFORM_INITIALIZED
)

# Define optional but recommended variables
set(RECOMMENDED_VARIABLES
    CFLAGS
    LDFLAGS
)

# Track validation status
set(VALIDATION_FAILED FALSE)
set(MISSING_VARIABLES "")

# Check required variables
foreach(VAR ${REQUIRED_VARIABLES})
    if(NOT DEFINED ${VAR})
        list(APPEND MISSING_VARIABLES ${VAR})
        set(VALIDATION_FAILED TRUE)
        message(SEND_ERROR "REQUIRED variable not set: ${VAR}")
    else()
        # Variable is set, provide feedback
        message(STATUS "  ${VAR}: ${${VAR}}")
    endif()
endforeach()

# Check recommended variables (warnings only)
foreach(VAR ${RECOMMENDED_VARIABLES})
    if(NOT DEFINED ${VAR})
        message(WARNING "Recommended variable not set: ${VAR}")
    else()
        message(STATUS "  ${VAR}: ${${VAR}}")
    endif()
endforeach()

# Additional platform-specific validation
if(TARGET_PLATFORM STREQUAL "Android")
    # Android-specific required variables
    set(ANDROID_REQUIRED
        CMAKE_ANDROID_NDK
        ANDROID_PLATFORM
        ANDROID_ABI
    )
    
    foreach(VAR ${ANDROID_REQUIRED})
        if(NOT DEFINED ${VAR})
            list(APPEND MISSING_VARIABLES ${VAR})
            set(VALIDATION_FAILED TRUE)
            message(SEND_ERROR "REQUIRED Android variable not set: ${VAR}")
        else()
            message(STATUS "  ${VAR}: ${${VAR}}")
        endif()
    endforeach()
endif()

# Validate that build directories exist
if(NOT EXISTS "${BUILD_DOWNLOAD_DIR}")
    message(SEND_ERROR "Download directory does not exist: ${BUILD_DOWNLOAD_DIR}")
    set(VALIDATION_FAILED TRUE)
endif()

if(NOT EXISTS "${BUILD_STAGING_DIR}")
    message(SEND_ERROR "Staging directory does not exist: ${BUILD_STAGING_DIR}")
    set(VALIDATION_FAILED TRUE)
endif()

# Validate that dependencies are defined
if(NOT DEFINED APP_DEPENDENCIES)
    message(WARNING "APP_DEPENDENCIES not set - no libraries will be built")
elseif(NOT APP_DEPENDENCIES)
    message(WARNING "APP_DEPENDENCIES is empty - no libraries will be built")
else()
    message(STATUS "  APP_DEPENDENCIES: ${APP_DEPENDENCIES}")
endif()

# Final validation result
message(STATUS "==========================================")
if(VALIDATION_FAILED)
    message(FATAL_ERROR "Configuration validation FAILED!\n"
                        "Missing required variables: ${MISSING_VARIABLES}\n"
                        "Please check your platform configuration in cmake/platforms/${TARGET_PLATFORM}.cmake")
endif()
message(STATUS "==========================================")
