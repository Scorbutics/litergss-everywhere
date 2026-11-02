/*
 * ruby_cli_test.c - The standalone entry point (litergss-main.c): stdlib, static
 * extensions, and what the embedded assets must provide to run Pokemon SDK
 * unmodified (extension paths, CA bundle).
 */

extern int litergss_main(int argc, char** argv);

static const char SCRIPT[] =
    "%w[zlib socket uri openssl net/http csv json yaml].each { |library| require library }\n"
    "require 'LiteRGSS'\n"
    "require 'SFMLAudio'\n"
    "lib = File.join(ENV.fetch('GAMEDEPS'), 'ruby-dist', 'lib')\n"
    "require File.join(lib, 'LiteRGSS')\n"
    "require File.join(lib, 'SFMLAudio')\n"
    "abort 'GAMEDEPS still set' if ENV.key?('GAMEDEPS')\n"
    "OpenSSL::X509::Store.new.add_file(ENV.fetch('SSL_CERT_FILE'))\n";

int main(void)
{
    char* argv[] = { "ruby", "-e", (char*) SCRIPT, 0 };
    return litergss_main(3, argv);
}
