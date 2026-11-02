# Ruby client code shipped with the runtime (ruby/litergss: touch overlay...).
#
# ruby/litergss is zipped and embedded in liblitergss_ruby_client.a with
# embedded-ruby-vm's embed_binary; litergss_register_ruby_client()
# (files/ruby-client.c, called by extension-init.c) registers the ZIP with
# embedded-ruby-vm, which extracts it with the Ruby standard library, on the
# load path: `require 'litergss/touch_overlay'` loads a plain file.
#
# On Linux the library also holds the standalone entry point (files/litergss-main.c)
# and the ZIP what it needs to run Pokemon SDK as is: ruby/ruby-dist (the paths its
# loader requires) and a CA bundle, as ruby-dist/lib/cert.pem where Pokemon SDK
# looks for it.
#
# Defines LITERGSS_RUBY_CLIENT_LIB (the archive, in the staging lib dir) and
# the litergss_ruby_client target.

include(${CMAKE_SOURCE_DIR}/external/embedded-ruby-vm/assets/embed_binary.cmake)

set(_ruby_client_dir "${CMAKE_BINARY_DIR}/ruby-client")
set(_ruby_client_zip "litergss_ruby.zip")
file(GLOB_RECURSE _ruby_client_files CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/ruby/litergss/*")
file(MAKE_DIRECTORY "${_ruby_client_dir}")

# Assembled in a directory of its own: the ZIP paths are relative to it
set(_ruby_client_content "${_ruby_client_dir}/content")
set(_ruby_client_entries litergss)
set(_ruby_client_extra_commands "")

if(PLATFORM_LOWER STREQUAL "linux")
    # Mozilla's CA bundle, as published by curl.se/docs/caextract.html
    set(_ca_bundle "cacert-2026-10-20.pem")
    file(DOWNLOAD "https://curl.se/ca/${_ca_bundle}" "${_ruby_client_dir}/${_ca_bundle}"
        EXPECTED_HASH SHA256=796f1389bfea13c0ed78f663b765baaff54a508e5483786bd6ece73c5e3e3cbe
        TLS_VERIFY ON
    )

    file(GLOB_RECURSE _ruby_dist_files CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/ruby/ruby-dist/*")
    list(APPEND _ruby_client_files ${_ruby_dist_files} "${_ruby_client_dir}/${_ca_bundle}")
    list(APPEND _ruby_client_entries ruby-dist)
    list(APPEND _ruby_client_extra_commands
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_SOURCE_DIR}/ruby/ruby-dist" "${_ruby_client_content}/ruby-dist"
        COMMAND ${CMAKE_COMMAND} -E copy "${_ruby_client_dir}/${_ca_bundle}" "${_ruby_client_content}/ruby-dist/lib/cert.pem"
    )
endif()

add_custom_command(
    OUTPUT "${_ruby_client_dir}/${_ruby_client_zip}"
    COMMAND ${CMAKE_COMMAND} -E remove_directory "${_ruby_client_content}"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_SOURCE_DIR}/ruby/litergss" "${_ruby_client_content}/litergss"
    ${_ruby_client_extra_commands}
    COMMAND ${CMAKE_COMMAND} -E chdir "${_ruby_client_content}"
        ${CMAKE_COMMAND} -E tar cf "${_ruby_client_dir}/${_ruby_client_zip}" --format=zip ${_ruby_client_entries}
    DEPENDS ${_ruby_client_files}
    COMMENT "Zipping the Ruby client code (${_ruby_client_entries})"
    VERBATIM
)
embed_binary("${_ruby_client_dir}" "${_ruby_client_zip}" LITERGSS_RUBY_CLIENT_ZIP_OBJ)

add_library(litergss_ruby_client STATIC
    ${CMAKE_CURRENT_LIST_DIR}/dependencies/files/ruby-client.c
    ${LITERGSS_RUBY_CLIENT_ZIP_OBJ}
)
target_include_directories(litergss_ruby_client PRIVATE "${BUILD_STAGING_DIR}/usr/local/include")
if(PLATFORM_LOWER STREQUAL "linux")
    target_sources(litergss_ruby_client PRIVATE ${CMAKE_CURRENT_LIST_DIR}/dependencies/files/litergss-main.c)
    set_source_files_properties(${CMAKE_CURRENT_LIST_DIR}/dependencies/files/litergss-main.c PROPERTIES
        COMPILE_OPTIONS "-Wall;-Wextra;-Werror"
    )
    # Ruby headers are third-party: SYSTEM keeps their warnings out of -Werror
    target_include_directories(litergss_ruby_client SYSTEM PRIVATE ${RUBY_FOR_ANDROID_INCLUDE_DIRS})
endif()
set_target_properties(litergss_ruby_client PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${BUILD_STAGING_DIR}/usr/local/lib"
    POSITION_INDEPENDENT_CODE ON
)
# assets-install.h comes with the embedded-ruby-vm release
add_dependencies(litergss_ruby_client embedded-ruby-vm_external)

set(LITERGSS_RUBY_CLIENT_LIB "${BUILD_STAGING_DIR}/usr/local/lib/liblitergss_ruby_client.a")
