(module aslHarness/tests/pluginTest :x [runTests] :i [(plugin :a plug) (config :a cfg)])

fn testCreatePlugin -> Bool
  (let [(cap (plug/PluginCapability :providedTools (list "custom-tool-1") :systemPrompts (list "Use custom tool 1") :hooks (list (cfg/hookPreCall)) :dependencies (list) :conflicts (list))) (p (plug/createPlugin "plug-alpha" "Alpha Plugin" "1.0.0" 1 cap))] (assert (= p.id "plug-alpha") "plugin id matches") (assert (= p.name "Alpha Plugin") "plugin name matches") (assert p.enabled "plugin is enabled") (assert (= p.priority 1) "plugin priority is 1") true)

fn testRegistryLifecycle -> Bool
  (let [(cap (plug/PluginCapability :providedTools (list "test-cmd-a" "test-cmd-b") :systemPrompts (list) :hooks (list) :dependencies (list) :conflicts (list))) (p (plug/createPlugin "p1" "Plugin One" "1.0.0" 1 cap)) (reg0 (plug/registryCreate)) (reg1 (plug/registryAdd reg0 p)) (found (plug/registryFind reg1 "p1")) (tools (plug/registryGetTools reg1))] (assert (= reg1.activeCount 1) "active count is 1") (assert (match found ((none) false) ((some fp) (= fp.name "Plugin One"))) "found plugin name matches") (assert (= (listLength tools) 2) "tool count is 2") (assert (plug/containsString? tools "test-cmd-a") "contains test-cmd-a") true)

fn testStandardHarnessPlugins -> Bool
  (let [(std (plug/buildStandardHarnessPlugins)) (tools (plug/registryGetTools std))] (assert (>= std.activeCount 5) "standard count >= 5") (assert (plug/containsString? tools "intel-preload") "has intel-preload") (assert (plug/containsString? tools "audit-ast-mutation") "has audit-ast-mutation") (assert (plug/containsString? tools "scan-component-usages") "has scan-component-usages") true)

fn runTests -> Bool
  (do (testCreatePlugin) (testRegistryLifecycle) (testStandardHarnessPlugins) true)
