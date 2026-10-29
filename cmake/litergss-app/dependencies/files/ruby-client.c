/*
 * ruby-client.c
 *
 * Registers the Ruby client code (ruby/litergss, zipped and embedded by
 * cmake/litergss-app/ruby-client.cmake) with embedded-ruby-vm, which extracts
 * it with the Ruby standard library, on the load path.
 */

#include <stddef.h>
#include "embedded-ruby-vm/assets-install.h"

/* embed_binary.cmake symbols of litergss_ruby.zip */
extern const char _binary_litergss_ruby_zip_start[];
extern const char _binary_litergss_ruby_zip_end[];

void litergss_register_ruby_client(void)
{
    assets_register_extra_zip("litergss_ruby.zip", _binary_litergss_ruby_zip_start,
                              (size_t) (_binary_litergss_ruby_zip_end - _binary_litergss_ruby_zip_start));
}
