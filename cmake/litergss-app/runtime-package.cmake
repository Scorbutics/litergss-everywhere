# runtime-package.cmake
# The runtime the application links: the fat librgss_runtime.a (or the shared
# rgss_runtime), the distribution archive, the symbol check and the native
# smoke tests. Shared by the engines (dependencies/litergss2.cmake,
# dependencies/litergss3.cmake), which set before including it:
#
#   RGSS_ENGINE                 the engine's dependency target (litergss2, litergss3)
#   RGSS_ENGINE_FAT_LIBS        the engine's static libraries and what they link,
#                               combined into librgss_runtime.a ahead of Ruby's
#   RGSS_ENGINE_SHARED_LIBS     the same, as linked by the shared wrapper
#                               (BUILD_SHARED_WRAPPER)
#   RGSS_ENGINE_SHARED_DEPENDS  dependency targets the shared wrapper waits for

# ============================================================================
# FINAL OUTPUT
# ============================================================================

# ============================================================================
# EXPECTED SYMBOLS (shared between nm verify and smoke test)
# ============================================================================
include(${CMAKE_SOURCE_DIR}/cmake/litergss-app/expected_symbols.cmake)
# AUDIO_EXT_NAME, for the music test
include(${CMAKE_SOURCE_DIR}/cmake/litergss-app/ruby-extension-names.cmake)
set(VERIFY_SYMBOLS_SCRIPT "${CMAKE_SOURCE_DIR}/cmake/litergss-app/scripts/verify_symbols.cmake")

# Generate the header so smoke_test.c can verify all symbols at link+run time
rgss_generate_expected_symbols_header("${CMAKE_BINARY_DIR}/generated")

# Detect whether we can run built binaries on this host.
# CMAKE_CROSSCOMPILING is TRUE whenever CMAKE_SYSTEM_NAME is set explicitly
# (even for native builds like x86_64-linux on an x86_64-linux host), so we
# also check whether host and target actually match.
set(_RGSS_CAN_RUN_TESTS FALSE)
if(NOT CMAKE_CROSSCOMPILING)
    set(_RGSS_CAN_RUN_TESTS TRUE)
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL CMAKE_SYSTEM_NAME
       AND CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL CMAKE_SYSTEM_PROCESSOR)
    set(_RGSS_CAN_RUN_TESTS TRUE)
endif()

# Ruby client code (ruby/litergss): liblitergss_ruby_client.a, linked below
include(${CMAKE_CURRENT_LIST_DIR}/ruby-client.cmake)

if(BUILD_SHARED_WRAPPER)
    # ------------------------------------------------------------------------
    # SHARED WRAPPER MODE (rgss_runtime.so)
    # ------------------------------------------------------------------------
    message(STATUS "LiteRGSS: Configuring shared wrapper build (rgss_runtime)")
    
    # Create the shared library target
    add_library(rgss_runtime SHARED ${CMAKE_CURRENT_LIST_DIR}/dependencies/files/dummy.c)

    # The engine's extension is always a static library; the other
    # dependencies follow BUILD_SHARED_LIBS (RGSS_ENGINE_SHARED_LIBS).

    if(BUILD_SHARED_LIBS)
        set(DEP_EXT "so")
    else()
        set(DEP_EXT "a")
    endif()

    # Define the list of library files to link
    # Using full paths to staging dir
    set(LIBS_TO_LINK
        ${RGSS_ENGINE_SHARED_LIBS}
        "${LITERGSS_RUBY_CLIENT_LIB}"
    )
    
    # embedded-ruby-vm libraries
    # Since we used add_subdirectory, we can access targets or files directly.
    # But for safety and consistency with "combining into dynamic library", we should link the artifacts.
    # target_link_libraries(rgss_runtime embedded-ruby) would work if embedded-ruby encapsulates everything.
    # But we want to bundle everything.
    
    if(UNIX AND NOT APPLE AND NOT BUILD_SHARED_LIBS)
        # Linux Static Link -> Shared Lib: Use --whole-archive
        target_link_libraries(rgss_runtime PRIVATE
            -Wl,--whole-archive
            embedded-ruby # Is a target, CMake resolves it
            ${LIBS_TO_LINK}
            -Wl,--no-whole-archive
        )
    else()
        # Shared dependencies or non-Linux: Normal linking
        target_link_libraries(rgss_runtime PRIVATE
            embedded-ruby
            ${LIBS_TO_LINK}
        )
    endif()

    # Add dependencies ensuring they are built before linking
    add_dependencies(rgss_runtime
        litergss_ruby_client
        ${RGSS_ENGINE}
        ${RGSS_ENGINE_SHARED_DEPENDS}
    )
    
    # We also need rubysfml-audio if used
    # Assuming it is part of the request (not explicitly listed but usually required)
    # If so, add it to LIBS_TO_LINK
    
    install(TARGETS rgss_runtime DESTINATION lib)
    # No separate symbol verification needed: if a symbol is missing,
    # the shared library link above will fail with an unresolved reference.

    # Bridge variables for the smoke test section below
    set(RGSS_SMOKE_TEST_ENABLED TRUE)
    set(RGSS_SMOKE_TEST_LINK_MODE "shared")

