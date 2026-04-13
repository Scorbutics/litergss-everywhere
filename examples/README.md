# LiteRGSS Examples

## Available Examples

| Example | Language | Description |
|---------|----------|-------------|
| [simple_app/](simple_app/) | C | Minimal app linking the static library directly |
| [android-integration/](android-integration/) | Kotlin | Full Android app using the KMP module |
| [ios-integration/](ios-integration/) | Kotlin/Swift | iOS app using the KMP framework |
| [litergss_ruby_example.c](litergss_ruby_example.c) | C | Bare-bones Ruby VM + LiteRGSS initialization |

## Before Running Examples

Build litergss-everywhere first:

```bash
cd /path/to/litergss-everywhere
./configure
make
```

This produces `librgss_runtime.a` at `build/staging/usr/local/lib/`.

See the [Integration Guide](../docs/INTEGRATION.md) for detailed setup per platform, and the [Building Guide](../docs/BUILDING.md) for build options.
