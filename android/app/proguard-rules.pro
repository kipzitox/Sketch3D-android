# Keep the JNI entry points of the wry/tao bridge.
-keep class com.notebysebas.sketch3d.Rust { *; }
-keep class com.notebysebas.sketch3d.RustWebView { *; }
-keep class com.notebysebas.sketch3d.RustWebViewClient { *; }
-keep class com.notebysebas.sketch3d.RustWebChromeClient { *; }
-keep class com.notebysebas.sketch3d.WryActivity { *; }
-keep class com.notebysebas.sketch3d.Ipc { *; }
-keepclassmembers class com.notebysebas.sketch3d.Exporter {
    @android.webkit.JavascriptInterface <methods>;
}
