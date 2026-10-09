(module asl-ui/tests/pluginShellTest
  :x [runTests RunTests testPluginShellInitialization testRegisterAndRenderSlot testUnregisterPlugin testSlotValidation testDualPolarityRefutations]
  :i [(asl-ui/pluginShell :a ps)])

fn testPluginShellInitialization -> Bool
  (let [(shell (ps/makePluginShell))]
    (assert (listEmpty? shell.activePlugins) "initial shell has 0 active plugins")
    (refute (not (listEmpty? shell.activePlugins)) "initial shell refutes non-empty plugins")
    (assert (= (listLength shell.supportedSlots) 4) "shell supports 4 standard layout slots")
    (refute (!= (listLength shell.supportedSlots) 4) "supported slots count refutes non-4"))
  true

fn testRegisterAndRenderSlot -> Bool
  (let [(shell0 (ps/makePluginShell))
        (pHeader (ps/makeUIPlugin "nav" "Navbar" "header" "<nav>Links</nav>"))
        (pSidebar (ps/makeUIPlugin "tree" "FileTree" "sidebar" "<aside>Tree</aside>"))
        (reg1 (ps/registerPlugin shell0 pHeader))
        (shell1 (mt reg1 ((ok s) s) ((err _) shell0)))
        (reg2 (ps/registerPlugin shell1 pSidebar))
        (shell2 (mt reg2 ((ok s) s) ((err _) shell1)))]
    (assert (= (listLength shell2.activePlugins) 2) "2 plugins registered")
    (refute (!= (listLength shell2.activePlugins) 2) "registered count refutes mismatch")
    (let [(headerHtml (ps/renderSlot shell2 "header"))
          (sidebarHtml (ps/renderSlot shell2 "sidebar"))
          (emptyHtml (ps/renderSlot shell2 "footer"))]
      (assert (stringContains? headerHtml "<nav>Links</nav>") "header slot contains nav content")
      (assert (stringContains? headerHtml "slot-header") "header slot has slot-header class")
      (assert (stringContains? sidebarHtml "<aside>Tree</aside>") "sidebar slot contains tree content")
      (refute (stringContains? headerHtml "<aside>Tree</aside>") "header slot refutes sidebar content")
      (assert (stringContains? emptyHtml "slot-footer") "empty slot produces wrapper")))
  true

fn testUnregisterPlugin -> Bool
  (let [(shell0 (ps/makePluginShell))
        (plugin (ps/makeUIPlugin "p1" "Plugin One" "workspace" "<div>Canvas</div>"))
        (reg (ps/registerPlugin shell0 plugin))
        (shell1 (mt reg ((ok s) s) ((err _) shell0)))
        (unreg (ps/unregisterPlugin shell1 "p1"))]
    (assert (ok? unreg) "unregistering existing plugin succeeds")
    (refute (err? unreg) "unregistering existing plugin refutes error")
    (mt unreg
      ((ok shell2)
        (assert (listEmpty? shell2.activePlugins) "active plugins list is empty after unregister")
        (refute (not (listEmpty? shell2.activePlugins)) "active plugins refutes non-empty"))
      ((err _)
        (assert false "unexpected unregister failure")
        (refute true "unexpected unregister failure"))))
  true

fn testSlotValidation -> Bool
  (do
    (assert (ps/isValidSlot? "header") "header is valid slot")
    (assert (ps/isValidSlot? "sidebar") "sidebar is valid slot")
    (assert (ps/isValidSlot? "workspace") "workspace is valid slot")
    (assert (ps/isValidSlot? "footer") "footer is valid slot")
    (assert (not (ps/isValidSlot? "random-slot")) "random-slot is invalid")
    (refute (ps/isValidSlot? "random-slot") "random-slot refutes valid")
    true)

fn testDualPolarityRefutations -> Bool
  (let [(shell (ps/makePluginShell))
        (badPlugin (ps/makeUIPlugin "bad" "Bad" "invalid-slot" "content"))
        (regBad (ps/registerPlugin shell badPlugin))
        (unregNonExistent (ps/unregisterPlugin shell "ghost"))]
    (assert (err? regBad) "registering plugin with invalid slot fails")
    (refute (ok? regBad) "invalid slot refutes ok")
    (assert (err? unregNonExistent) "unregistering non-existent plugin fails")
    (refute (ok? unregNonExistent) "unregistering non-existent plugin refutes ok"))
  true

fn runTests -> Bool
  (do
    (assert (testPluginShellInitialization) "testPluginShellInitialization passed")
    (assert (testRegisterAndRenderSlot) "testRegisterAndRenderSlot passed")
    (assert (testUnregisterPlugin) "testUnregisterPlugin passed")
    (assert (testSlotValidation) "testSlotValidation passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
