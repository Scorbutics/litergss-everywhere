# litergss2.cmake
# Configuration for LiteRGSS2 (the main library)

set(LITERGSS2_VERSION "2.0.0")
set(LITERGSS2_GIT_URL "https://gitlab.com/pokemonsdk/litergss2.git")
set(LITERGSS2_GIT_TAG "development")

option(BUILD_SHARED_WRAPPER "Build single shared library wrapper (rgss_runtime) instead of archive" OFF)

string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)

# Get Ruby arch and set include/lib paths from embedded-ruby-vm
get_ruby_arch(RUBY_ARCH "litergss2")
set(RUBY_MINOR_VERSION "3.1.0")
# RUBY_INCLUDE_DIR_CFLAGS and RUBY_LIB_DIR_LFLAGS are already set by embedded-ruby-vm.cmake
# No need to override them here

# Build directory for install command reference
set(LITERGSS2_BUILD_DIR "${CMAKE_BINARY_DIR}/litergss2/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/litergss2-${LITERGSS2_VERSION}")
set(LITERGSS2_EXTRA_CFLAGS "-I${BUILD_STAGING_DIR}/usr/local/include/LiteCGSS -DLITECGSS_USE_PHYSFS ${RUBY_INCLUDE_DIR_CFLAGS}")

# litergss2 configure command (CMake-based)
# Note: Now builds as static library for all platforms internally
# We force BUILD_SHARED_LIBS=OFF for the inner library to ensure we get a static .a to link
set(LITERGSS2_CONFIGURE_CMD
    ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_LIST_DIR}/files/litergss2-CMakeLists.txt ${LITERGSS2_BUILD_DIR}/CMakeLists.txt
    COMMAND ${CMAKE_COMMAND}
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DCMAKE_BUILD_TYPE=Release
    "-DCMAKE_C_FLAGS=${CFLAGS} ${LITERGSS2_EXTRA_CFLAGS}"
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS} ${LITERGSS2_EXTRA_CFLAGS}"
    "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    -DBUILD_SHARED_LIBS=OFF 
    .
)

# Static build: just copy .a file
set(LITERGSS2_INSTALL_CMD
    ${CMAKE_COMMAND} -E copy ${LITERGSS2_BUILD_DIR}/lib/libLiteRGSS.a ${BUILD_STAGING_DIR}/usr/local/lib/
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_LIST_DIR}/files/extension-init.c ${BUILD_STAGING_DIR}/extension-init.c
)
set(LITERGSS2_DEPENDS litecgss embedded-ruby-vm)
set(LITERGSS2_PATCH_DIR ${CMAKE_CURRENT_LIST_DIR}/patches/litergss2/static)

add_external_dependency(
    NAME                litergss2
    VERSION             ${LITERGSS2_VERSION}
    GIT_REPOSITORY      ${LITERGSS2_GIT_URL}
    GIT_TAG             ${LITERGSS2_GIT_TAG}
    GIT_SHALLOW         TRUE

    CONFIGURE_COMMAND   ${LITERGSS2_CONFIGURE_CMD}

    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build .

    INSTALL_COMMAND     ${LITERGSS2_INSTALL_CMD}

    PATCH_DIR           ${LITERGSS2_PATCH_DIR}

    DEPENDS             ${LITERGSS2_DEPENDS}
)

# ============================================================================
# FINAL OUTPUT
# ============================================================================