else()
    # ------------------------------------------------------------------------
    # ARCHIVE MODE (Static Wrapper / Archive)
    # ------------------------------------------------------------------------
    # Create final application archive containing all LiteRGSS components
    set(LITERGSS_ARCHIVE_NAME "litergss-${PLATFORM_LOWER}-${TARGET_ARCH}.zip")

    # Include appropriate library files based on BUILD_SHARED_LIBS
    if(BUILD_SHARED_LIBS)
        set(LITERGSS_LIB_EXTENSION "so")
    else()
        set(LITERGSS_LIB_EXTENSION "a")
    endif()

    # Prepare Ruby runtime files for packaging
    # Copy Ruby libraries from embedded-ruby-vm to staging directory
    file(MAKE_DIRECTORY "${BUILD_STAGING_DIR}/usr/local/lib/ruby")
    file(GLOB RUBY_LIBS "${EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS}/libruby*.${LITERGSS_LIB_EXTENSION}*")
    file(GLOB RUBY_DEPS "${EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS}/lib*.${LITERGSS_LIB_EXTENSION}*")
    foreach(lib ${RUBY_LIBS} ${RUBY_DEPS})
        file(COPY ${lib} DESTINATION "${BUILD_STAGING_DIR}/usr/local/lib/ruby/")
    endforeach()

    # Ruby's headers are already in the staging prefix, as consumers want
    # them (ruby-for-android.cmake: usr/local/include/ruby-<ABI>/ruby/). No
    # copy of EMBEDDED_RUBY_VM_INCLUDE_DIRS here: those are that staging
    # directory, and copying its ruby/ into ruby-<ABI>/ (which a reconfigure
    # did) put Ruby's assert.h where <cassert> finds it first.
    file(MAKE_DIRECTORY "${BUILD_STAGING_DIR}/usr/local/include")

    # ========================================================================
    # Create "fat" static library combining all dependencies
    # ========================================================================
    if(NOT BUILD_SHARED_LIBS)
        include(${CMAKE_SOURCE_DIR}/cmake/core/CombineFatLibrary.cmake)

        # Configurable fat library name (default: rgss_runtime)
        set(FAT_LIBRARY_NAME "rgss_runtime" CACHE STRING "Name of the fat library (without lib prefix or extension)")
        
        # Ruby names the static lib differently per platform:
        #   Linux/Android: libruby-static.a
        #   iOS/macOS:     libruby.3.1-static.a (versioned)
        file(GLOB _ruby_static_candidates
            "${BUILD_STAGING_DIR}/usr/local/lib/libruby*-static.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libruby.a"
        )
        list(FILTER _ruby_static_candidates EXCLUDE REGEX "libruby-ext")
        if(_ruby_static_candidates)
            list(GET _ruby_static_candidates 0 RUBY_STATIC_LIB)
        else()
            set(RUBY_STATIC_LIB "${BUILD_STAGING_DIR}/usr/local/lib/libruby-static.a")
        endif()

        # Define the list of static libraries to combine
        set(STATIC_LIBS_TO_COMBINE
            # The engine and what it links (dependencies/litergss2.cmake / litergss3.cmake)
            ${RGSS_ENGINE_FAT_LIBS}
            # Ruby's dependencies (non-debug variants only, no _g versions)
            # Make sure the libruby-ext.a goes first because it will define Init_ext, as libruby-static.a does,
            # and we only keep the first found symbol in case of duplicates.
            "${BUILD_STAGING_DIR}/usr/local/lib/libruby-ext.a"
            "${RUBY_STATIC_LIB}"
            "${BUILD_STAGING_DIR}/usr/local/lib/libreadline.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libncurses.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libpanel.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libmenu.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libform.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libgdbm.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libgdbm_compat.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libssl.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libcrypto.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libgmp.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libffi.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libcrypt.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libbsd.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libmd.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libz.a"
            # Final libs
            "${BUILD_STAGING_DIR}/usr/local/lib/libminizip.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libassets.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libembedded-ruby.a"
            "${LITERGSS_RUBY_CLIENT_LIB}"
        )

        set(FAT_LIBRARY_OUTPUT "${BUILD_STAGING_DIR}/usr/local/lib/lib${FAT_LIBRARY_NAME}.a")
        set(FAT_LIBRARY_WORKDIR "${CMAKE_BINARY_DIR}/fat_library_workdir")

        # Runs on every build; the script skips the merge when the fat library
        # is newer than all of its inputs. A custom command OUTPUT depending on
        # the dependency targets alone never re-ran once the library existed,
        # so a rebuilt dependency (new SFML pin...) didn't reach it.
        add_custom_target(rgss_fat_library ALL
            COMMAND ${CMAKE_COMMAND}
                -DCOMBINE_OUTPUT=${FAT_LIBRARY_OUTPUT}
                -DCOMBINE_WORKDIR=${FAT_LIBRARY_WORKDIR}
                -DCOMBINE_AR=${CMAKE_AR}
                -DCOMBINE_RANLIB=${CMAKE_RANLIB}
                -DCOMBINE_NM=${CMAKE_NM}
                -DCOMBINE_OBJCOPY=${CMAKE_OBJCOPY}
                "-DCOMBINE_LIBS=${STATIC_LIBS_TO_COMBINE}"
                -P ${CMAKE_SOURCE_DIR}/cmake/core/CombineFatLibraryScript.cmake
            BYPRODUCTS ${FAT_LIBRARY_OUTPUT}
            COMMENT "Creating fat static library lib${FAT_LIBRARY_NAME}.a (if its inputs changed)"
            VERBATIM
        )
        add_dependencies(rgss_fat_library ${RGSS_ENGINE}_external ${RGSS_AUDIO_DEPENDENCY}_external litergss_ruby_client)

        # Verify symbols are present in the fat static library.
        # For native builds the smoke test provides a stronger check
        # (compile + link + run), so the nm fallback is only needed
        # when we cannot run built binaries.
        if(NOT _RGSS_CAN_RUN_TESTS)
            add_custom_command(
                TARGET rgss_fat_library POST_BUILD
                COMMAND ${CMAKE_COMMAND}
                    -DVERIFY_NM=${CMAKE_NM}
                    -DVERIFY_LIBRARY=${FAT_LIBRARY_OUTPUT}
                    "-DVERIFY_SYMBOLS=${RGSS_EXPECTED_SYMBOLS}"
                    -DVERIFY_LIBRARY_TYPE=static
                    -P ${VERIFY_SYMBOLS_SCRIPT}
                COMMENT "Verifying symbols in lib${FAT_LIBRARY_NAME}.a (cross-compile nm check)"
                VERBATIM
            )
        endif()

        # Bridge variables for the smoke test section below
        set(RGSS_SMOKE_TEST_ENABLED TRUE)
        set(RGSS_SMOKE_TEST_LINK_MODE "static")

        # Add clean target for fat library
        add_custom_target(rgss_fat_library_clean
            COMMAND ${CMAKE_COMMAND} -E rm -f ${FAT_LIBRARY_OUTPUT}
            COMMAND ${CMAKE_COMMAND} -E rm -rf ${JNI_OUTPUT_DIR}
            COMMENT "Cleaning fat library and JNI output directories"
        )

        # Copy fat library to JNI structure for Android integration
        if(TARGET_PLATFORM STREQUAL "android")
            if(TARGET_ARCH STREQUAL "arm64")
                set(ANDROID_ABI "arm64-v8a")
            elseif(TARGET_ARCH STREQUAL "x86_64")
                set(ANDROID_ABI "x86_64")
            elseif(TARGET_ARCH STREQUAL "x86")
                set(ANDROID_ABI "x86")
            elseif(TARGET_ARCH STREQUAL "arm")
                set(ANDROID_ABI "armeabi-v7a")
            endif()
            
            set(JNI_OUTPUT_DIR "${CMAKE_BINARY_DIR}/jni-libs")
            set(JNI_ABI_DIR "${JNI_OUTPUT_DIR}/${ANDROID_ABI}")
            
            add_custom_command(
                TARGET rgss_fat_library POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E make_directory ${JNI_ABI_DIR}
                COMMAND ${CMAKE_COMMAND} -E copy ${FAT_LIBRARY_OUTPUT} ${JNI_ABI_DIR}/
                COMMENT "Copying fat library to JNI directory: ${JNI_ABI_DIR}"
            )
            
            message(STATUS "Fat library will be copied to: ${JNI_ABI_DIR}/lib${FAT_LIBRARY_NAME}.a")
        endif()

        message(STATUS "Fat library configuration:")
        message(STATUS "  Name: lib${FAT_LIBRARY_NAME}.a")
        message(STATUS "  Output: ${FAT_LIBRARY_OUTPUT}")
    endif()

    # Create distribution archive with headers and library
    if(NOT BUILD_SHARED_LIBS)
        # Static library build - include fat library in archive
        create_archive_target(
            NAME litergss_archive
            OUTPUT ${LITERGSS_ARCHIVE_NAME}
            INCLUDES
                usr/local/include/SFML/
                usr/local/include/ruby-${RUBY_MINOR_VERSION}/
                usr/local/include/
                usr/local/lib/lib${FAT_LIBRARY_NAME}.a
            DEPENDS ${RGSS_ENGINE}_external embedded-ruby-vm rgss_fat_library
        )
        add_dependencies(${RGSS_ENGINE} litergss_archive rgss_fat_library)
    else()
        # Shared library build - include .so files in archive
        create_archive_target(
            NAME litergss_archive
            OUTPUT ${LITERGSS_ARCHIVE_NAME}
            INCLUDES
                usr/local/include/SFML/
                usr/local/include/ruby-${RUBY_MINOR_VERSION}/
                usr/local/include/
                usr/local/lib/
            DEPENDS ${RGSS_ENGINE}_external embedded-ruby-vm
        )
        add_dependencies(${RGSS_ENGINE} litergss_archive)
    endif()

    message(STATUS "${RGSS_ENGINE} configured - archive will be: ${LITERGSS_ARCHIVE_NAME}")
