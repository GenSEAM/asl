(module asl/packages/asl-plugin/tests/sandboxPathTest :x [testValidSandboxPath! testRelativeEscapeRejection! testAbsoluteEscapeRejection! testSymlinkEscapeRejection! testNonexistentPath! testDualPolarityRefutations! runTests] :i [(asl-plugin/types :a t) (asl-plugin/security :a sec)])

fn ensureFixtures! -> Bool
  (let [(cmd "mkdir -p tmp/sandbox_51302 && echo 'valid-wasm' > tmp/sandbox_51302/valid.wasm && echo 'outside-wasm' > tmp/outside_51302.wasm && ln -sf $(pwd)/tmp/outside_51302.wasm tmp/sandbox_51302/symlink_escape.wasm 2>/dev/null") (res (processRun cmd))] (= res.exitCode 0))

fn testValidSandboxPath! -> Bool
  (let [(res (sec/validateSandboxPath! "valid.wasm" "tmp/sandbox_51302"))] (assert (ok? res) "Valid path must return ok Result") (mt res ((ok canon) (do (assert (stringContains? canon "tmp/sandbox_51302/valid.wasm") "Canonical path must contain valid filename") true)) ((err _) false)))

fn testRelativeEscapeRejection! -> Bool
  (let [(res (sec/validateSandboxPath! "../outside_51302.wasm" "tmp/sandbox_51302"))] (assert (err? res) "Relative escape must return err Result") (mt res ((err e) (let [(isEscape (mt e ((t/errSandboxEscape _) true) (else false)))] (assert isEscape "Relative escape must trigger errSandboxEscape variant") true)) ((ok _) false)))

fn testAbsoluteEscapeRejection! -> Bool
  (let [(res (sec/validateSandboxPath! "/etc/passwd" "tmp/sandbox_51302"))] (assert (err? res) "Absolute escape must return err Result") (mt res ((err e) (let [(isEscape (mt e ((t/errSandboxEscape _) true) (else false)))] (assert isEscape "Absolute escape must trigger errSandboxEscape variant") true)) ((ok _) false)))

fn testSymlinkEscapeRejection! -> Bool
  (let [(res (sec/validateSandboxPath! "symlink_escape.wasm" "tmp/sandbox_51302"))] (assert (err? res) "Symlink escape must return err Result") (mt res ((err e) (let [(isEscape (mt e ((t/errSandboxEscape _) true) (else false)))] (assert isEscape "Symlink escape must trigger errSandboxEscape variant") true)) ((ok _) false)))

fn testNonexistentPath! -> Bool
  (let [(res (sec/validateSandboxPath! "missing.wasm" "tmp/sandbox_51302"))] (assert (err? res) "Missing file must return err Result") (mt res ((err e) (let [(isNotFound (mt e ((t/errNotFound _) true) (else false)))] (assert isNotFound "Missing file inside sandbox must trigger errNotFound variant") true)) ((ok _) false)))

fn testDualPolarityRefutations! -> Bool
  (let [(resValid (sec/validateSandboxPath! "valid.wasm" "tmp/sandbox_51302")) (resRel (sec/validateSandboxPath! "../outside_51302.wasm" "tmp/sandbox_51302")) (resAbs (sec/validateSandboxPath! "/outside/target.wasm" "tmp/sandbox_51302")) (resSym (sec/validateSandboxPath! "symlink_escape.wasm" "tmp/sandbox_51302")) (resMissing (sec/validateSandboxPath! "missing.wasm" "tmp/sandbox_51302"))] (refute (err? resValid) "Valid sandbox path must not produce an error") (refute (ok? resRel) "Relative escape path must not produce ok") (refute (ok? resAbs) "Absolute escape path must not produce ok") (refute (ok? resSym) "Symlink escape path must not produce ok") (refute (ok? resMissing) "Nonexistent file must not produce ok") true)

fn ! runTests -> Bool
  (do (assert (ensureFixtures!) "Fixtures must be initialized cleanly") (assert (testValidSandboxPath!) "testValidSandboxPath must pass") (assert (testRelativeEscapeRejection!) "testRelativeEscapeRejection must pass") (assert (testAbsoluteEscapeRejection!) "testAbsoluteEscapeRejection must pass") (assert (testSymlinkEscapeRejection!) "testSymlinkEscapeRejection must pass") (assert (testNonexistentPath!) "testNonexistentPath must pass") (assert (testDualPolarityRefutations!) "testDualPolarityRefutations must pass") true)