if(BUILD_SHARED_WRAPPER)
    # ------------------------------------------------------------------------
    # SHARED WRAPPER MODE (rgss_runtime.so)
    # ------------------------------------------------------------------------
    message(STATUS "LiteRGSS: Configuring shared wrapper build (rgss_runtime)")
    
    # Create the shared library target
    add_library(rgss_runtime SHARED ${CMAKE_CURRENT_LIST_DIR}/files/dummy.c)

    # Determine extension for static libs to link
    # The inner libs are FORCED static by our changes, except if BUILD_SHARED_LIBS was passed globally?
    # Wait, we forced LITERGSS2 to OFF above.
    # Other deps respect global BUILD_SHARED_LIBS.
    # The user requirements said: "build all the dependencies and the litergss2 as individual internal static libraries"
    # So we assume they are static .a files.
    # If global BUILD_SHARED_LIBS is ON, our dependencies (sfml, etc) built shared.
    # But litergss2 build command above forces OFF.
    # Let's assume we link against whatever was built.
    
    if(BUILD_SHARED_LIBS)
        set(DEP_EXT "so")
    else()
        set(DEP_EXT "a")
    endif()

    # Define the list of library files to link
    # Using full paths to staging dir
    set(LIBS_TO_LINK
        "${BUILD_STAGING_DIR}/usr/local/lib/libLiteRGSS.a" # Always static as per above
        "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-graphics.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-window.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-system.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-audio.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-network.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libLiteCGSS_engine.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libphysfs.a" # LiteCGSS setup usually static
        "${BUILD_STAGING_DIR}/usr/local/lib/libskalog.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libfreetype.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libogg.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libvorbis.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libvorbisenc.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libvorbisfile.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libFLAC.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/lib/libopenal.${DEP_EXT}"
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
        litergss2
        sfml litecgss openal-soft flac libogg libvorbis freetype
    )
    
    # We also need rubysfml-audio if used
    # Assuming it is part of the request (not explicitly listed but usually required)
    # If so, add it to LIBS_TO_LINK
    
    install(TARGETS rgss_runtime DESTINATION lib)

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

    # Copy Ruby headers for consumers
    file(MAKE_DIRECTORY "${BUILD_STAGING_DIR}/usr/local/include")
    foreach(include_dir ${EMBEDDED_RUBY_VM_INCLUDE_DIRS})
        if(EXISTS "${include_dir}")
            file(COPY "${include_dir}/" DESTINATION "${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}/")
        endif()
    endforeach()

    # ========================================================================
    # Create "fat" static library combining all dependencies
    # ========================================================================
    if(NOT BUILD_SHARED_LIBS)
        include(${CMAKE_SOURCE_DIR}/cmake/core/CombineFatLibrary.cmake)

        # Configurable fat library name (default: rgss_runtime)
        set(FAT_LIBRARY_NAME "rgss_runtime" CACHE STRING "Name of the fat library (without lib prefix or extension)")
        
        # Define the list of static libraries to combine
        set(STATIC_LIBS_TO_COMBINE
            # This repository dependencies
            "${BUILD_STAGING_DIR}/usr/local/lib/libLiteRGSS.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libSFMLAudio.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-graphics-s.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-window-s.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-system-s.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-audio-s.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-network-s.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-main.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libLiteCGSS_engine.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libphysfs.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libskalog.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libfreetype.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libogg.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libvorbis.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libvorbisenc.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libvorbisfile.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libFLAC.a"
            "${BUILD_STAGING_DIR}/usr/lib/libopenal.a"
            # Ruby's dependencies (non-debug variants only, no _g versions)
            # Make sure the libruby-ext.a goes first because it will define Init_ext, as libruby-static.a does,
            # and we only keep the first found symbol in case of duplicates.
            "${BUILD_STAGING_DIR}/usr/local/lib/libruby-ext.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libruby-static.a"
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
            "${BUILD_STAGING_DIR}/usr/local/lib/libcrypt.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libbsd.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libmd.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libz.a"
            # Final libs
            "${BUILD_STAGING_DIR}/usr/local/lib/libminizip.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libassets.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libembedded-ruby.a"
        )

        set(FAT_LIBRARY_OUTPUT "${BUILD_STAGING_DIR}/usr/local/lib/lib${FAT_LIBRARY_NAME}.a")
        set(FAT_LIBRARY_WORKDIR "${CMAKE_BINARY_DIR}/fat_library_workdir")

        # Filter library list to only include files that exist (at configure time)
        # This handles platform differences (e.g., Android doesn't have libcrypt.a)
        set(EXISTING_LIBS_TO_COMBINE)
        foreach(lib ${STATIC_LIBS_TO_COMBINE})
            if(EXISTS "${lib}")
                list(APPEND EXISTING_LIBS_TO_COMBINE "${lib}")
            else()
                message(STATUS "Skipping non-existent library: ${lib}")
            endif()
        endforeach()

        # Create custom command that calls the combine function
        # Note: We depend on the actual library files so the fat library rebuilds if they change
        add_custom_command(
            OUTPUT ${FAT_LIBRARY_OUTPUT}
            COMMAND ${CMAKE_COMMAND}
                -DCOMBINE_OUTPUT=${FAT_LIBRARY_OUTPUT}
                -DCOMBINE_WORKDIR=${FAT_LIBRARY_WORKDIR}
                -DCOMBINE_AR=${CMAKE_AR}
                -DCOMBINE_RANLIB=${CMAKE_RANLIB}
                -DCOMBINE_NM=${CMAKE_NM}
                "-DCOMBINE_LIBS=${EXISTING_LIBS_TO_COMBINE}"
                -P ${CMAKE_SOURCE_DIR}/cmake/core/CombineFatLibraryScript.cmake
            DEPENDS litergss2_external ${EXISTING_LIBS_TO_COMBINE}
            COMMENT "Creating fat static library lib${FAT_LIBRARY_NAME}.a"
            VERBATIM
        )

        add_custom_target(rgss_fat_library ALL
            DEPENDS ${FAT_LIBRARY_OUTPUT}
        )

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
            DEPENDS litergss2_external embedded-ruby-vm rgss_fat_library
        )
        add_dependencies(litergss2 litergss_archive rgss_fat_library)
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
            DEPENDS litergss2_external embedded-ruby-vm
        )
        add_dependencies(litergss2 litergss_archive)
    endif()

    message(STATUS "LiteRGSS2 configured - archive will be: ${LITERGSS_ARCHIVE_NAME}")
endif()
