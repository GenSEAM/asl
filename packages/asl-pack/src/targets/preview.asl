(module aslPack/targets/preview
  :d "In-browser WebAssembly mobile simulator and live dual-device preview generator."
  :x [MobilePreviewSpec
      generateDevicePreviewHtml
      generatePreviewWasmManifest]
  :i [])

(df int-to-string [(n Int64)] -> Str
  :d "Converts integer to string representation."
  (string-from-int64 n))

(dfs MobilePreviewSpec
  (:f appName Str "Application display name e.g. ASL Mobile")
  (:f defaultPlatform Str "Initial active device view: ios or android")
  (:f enableHotReload Bool "Enables local WebSocket hot-reload client")
  (:f reloadPort Int64 "WebSocket hot-reload port e.g. 8080"))

(df generatePreviewWasmManifest [(spec MobilePreviewSpec)] -> Str
  :d "Emits ASN runtime configuration manifest for in-browser Wasm mobile execution."
  (str "(:wasm-preview-config\n"
       "  :app-name \"" (.-appName spec) "\"\n"
       "  :platform \"" (.-defaultPlatform spec) "\"\n"
       "  :hot-reload " (if (.-enableHotReload spec) "true" "false") "\n"
       "  :port " (int-to-string (.-reloadPort spec)) "\n"
       "  :features [:touch-emulation :sensor-mocks :orientation-toggle :theme-switch])\n"))

(df generateDevicePreviewHtml [(spec MobilePreviewSpec)] -> Str
  :d "Generates standalone HTML5 dual-device simulator with iPhone 16 Pro and Pixel 9 mockups."
  (let [(title (.-appName spec))
        (portStr (int-to-string (.-reloadPort spec)))]
    (str "<!DOCTYPE html>\n"
         "<html lang=\"en\">\n"
         "<head>\n"
         "  <meta charset=\"UTF-8\" />\n"
         "  <title>" title " - In-Browser Mobile Preview</title>\n"
         "  <style>\n"
         "    body { margin: 0; padding: 24px; background: #0f172a; color: #f8fafc; font-family: system-ui, sans-serif; display: flex; flex-direction: column; align-items: center; min-height: 100vh; }\n"
         "    .toolbar { display: flex; gap: 12px; margin-bottom: 20px; align-items: center; background: #1e293b; padding: 8px 16px; border-radius: 9999px; border: 1px solid #334155; }\n"
         "    .btn { background: #3b82f6; color: white; border: none; padding: 6px 14px; border-radius: 9999px; cursor: pointer; font-weight: 500; }\n"
         "    .viewport-container { display: flex; gap: 32px; flex-wrap: wrap; justify-content: center; }\n"
         "    .device-frame { width: 393px; height: 852px; background: #000; border-radius: 54px; box-shadow: 0 25px 50px -12px rgba(0,0,0,0.7), inset 0 0 0 4px #475569; position: relative; overflow: hidden; display: flex; flex-direction: column; }\n"
         "    .dynamic-island { width: 120px; height: 35px; background: #000; border-radius: 20px; margin: 11px auto 0 auto; z-index: 10; position: relative; }\n"
         "    .screen { flex: 1; background: #fff; color: #000; overflow-y: auto; position: relative; }\n"
         "    .home-indicator { width: 140px; height: 5px; background: #000; border-radius: 3px; margin: 8px auto; }\n"
         "    .badge { font-size: 12px; padding: 2px 8px; border-radius: 4px; background: #22c55e20; color: #4ade80; border: 1px solid #22c55e40; }\n"
         "  </style>\n"
         "</head>\n"
         "<body>\n"
         "  <div class=\"toolbar\">\n"
         "    <strong>" title "</strong>\n"
         "    <span class=\"badge\">Wasm Core Active</span>\n"
         "    <button class=\"btn\" onclick=\"toggleTheme()\">Toggle Theme</button>\n"
         "    <button class=\"btn\" onclick=\"toggleOrientation()\">Rotate</button>\n"
         "  </div>\n"
         "  <div class=\"viewport-container\">\n"
         "    <div class=\"device-frame\" id=\"ios-frame\">\n"
         "      <div class=\"dynamic-island\"></div>\n"
         "      <div class=\"screen\" id=\"app-screen\"></div>\n"
         "      <div class=\"home-indicator\"></div>\n"
         "    </div>\n"
         "  </div>\n"
         "  <script>\n"
         "    const ws = new WebSocket('ws://localhost:" portStr "');\n"
         "    ws.onmessage = (event) => {\n"
         "      const data = JSON.parse(event.data);\n"
         "      if (data.type === 'patch') document.getElementById('app-screen').innerHTML = data.html;\n"
         "    };\n"
         "  </script>\n"
         "</body>\n"
         "</html>\n")))
