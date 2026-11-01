# librgss_runtime.so binds NativeSurface's natives by name, and looks up its
# virtual keyboard callback (GetStaticMethodID) when the callback is armed:
# a minified host must keep them as they are.
-keep class com.scorbutics.litergss.NativeSurface {
    native <methods>;
    *** dispatchVirtualKeyboardRequest(...);
}