endif()

# ============================================================================
# SMOKE TEST (native builds only)
# ============================================================================
# When we can run the built binary, compile and run a smoke test against the
# output library to verify the build artifact is functional, not just symbol-complete.
if(RGSS_SMOKE_TEST_ENABLED AND _RGSS_CAN_RUN_TESTS)
    # enable_testing() is called by the top-level CMakeLists.txt
    # Native test executables linked against the output library like an app
    function(rgss_add_native_test name src)
        add_executable(${name} ${src})

        # Same include paths as extension-init.c compilation (see embedded-ruby-vm.cmake)
        target_include_directories(${name} PRIVATE
            "${CMAKE_BINARY_DIR}/generated"
            "${BUILD_STAGING_DIR}/usr/local/include"
        )
        target_compile_options(${name} PRIVATE -Wall -Wextra -Werror)

        # Export symbols so dlsym(RTLD_DEFAULT, ...) can find them in the executable
        if(APPLE)
            target_link_options(${name} PRIVATE -Wl,-export_dynamic)
        else()
            target_link_options(${name} PRIVATE -rdynamic)
        endif()

        if(RGSS_SMOKE_TEST_LINK_MODE STREQUAL "shared")
            # Shared wrapper: link against the CMake target directly
            target_link_libraries(${name} PRIVATE rgss_runtime)
            add_dependencies(${name} rgss_runtime)
        elseif(RGSS_SMOKE_TEST_LINK_MODE STREQUAL "static")
            # Fat static library, linked whole like an app does (INTEGRATION.md):
            # dlsym finds every expected symbol, not only the referenced ones.
            # System deps are needed because the static archive doesn't resolve them.
            if(APPLE)
                set(_rgss_fat_library_link "-Wl,-force_load,${FAT_LIBRARY_OUTPUT}")
            else()
                set(_rgss_fat_library_link -Wl,--whole-archive "${FAT_LIBRARY_OUTPUT}" -Wl,--no-whole-archive)
            endif()
            # The archive holds C++ (SFML, LiteCGSS): link with the C++ runtime
            set_target_properties(${name} PROPERTIES LINKER_LANGUAGE CXX)
            find_package(Threads REQUIRED)
            target_link_libraries(${name} PRIVATE
                ${_rgss_fat_library_link}
                Threads::Threads
                ${CMAKE_DL_LIBS}
                m
            )
            if(APPLE)
                find_package(OpenGL REQUIRED)
                target_link_libraries(${name} PRIVATE
                    OpenGL::GL
                    "-framework Cocoa"
                    "-framework IOKit"
                    "-framework CoreFoundation"
                    "-framework CoreVideo"
                    "-framework Carbon"
                    "-framework Security"  # Ruby 3.0: SecRandomCopyBytes
                    "-framework CoreAudio"     # OpenAL Soft's / miniaudio's CoreAudio backend
                    "-framework AudioToolbox"
                    compression
                    iconv
                    bz2  # FreeType's bzip2 support
                )
            else()
                find_package(X11 REQUIRED)
                find_package(OpenGL REQUIRED)
                target_link_libraries(${name} PRIVATE
                    ${X11_LIBRARIES}
                    ${X11_Xrandr_LIB}
                    ${X11_Xcursor_LIB}
                    OpenGL::GL
                    udev
                )
            endif()
            add_dependencies(${name} rgss_fat_library)
        endif()
        add_test(NAME ${name} COMMAND ${name})
    endfunction()

    rgss_add_native_test(rgss_smoke_test "${CMAKE_SOURCE_DIR}/cmake/litergss-app/tests/smoke_test.c")
    set_tests_properties(rgss_smoke_test PROPERTIES TIMEOUT 10)

    # SFMLAudio::Music opening a second buffer (sfmlaudio's sf_Music.cpp; the
    # raylib backend's RaylibAudio, its SFMLAudio API)
    rgss_add_native_test(rgss_music_reopen_test "${CMAKE_SOURCE_DIR}/cmake/litergss-app/tests/music_reopen_test.c")
    # Ruby headers are third-party: SYSTEM keeps their warnings out of -Werror
    target_include_directories(rgss_music_reopen_test SYSTEM PRIVATE ${RUBY_FOR_ANDROID_INCLUDE_DIRS})
    target_compile_definitions(rgss_music_reopen_test PRIVATE
        AUDIO_INIT_FUNCTION=Init_${AUDIO_EXT_NAME}
        MUSIC_FIXTURE_PATH="${CMAKE_SOURCE_DIR}/cmake/litergss-app/tests/fixtures/tone.ogg"
        MUSIC_LONGER_FIXTURE_PATH="${CMAKE_SOURCE_DIR}/cmake/litergss-app/tests/fixtures/tone-long.ogg"
    )
    # AddressSanitizer reports the read of a released buffer, also from the
    # runtime's code (not instrumented: its memcpy interceptor checks it)
    target_compile_options(rgss_music_reopen_test PRIVATE -fsanitize=address)
    target_link_options(rgss_music_reopen_test PRIVATE -fsanitize=address)
    # Leaks of a VM never torn down are not what this test is about
    set_tests_properties(rgss_music_reopen_test PROPERTIES
        TIMEOUT 60
        ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0"
    )

    # Linux standalone entry point (litergss-main.c)
    if(PLATFORM_LOWER STREQUAL "linux")
        rgss_add_native_test(rgss_ruby_cli_test "${CMAKE_SOURCE_DIR}/cmake/litergss-app/tests/ruby_cli_test.c")
        set_tests_properties(rgss_ruby_cli_test PROPERTIES
            TIMEOUT 60
            ENVIRONMENT "XDG_CACHE_HOME=${CMAKE_CURRENT_BINARY_DIR}/ruby-cli-test-cache"
        )
    endif()

    message(STATUS "Smoke test enabled (native build, link mode: ${RGSS_SMOKE_TEST_LINK_MODE})")
else()
    if(NOT _RGSS_CAN_RUN_TESTS)
        message(STATUS "Smoke test disabled (cross-compiling: ${CMAKE_SYSTEM_NAME}/${CMAKE_SYSTEM_PROCESSOR} on ${CMAKE_HOST_SYSTEM_NAME}/${CMAKE_HOST_SYSTEM_PROCESSOR})")
    elseif(NOT RGSS_SMOKE_TEST_ENABLED)
        message(STATUS "Smoke test disabled (no testable output library)")
    endif()
endif()
