# Checks that the Ruby client code compiled into the runtime (embed_ruby_client.cmake)
# loads as `require 'litergss/touch_overlay'`: the generated C file is built as a
# Ruby extension for the host Ruby (needs its headers and a C compiler), which
# loads it exactly as the runtime's extension init does; the required source and
# images must be identical to ruby/litergss.
#   cmake -DWORK_DIR=/tmp/ruby-client -P cmake/litergss-app/tests/check_ruby_client.cmake
# Optional: -DRUBY=<ruby executable> (default: ruby from PATH), -DCC=<C compiler>.

get_filename_component(_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(_ruby_dir "${_root}/ruby")
if(NOT WORK_DIR)
    set(WORK_DIR "${CMAKE_BINARY_DIR}/ruby-client-check")
endif()
if(NOT RUBY)
    set(RUBY ruby)
endif()
if(NOT CC)
    set(CC cc)
endif()
file(MAKE_DIRECTORY "${WORK_DIR}")

execute_process(
    COMMAND ${CMAKE_COMMAND} -DRUBY_DIR=${_ruby_dir} -DOUTPUT=${WORK_DIR}/litergss_ruby_client.c
            -P ${_root}/cmake/litergss-app/scripts/embed_ruby_client.cmake
    RESULT_VARIABLE _result)
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "embed_ruby_client.cmake failed")
endif()

# The test extension only forwards to the runtime's loading function
file(WRITE "${WORK_DIR}/ruby_client_test.c" "
void litergss_load_ruby_client(void);
void Init_ruby_client_test(void) { litergss_load_ruby_client(); }
")

execute_process(
    COMMAND ${RUBY} -rrbconfig -e "print RbConfig::CONFIG.values_at('rubyhdrdir', 'rubyarchhdrdir', 'DLEXT').join(';')"
    OUTPUT_VARIABLE _config RESULT_VARIABLE _result)
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "Cannot run ${RUBY}")
endif()
list(GET _config 0 _hdrdir)
list(GET _config 1 _archhdrdir)
list(GET _config 2 _dlext)

set(_link_flags -shared)
if(CMAKE_HOST_APPLE)
    set(_link_flags -bundle -undefined dynamic_lookup)
endif()
execute_process(
    COMMAND ${CC} -fPIC -Wall -Wextra -Werror ${_link_flags}
            -isystem ${_hdrdir} -isystem ${_archhdrdir}
            ${WORK_DIR}/litergss_ruby_client.c ${WORK_DIR}/ruby_client_test.c
            -o ${WORK_DIR}/ruby_client_test.${_dlext}
    RESULT_VARIABLE _result)
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "The generated Ruby client C source does not compile")
endif()

file(WRITE "${WORK_DIR}/check.rb" [=[
require 'ruby_client_test'
require 'litergss/touch_overlay'
ruby_dir = ARGV[0]
overlay = LiteRGSS::TouchOverlay
failures = []
expected = Dir[File.join(ruby_dir, 'litergss/touch_overlay/*.png')].to_h { |f| [File.basename(f, '.png'), File.binread(f)] }
failures << "images #{overlay::IMAGES.keys.sort} != #{expected.keys.sort}" unless overlay::IMAGES.keys.sort == expected.keys.sort
expected.each { |name, data| failures << "image #{name} differs" unless overlay::IMAGES[name] == data }
failures << 'IMAGES is not frozen' unless overlay::IMAGES.frozen?
file, line = overlay.method(:install).source_location
source = File.readlines(File.join(ruby_dir, 'litergss/touch_overlay.rb'))
failures << "install defined at #{file}:#{line}" unless file == 'litergss/touch_overlay.rb' && source[line - 1] =~ /def install/
failures << 'a second require loads again' if require('litergss/touch_overlay')
if failures.empty?
  puts "litergss/touch_overlay: #{overlay::IMAGES.size} images, source identical"
else
  puts failures
  exit 1
end
]=])
execute_process(
    COMMAND ${RUBY} -I ${WORK_DIR} ${WORK_DIR}/check.rb ${_ruby_dir}
    RESULT_VARIABLE _result)
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "The compiled Ruby client does not load as its source")
endif()
message(STATUS "Ruby client code compiles into the runtime and loads as its source")
