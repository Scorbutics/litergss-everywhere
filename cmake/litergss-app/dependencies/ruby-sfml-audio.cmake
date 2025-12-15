# ruby-sfml-audio.cmake
# Configuration for ruby-sfml-audio (Ruby extension for SFML audio)

set(RUBY_SFML_AUDIO_VERSION "1.0.0")
set(RUBY_SFML_AUDIO_GIT_URL "https://gitlab.com/NuriYuri/sfmlaudio.git")
set(RUBY_SFML_AUDIO_GIT_TAG "HEAD")

string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)

# Source directory for install command reference
set(RUBY_SFML_AUDIO_SOURCE_DIR "${CMAKE_BINARY_DIR}/ruby-sfml-audio/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/ruby-sfml-audio-${RUBY_SFML_AUDIO_VERSION}")

# ruby-sfml-audio configure command (CMake-based)
set(RUBY_SFML_AUDIO_CONFIGURE_CMD
    ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_LIST_DIR}/files/ruby-sfml-audio-CMakeLists.txt ${RUBY_SFML_AUDIO_SOURCE_DIR}/CMakeLists.txt
    COMMAND ${CMAKE_COMMAND}
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_ANDROID_NDK}/build/cmake/android.toolchain.cmake
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DCMAKE_BUILD_TYPE=Release
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS} -std=c++17 ${RUBY_INCLUDE_DIR_CFLAGS}"
    "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    -DBUILD_SHARED_LIBS=TRUE
    .
)

add_external_dependency(
    NAME                ruby-sfml-audio
    VERSION             ${RUBY_SFML_AUDIO_VERSION}
    GIT_REPOSITORY      ${RUBY_SFML_AUDIO_GIT_URL}
    GIT_TAG             ${RUBY_SFML_AUDIO_GIT_TAG}
    GIT_SHALLOW         TRUE
    
    CONFIGURE_COMMAND   ${RUBY_SFML_AUDIO_CONFIGURE_CMD}
    
    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build .
    
    INSTALL_COMMAND     ${CMAKE_COMMAND} -E rename ${RUBY_SFML_AUDIO_SOURCE_DIR}/lib/SFMLAudio.so ${RUBY_SFML_AUDIO_SOURCE_DIR}/lib/libSFMLAudio.so
                        COMMAND ${BUILD_STAGING_DIR}/../host/usr/local/bin/patchelf --set-soname libSFMLAudio.so ${RUBY_SFML_AUDIO_SOURCE_DIR}/lib/libSFMLAudio.so
                        COMMAND ${CMAKE_COMMAND} -E copy ${RUBY_SFML_AUDIO_SOURCE_DIR}/lib/libSFMLAudio.so ${BUILD_STAGING_DIR}/usr/local/lib/
    
    DEPENDS             sfml ruby-for-android patchelf
)
