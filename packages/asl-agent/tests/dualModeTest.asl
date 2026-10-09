(module aslAgentTests/dualModeTest :x [testSimpleModeRouting! testMaintainerModeRouting! testCliSimpleFlagSelection runTests] :i [(agent :a ag) (cli :a cli) (policy :a pol)])

fn testSimpleModeRouting! -> Bool
  (let [(manifest (pol/makeManifest "/tmp" (list) "/tmp" false)) (out (ag/runInMode! (ag/modeSimple) "read config" "/tmp" manifest (pol/levelAuto)))] (assert (stringStartsWith? out "SIMPLE-MODE") "c-mode-pos-001: starts with simple mode prefix") (assert (not (stringStartsWith? out "MAINTAINER-MODE")) "c-mode-pos-001: not maintainer mode") true)

fn testMaintainerModeRouting! -> Bool
  (let [(manifest (pol/makeManifest "/tmp" (list) "/tmp" false)) (out (ag/runInMode! (ag/modeMaintainer) "refactor auth" "/tmp" manifest (pol/levelAuto)))] (assert (stringStartsWith? out "MAINTAINER-MODE") "c-mode-pos-002: starts with maintainer mode prefix") (assert (not (stringStartsWith? out "SIMPLE-MODE")) "c-mode-pos-002: not simple mode") true)

fn testCliSimpleFlagSelection -> Bool
  (let [(optSimple (cli/makeSimpleCliOptions (pol/levelAuto) "gemma-4-31b-it" "quick-cmd" "" false true)) (optDefault (cli/makeCliOptions (pol/levelAuto) "gemma-4-31b-it" "quick-cmd" "" false))] (assert optSimple.isSimple "simple flag is true") (assert (not optDefault.isSimple) "default is not simple") true)

fn ! runTests -> Bool
  (and (testSimpleModeRouting!) (and (testMaintainerModeRouting!) (testCliSimpleFlagSelection)))
