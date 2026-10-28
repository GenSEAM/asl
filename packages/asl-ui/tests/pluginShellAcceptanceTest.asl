(module asl-ui/tests/pluginShellAcceptanceTest
  :x [runTests RunTests testPluginMountAndSlotRender testPluginLifecycle testDualPolarityRefutations]
  :i [(asl-ui/pluginShell :a ps)])

fn testPluginMountAndSlotRender -> Bool
  (let [(shell0 (ps/makePluginShell))
        (plugin (ps/makeUIPlugin "chat" "ChatPlugin" "sidebar" "<div id=\"chat-view\">Chat</div>"))
        (regRes (ps/registerPlugin shell0 plugin))
        (shell1 (match regRes ((ok s) s) ((err _) shell0)))
        (rendered (ps/renderSlot shell1 "sidebar"))]
    (assert (= (listLength shell1.activePlugins) 1) "1 plugin mounted")
    (refute (!= (listLength shell1.activePlugins) 1) "plugin count refutes divergence")
    (assert (stringContains? rendered "<div id=\"chat-view\">Chat</div>") "sidebar renders chat plugin")
    (refute (not (stringContains? rendered "<div id=\"chat-view\">Chat</div>")) "sidebar refutes missing content")
    (assert (stringContains? rendered "slot-sidebar") "slot wrapper has slot-sidebar class"))
  true

fn testPluginLifecycle -> Bool
  (let [(shell0 (ps/makePluginShell))
        (plugin (ps/makeUIPlugin "term" "Terminal" "footer" "<pre>terminal</pre>"))
        (regRes (ps/registerPlugin shell0 plugin))
        (shell1 (match regRes ((ok s) s) ((err _) shell0)))
        (unregRes (ps/unregisterPlugin shell1 "term"))
        (shell2 (match unregRes ((ok s) s) ((err _) shell1)))]
    (assert (ok? unregRes) "unmount succeeds")
    (refute (err? unregRes) "unmount refutes failure")
    (assert (listEmpty? shell2.activePlugins) "active plugins is empty after unmount")
    (refute (not (listEmpty? shell2.activePlugins)) "active plugins refutes non-empty"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(shell (ps/makePluginShell))
        (badPlugin (ps/makeUIPlugin "" "Title" "header" "content"))
        (res (ps/registerPlugin shell badPlugin))]
    (assert (err? res) "plugin with empty ID is rejected")
    (refute (ok? res) "plugin with empty ID refutes ok"))
  true

fn runTests -> Bool
  (do
    (assert (testPluginMountAndSlotRender) "testPluginMountAndSlotRender passed")
    (assert (testPluginLifecycle) "testPluginLifecycle passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
