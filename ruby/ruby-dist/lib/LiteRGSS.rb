# Pokemon SDK requires its extensions by path on Linux (ruby-dist/lib/LiteRGSS).
# The extension is statically linked and already initialized: nothing to load.

# litergss-main.c only set it for the line that found this file: to Pokemon SDK,
# GAMEDEPS also means "started by the launcher" (progress on stdout, then closed).
ENV.delete('GAMEDEPS')
