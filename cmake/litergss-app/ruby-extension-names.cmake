# ruby-extension-names.cmake
# Names of the Ruby extensions the runtime embeds, and of their init
# functions (Init_<name>): extension-init.c (embedded-ruby-vm.cmake) calls
# what litergss2.cmake / litergss3.cmake / ruby-sfml-audio.cmake /
# ruby-raylib-audio.cmake build.
#
# Android only packages native libraries named lib*.so: there, a shared
# build names them lib<name> (Init_lib<name>). Every other build, static
# builds included, keeps the plain name.

string(TOLOWER "${TARGET_PLATFORM}" _RGSS_EXT_PLATFORM)
if(BUILD_SHARED_LIBS AND _RGSS_EXT_PLATFORM STREQUAL "android")
    set(_RGSS_EXT_PREFIX "lib")
else()
    set(_RGSS_EXT_PREFIX "")
endif()

set(LITERGSS_EXT_NAME "${_RGSS_EXT_PREFIX}LiteRGSS")
set(SFMLAUDIO_EXT_NAME "${_RGSS_EXT_PREFIX}SFMLAudio")
set(RAYLIBAUDIO_EXT_NAME "${_RGSS_EXT_PREFIX}RaylibAudio")

# The audio extension of the backend (CMakeLists.txt): RaylibAudio, which
# also defines SFMLAudio's API, with raylib; SFMLAudio with sfml.
if(LITERGSS_BACKEND STREQUAL "raylib")
    set(AUDIO_EXT_NAME "${RAYLIBAUDIO_EXT_NAME}")
else()
    set(AUDIO_EXT_NAME "${SFMLAUDIO_EXT_NAME}")
endif()
