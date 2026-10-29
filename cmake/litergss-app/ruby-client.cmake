# Ruby client code shipped with the runtime (ruby/litergss: touch overlay...).
#
# ruby/litergss is zipped and embedded in liblitergss_ruby_client.a with
# embedded-ruby-vm's embed_binary; litergss_register_ruby_client()
# (files/ruby-client.c, called by extension-init.c) registers the ZIP with
# embedded-ruby-vm, which extracts it with the Ruby standard library, on the
# load path: `require 'litergss/touch_overlay'` loads a plain file.
#
# Defines LITERGSS_RUBY_CLIENT_LIB (the archive, in the staging lib dir) and
# the litergss_ruby_client target.

include(${CMAKE_SOURCE_DIR}/external/embedded-ruby-vm/assets/embed_binary.cmake)

set(_ruby_client_dir "${CMAKE_BINARY_DIR}/ruby-client")
set(_ruby_client_zip "litergss_ruby.zip")
file(GLOB_RECURSE _ruby_client_files CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/ruby/litergss/*")
file(MAKE_DIRECTORY "${_ruby_client_dir}")

add_custom_command(
    OUTPUT "${_ruby_client_dir}/${_ruby_client_zip}"
    COMMAND ${CMAKE_COMMAND} -E tar cf "${_ruby_client_dir}/${_ruby_client_zip}" --format=zip litergss
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/ruby"
    DEPENDS ${_ruby_client_files}
    COMMENT "Zipping the Ruby client code (ruby/litergss)"
    VERBATIM
)
embed_binary("${_ruby_client_dir}" "${_ruby_client_zip}" LITERGSS_RUBY_CLIENT_ZIP_OBJ)

add_library(litergss_ruby_client STATIC
    ${CMAKE_CURRENT_LIST_DIR}/dependencies/files/ruby-client.c
    ${LITERGSS_RUBY_CLIENT_ZIP_OBJ}
)
target_include_directories(litergss_ruby_client PRIVATE "${BUILD_STAGING_DIR}/usr/local/include")
set_target_properties(litergss_ruby_client PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${BUILD_STAGING_DIR}/usr/local/lib"
    POSITION_INDEPENDENT_CODE ON
)
# assets-install.h comes with the embedded-ruby-vm release
add_dependencies(litergss_ruby_client embedded-ruby-vm_external)

set(LITERGSS_RUBY_CLIENT_LIB "${BUILD_STAGING_DIR}/usr/local/lib/liblitergss_ruby_client.a")
