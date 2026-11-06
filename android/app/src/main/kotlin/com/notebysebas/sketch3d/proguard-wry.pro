# THIS FILE IS AUTO-GENERATED. DO NOT MODIFY!!

# Copyright 2020-2023 Tauri Programme within The Commons Conservancy
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: MIT

-keep class com.notebysebas.sketch3d.* {
  native <methods>;
}

-keep class com.notebysebas.sketch3d.WryActivity {
  public <init>(...);

  void setWebView(com.notebysebas.sketch3d.RustWebView);
  java.lang.Class getAppClass(...);
  int getId();
  java.lang.String getVersion();
  int startActivity(...);
}

-keep class com.notebysebas.sketch3d.Ipc {
  public <init>(...);

  @android.webkit.JavascriptInterface public <methods>;
}

-keep class com.notebysebas.sketch3d.RustWebView {
  public <init>(...);

  void loadUrlMainThread(...);
  void loadHTMLMainThread(...);
  void evalScript(...);
}

-keep class com.notebysebas.sketch3d.RustWebChromeClient,com.notebysebas.sketch3d.RustWebViewClient {
  public <init>(...);
}
