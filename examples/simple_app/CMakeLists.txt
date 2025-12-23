cmake_minimum_required(VERSION 3.20)
project(LiteRGSSSimpleApp C)

set(CMAKE_C_STANDARD 11)

# Path to the fat library (adjust this to point to your build output)
# This should be the path where librgss_runtime.a is located after building litergss-everywhere
set(RGSS_RUNTIME_LIB "${CMAKE_SOURCE_DIR}/../../build/staging/usr/local/lib/librgss_runtime.a"
    CACHE FILEPATH "Path to the fat librgss_runtime.a library")

# Path to the Ruby headers (adjust this to point to your build output)
set(RGSS_INCLUDE_DIR "${CMAKE_SOURCE_DIR}/../../build/staging/usr/local/include"
    CACHE PATH "Path to the Ruby and LiteRGSS headers")

# Verify the library exists
if(NOT EXISTS "${RGSS_RUNTIME_LIB}")
    message(FATAL_ERROR
        "Fat library not found at: ${RGSS_RUNTIME_LIB}\n"
        "Please build litergss-everywhere first with BUILD_SHARED_LIBS=OFF\n"
        "Or set RGSS_RUNTIME_LIB to the correct path.")
endif()

# Create the executable
add_executable(simple_app main.c)

# Link against the fat library
# Note: On Linux, we need to use --whole-archive to ensure all symbols are included
# This is critical for Ruby extensions to work properly
if(UNIX AND NOT APPLE)
    # Find required system libraries for SFML on Linux
    find_package(X11 REQUIRED)
    find_library(UDEV_LIBRARY udev REQUIRED)

    # Verify X11 components
    if(NOT X11_Xrandr_FOUND)
        message(FATAL_ERROR "X11 RandR extension not found. Install: libxrandr-dev")
    endif()
    if(NOT X11_Xcursor_FOUND)
        message(FATAL_ERROR "X11 Xcursor extension not found. Install: libxcursor-dev")
    endif()
    if(NOT UDEV_LIBRARY)
        message(FATAL_ERROR "libudev not found. Install: libudev-dev")
    endif()

    target_link_libraries(simple_app PRIVATE
        -Wl,--whole-archive
        ${RGSS_RUNTIME_LIB}
        -Wl,--no-whole-archive
        stdc++               # C++ standard library (required by SFML)
        pthread              # Required by Ruby
        dl                   # Required for dynamic loading
        m                    # Math library
        rt                   # POSIX real-time extensions
        ${X11_LIBRARIES}     # X11 windowing system (required by SFML)
        ${X11_Xrandr_LIB}    # X11 RandR extension (screen resolution)
        ${X11_Xcursor_LIB}   # X11 cursor support
        ${UDEV_LIBRARY}      # udev for input device detection (joysticks)
    )
elseif(APPLE)
    target_link_libraries(simple_app PRIVATE
        -Wl,-force_load,${RGSS_RUNTIME_LIB}
        c++      # C++ standard library (required by SFML)
        pthread
        dl
        m
    )
else()
    # Windows or other platforms
    target_link_libraries(simple_app PRIVATE
        ${RGSS_RUNTIME_LIB}
        pthread
        ws2_32   # Windows sockets
        # C++ stdlib is linked automatically on Windows
    )
endif()

# Add include directories
target_include_directories(simple_app PRIVATE
    ${RGSS_INCLUDE_DIR}/ruby-3.1.0
    ${RGSS_INCLUDE_DIR}
)

message(STATUS "LiteRGSS Simple App Configuration:")
message(STATUS "  Fat Library: ${RGSS_RUNTIME_LIB}")
message(STATUS "  Include Dir: ${RGSS_INCLUDE_DIR}")
