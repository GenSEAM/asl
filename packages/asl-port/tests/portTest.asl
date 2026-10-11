(module asl-port/tests/portTest
  :x [testPlanGeneration! testFixture1Arith! testFixture2Str! testFixture3Loop! testFixture4Cond! testFixture5Try! testFixture6Gap! testParitySpecGeneration! testPlanTraversalEdges! testTranslationEdges! testPythonMissing! testCliExecution! runTests]
  :i [(asl-json/json :a json)
      (asl-port/pyAst :a py)
      (asl-port/plan :a pl)
      (asl-port/translate :a tr)
      (asl-port/parity :a par)
      (asl-port/main :a m)])

fn hostExe -> String
  "asl/host/out/asl-host"

fn fixturePath name: String -> String
  (str "scratch/asl_port_fixtures/" name)

fn removeScratchPath! path: String -> Bool
  (if (fileExists? path) (ok? (pathRemove path)) true)

fn writeAndRunAsl! src: String tmpFile: String -> ProcessOutput
  (let [(writeRes (fileWrite tmpFile src))
        (_ (assert (ok? writeRes) "temporary ASL draft is written"))
        (cmd (str (hostExe) " run " tmpFile))
        (res (processRun cmd))]
    res)

fn testPlanGeneration! -> Bool
  (let [(_ (ensureFixtures!))
        (astRes (py/parsePythonAst! (fixturePath "f1_arith.py")))
        (_ (assert (ok? astRes) "f1_arith.py parses successfully"))
        (astVal (resultOr astRes (json/jnull)))
        (plan (pl/buildPortPlan (fixturePath "f1_arith.py") astVal))
        (fns plan.functions)
        (_ (assert (= (listLength fns) 2) "plan contains 2 functions"))
        (calcFn (mt (listHead fns) ((some f) f) ((none) (pl/FnPlan :name "" :startLine 0 :endLine 0 :callers (list) :globals (list)))))
        (_ (assert (= calcFn.name "calc_score") "first function is calc_score"))
        (_ (assert (= calcFn.startLine 1) "calc_score starts at line 1"))
        (_ (assert (listContains? calcFn.callers "run_calc") "calc_score caller is run_calc"))
        (_ (assert (listEmpty? calcFn.globals) "calc_score reads no globals"))
        (planStr (pl/formatPortPlan plan))
        (_ (cleanupFixtures!))]
    (do
      (assert (stringStartsWith? planStr "(:portPlan") "plan formats with (:portPlan")
      (assert (stringContains? planStr ":name \"calc_score\"") "plan includes calc_score")
      (assert (stringContains? planStr ":callers [\"run_calc\"]") "plan includes caller")
      true))

fn testFixture1Arith! -> Bool
  (let [(_ (ensureFixtures!))
        (astRes (py/parsePythonAst! (fixturePath "f1_arith.py")))
        (_ (assert (ok? astRes) "f1_arith parses"))
        (astVal (resultOr astRes (json/jnull)))
        (draft (tr/translateModule (fixturePath "f1_arith.py") astVal (list)))
        (draftText (tr/formatDraftFile "f1Draft" draft.functions draft.gaps))
        (src (str (stringReplace draftText ":x [" ":x [main ") "\n\nfn ! main -> (Result Int64 String)\n  (do (println (str (run_calc) \" \" (calc_score 4 4 2) \" \" (calc_score 2 5 3))) (ok 0))\n"))
        (tmpPath "scratch/f1_test.asl")
        (aslOut (writeAndRunAsl! src tmpPath))
        (pyCmd "python3 -c \"import sys; sys.path.insert(0, 'scratch/asl_port_fixtures'); import f1_arith; print(str(f1_arith.run_calc()) + ' ' + str(f1_arith.calc_score(4, 4, 2)) + ' ' + str(f1_arith.calc_score(2, 5, 3)))\"")
        (pyOut (processRun pyCmd))
        (_ (assert (removeScratchPath! tmpPath) "temporary ASL draft is removed"))
        (_ (cleanupFixtures!))]
    (do
      (assert (= aslOut.exitCode 0) "f1 ASL exits 0")
      (assert (= pyOut.exitCode 0) "f1 Python exits 0")
      (assert (= (stringTrim aslOut.stdout) (stringTrim pyOut.stdout)) "f1 ASL result matches Python result")
      (assert (= (stringTrim aslOut.stdout) "18 10 1") "f1 result is 18 10 1")
      true))

fn testFixture2Str! -> Bool
  (let [(_ (ensureFixtures!))
        (astRes (py/parsePythonAst! (fixturePath "f2_str.py")))
        (_ (assert (ok? astRes) "f2_str parses"))
        (astVal (resultOr astRes (json/jnull)))
        (draft (tr/translateModule (fixturePath "f2_str.py") astVal (list)))
        (draftText (tr/formatDraftFile "f2Draft" draft.functions draft.gaps))
        (src (str (stringReplace draftText ":x [" ":x [main ") "\n\nfn ! main -> (Result Int64 String)\n  (do (println (run_transform)) (ok 0))\n"))
        (tmpPath "scratch/f2_test.asl")
        (aslOut (writeAndRunAsl! src tmpPath))
        (pyCmd "python3 -c \"import sys; sys.path.insert(0, 'scratch/asl_port_fixtures'); import f2_str; print(f2_str.run_transform())\"")
        (pyOut (processRun pyCmd))
        (_ (assert (removeScratchPath! tmpPath) "temporary ASL draft is removed"))
        (_ (cleanupFixtures!))]
    (do
      (assert (= aslOut.exitCode 0) "f2 ASL exits 0")
      (assert (= pyOut.exitCode 0) "f2 Python exits 0")
      (assert (= (stringTrim aslOut.stdout) (stringTrim pyOut.stdout)) "f2 ASL result matches Python result")
      (assert (= (stringTrim aslOut.stdout) "formatted:alpha-beta-gamma") "f2 result formatted correctly")
      true))

fn testFixture3Loop! -> Bool
  (let [(_ (ensureFixtures!))
        (astRes (py/parsePythonAst! (fixturePath "f3_loop.py")))
        (_ (assert (ok? astRes) "f3_loop parses"))
        (astVal (resultOr astRes (json/jnull)))
        (draft (tr/translateModule (fixturePath "f3_loop.py") astVal (list)))
        (draftText (tr/formatDraftFile "f3Draft" draft.functions draft.gaps))
        (src (str (stringReplace draftText ":x [" ":x [main ") "\n\nfn ! main -> (Result Int64 String)\n  (do (println (str (run_loops))) (ok 0))\n"))
        (tmpPath "scratch/f3_test.asl")
        (aslOut (writeAndRunAsl! src tmpPath))
        (pyCmd "python3 -c \"import sys; sys.path.insert(0, 'scratch/asl_port_fixtures'); import f3_loop; print(f3_loop.run_loops())\"")
        (pyOut (processRun pyCmd))
        (_ (assert (removeScratchPath! tmpPath) "temporary ASL draft is removed"))
        (_ (cleanupFixtures!))]
    (do
      (assert (= aslOut.exitCode 0) "f3 ASL exits 0")
      (assert (= pyOut.exitCode 0) "f3 Python exits 0")
      (assert (= (stringTrim aslOut.stdout) (stringTrim pyOut.stdout)) "f3 ASL result matches Python result")
      (assert (= (stringTrim aslOut.stdout) "90") "f3 result is 90")
      true))

fn testFixture4Cond! -> Bool
  (let [(_ (ensureFixtures!))
        (astRes (py/parsePythonAst! (fixturePath "f4_cond.py")))
        (_ (assert (ok? astRes) "f4_cond parses"))
        (astVal (resultOr astRes (json/jnull)))
        (draft (tr/translateModule (fixturePath "f4_cond.py") astVal (list)))
        (draftText (tr/formatDraftFile "f4Draft" draft.functions draft.gaps))
        (src (str (stringReplace draftText ":x [" ":x [main ") "\n\nfn ! main -> (Result Int64 String)\n  (let [(r (run_evaluate))] (do (println (str (optionOr (mapGet r \"grade\") \"\") \" \" (optionOr (mapGet r \"points\") 0))) (ok 0)))\n"))
        (tmpPath "scratch/f4_test.asl")
        (aslOut (writeAndRunAsl! src tmpPath))
        (pyCmd "python3 -c \"import sys; sys.path.insert(0, 'scratch/asl_port_fixtures'); import f4_cond; r = f4_cond.run_evaluate(); print(r['grade'], r['points'])\"")
        (pyOut (processRun pyCmd))
        (_ (assert (removeScratchPath! tmpPath) "temporary ASL draft is removed"))
        (_ (cleanupFixtures!))]
    (do
      (assert (= aslOut.exitCode 0) "f4 ASL exits 0")
      (assert (= pyOut.exitCode 0) "f4 Python exits 0")
      (assert (= (stringTrim aslOut.stdout) (stringTrim pyOut.stdout)) "f4 ASL result matches Python result")
      (assert (= (stringTrim aslOut.stdout) "A 90") "f4 grade is A 90 at the >= 90 boundary")
      true))

fn testFixture5Try! -> Bool
  (let [(_ (ensureFixtures!))
        (astRes (py/parsePythonAst! (fixturePath "f5_try.py")))
        (_ (assert (ok? astRes) "f5_try parses"))
        (astVal (resultOr astRes (json/jnull)))
        (draft (tr/translateModule (fixturePath "f5_try.py") astVal (list)))
        (draftText (tr/formatDraftFile "f5Draft" draft.functions draft.gaps))
        (src (str (stringReplace draftText ":x [" ":x [main ") "\n\nfn ! main -> (Result Int64 String)\n  (do (println (str (run_div))) (ok 0))\n"))
        (tmpPath "scratch/f5_test.asl")
        (aslOut (writeAndRunAsl! src tmpPath))
        (pyCmd "python3 -c \"import sys; sys.path.insert(0, 'scratch/asl_port_fixtures'); import f5_try; print(f5_try.run_div())\"")
        (pyOut (processRun pyCmd))
        (_ (assert (removeScratchPath! tmpPath) "temporary ASL draft is removed"))
        (_ (cleanupFixtures!))]
    (do
      (assert (= aslOut.exitCode 0) "f5 ASL exits 0")
      (assert (= pyOut.exitCode 0) "f5 Python exits 0")
      (assert (= (stringTrim aslOut.stdout) (stringTrim pyOut.stdout)) "f5 ASL result matches Python result")
      (assert (= (stringTrim aslOut.stdout) "5") "f5 result is 5")
      true))

fn testFixture6Gap! -> Bool
  (let [(_ (ensureFixtures!))
        (astRes (py/parsePythonAst! (fixturePath "f6_gap.py")))
        (_ (assert (ok? astRes) "f6_gap parses"))
        (astVal (resultOr astRes (json/jnull)))
        (draft (tr/translateModule (fixturePath "f6_gap.py") astVal (list)))
        (gaps draft.gaps)
        (fns draft.functions)
        (_ (assert (= (listLength gaps) 1) "f6 has 1 port gap"))
        (gap (mt (listHead gaps) ((some g) g) ((none) (tr/PortGap :construct "" :line 0 :fnName "" :file ""))))
        (_ (assert (= gap.construct "Yield") "gap construct is Yield"))
        (_ (assert (= gap.line 3) "gap line is 3"))
        (_ (assert (= gap.fnName "stream_numbers") "gap function is stream_numbers"))
        (draftText (tr/formatDraftFile "f6Draft" fns gaps))
        (_ (cleanupFixtures!))]
    (do
      (assert (stringContains? draftText "(:portGap") "draft contains :portGap")
      (assert (stringContains? draftText ":construct \"Yield\"") "draft gap specifies Yield")
      (refute (stringContains? draftText "fn stream_numbers") "no function body emitted for gap fixture")
      true))

fn testParitySpecGeneration! -> Bool
  (let [(_ (ensureFixtures!))
        (astRes (py/parsePythonAst! (fixturePath "f1_arith.py")))
        (_ (assert (ok? astRes) "f1_arith parses for parity spec"))
        (astVal (resultOr astRes (json/jnull)))
        (spec (par/buildParitySpec (fixturePath "f1_arith.py") (list "calc_score") astVal))
        (specFns spec.functions)
        (_ (assert (= (listLength specFns) 1) "parity spec has 1 selected function"))
        (calcPar (mt (listHead specFns) ((some p) p) ((none) (par/FnParity :fnName "" :callSites (list)))))
        (sites calcPar.callSites)
        (_ (assert (= calcPar.fnName "calc_score") "spec function is calc_score"))
        (_ (assert (= (listLength sites) 1) "calc_score has 1 call site"))
        (site (mt (listHead sites) ((some s) s) ((none) (par/CallSite :caller "" :line 0 :args (list)))))
        (_ (assert (= site.caller "run_calc") "caller is run_calc"))
        (_ (assert (= site.line 13) "call line is 13"))
        (_ (assert (= (listLength site.args) 3) "3 arguments recorded"))
        (specText (par/formatParitySpec spec))
        (_ (cleanupFixtures!))]
    (do
      (assert (stringStartsWith? specText "(:paritySpec") "spec starts with (:paritySpec")
      (assert (stringContains? specText ":caller \"run_calc\"") "spec text contains caller")
      (assert (stringContains? specText ":args [\"10\" \"4\" \"3\"]") "parity preserves integer argument values")
      true))

fn testPlanTraversalEdges! -> Bool
  (let [(path "scratch/plan_edges.py")
        (_ (fileWrite path "GLOBAL_VALUE = 7\ndef target():\n    return 1\ndef factory():\n    return target\ndef caller():\n    wrapper(target_fn=target())\n    factory()()\ndef outer():\n    def inner():\n        GLOBAL_VALUE = 2\n    class Nested:\n        GLOBAL_VALUE = 3\n    return GLOBAL_VALUE\n"))
        (astRes (py/parsePythonAst! path))
        (astVal (resultOr astRes (json/jnull)))
        (plan (pl/buildPortPlan path astVal))
        (planText (pl/formatPortPlan plan))
        (parity (par/buildParitySpec path (list "target") astVal))
        (parityText (par/formatParitySpec parity))
        (_ (assert (removeScratchPath! path) "temporary Python probe is removed"))]
    (do
      (assert (stringContains? planText ":name \"target\" :startLine 2 :endLine 3 :callers [\"caller\"]") "keyword value call is traversed")
      (assert (stringContains? planText ":name \"factory\" :startLine 4 :endLine 5 :callers [\"caller\"]") "callable expression is traversed")
      (assert (stringContains? planText ":name \"outer\" :startLine 9 :endLine 14 :callers [] :globals [\"GLOBAL_VALUE\"]") "nested function and class assignments do not shadow globals")
      (assert (stringContains? parityText ":caller \"caller\"") "parity call sites traverse keyword values")
      true))

fn testTranslationEdges! -> Bool
  (let [(path "scratch/translate_edges.py")
        (_ (fileWrite path "def sum_evens(n):\n    total = 0\n    for i in range(n):\n        if i % 2 == 0:\n            total = total + i\n    return total\ndef loop_then_other(n):\n    total = 0\n    for i in range(n):\n        total = total + i\n    return n\ndef safe_mod(a, b):\n    try:\n        return a % b\n    except Exception:\n        return 0"))
        (astRes (py/parsePythonAst! path))
        (draft (tr/translateModule path (resultOr astRes (json/jnull)) (list)))
        (draftText (tr/formatDraftFile "edges" draft.functions draft.gaps))
        (_ (assert (removeScratchPath! path) "temporary Python probe is removed"))]
    (do
      (assert (stringContains? draftText ":construct \"If\"") "unsupported conditional loop is a port gap")
      (assert (stringContains? draftText ":fn \"sum_evens\"") "loop gap identifies its function")
      (refute (stringContains? draftText "fn sum_evens") "no plausible function body is emitted for an unsupported loop")
      (assert (stringContains? draftText "(let [(total (fold") "non-accumulator return after loop is preserved")
      (assert (stringContains? draftText "(mod a b)") "try modulo uses modulo operation")
      (assert (stringContains? draftText "ZeroDivisionError") "try modulo retains zero handling")
      true))

fn testUnsupportedSemanticsGap! -> Bool
  (let [(path "scratch/unsupported_semantics.py")
        (_ (fileWrite path "def attr_name(o):\n    return o.name\ndef nested():\n    def inner():\n        return 2\n    return inner()\ndef floating():\n    return 1.5\ndef chained(a, b, c):\n    return a < b < c\ndef true_div():\n    return 7 / 2\ndef assign_if(x):\n    y = 0\n    if x > 0:\n        y = 1\n    return y\ndef typed_except(s):\n    try:\n        return int(s)\n    except ValueError:\n        return -1\ndef multiple_except(s):\n    try:\n        return s / 2\n    except ValueError:\n        return -1\n    except TypeError:\n        return -2\ndef broad_except(s):\n    try:\n        return int(s)\n    except Exception:\n        return -1\ndef standalone_loop(n):\n    for i in range(n):\n        print(i)\ndef loop_after_expr(n):\n    print(n)\n    for i in range(n):\n        x = i\n    return n\n"))
        (astRes (py/parsePythonAst! path))
        (draft (tr/translateModule path (resultOr astRes (json/jnull)) (list)))
        (draftText (tr/formatDraftFile "unsupported" draft.functions draft.gaps))
        (_ (assert (removeScratchPath! path) "temporary Python probe is removed"))]
    (do
      (assert (= (listLength draft.gaps) 11) "all unsupported semantic constructs become gaps")
      (assert (stringContains? draftText ":construct \"Attribute\"") "attribute access is a port gap")
      (assert (stringContains? draftText ":construct \"FunctionDef\"") "nested function is a port gap")
      (assert (stringContains? draftText ":construct \"Constant\"") "float constant is a port gap")
      (assert (stringContains? draftText ":construct \"Compare\"") "chained comparison is a port gap")
      (assert (stringContains? draftText ":construct \"BinOp\"") "true division is a port gap")
      (assert (stringContains? draftText ":construct \"If\"") "if assignment fallthrough is a port gap")
      (assert (stringContains? draftText ":construct \"Try\"") "typed exception handling is a port gap")
      (assert (stringContains? draftText ":construct \"For\"") "standalone loop is a port gap")
      true))

fn testParityEscaping! -> Bool
  (let [(path "scratch/parity_escape.py")
        (_ (fileWrite path "def target(value):\n    return value\ndef caller():\n    return target(\"a\\\\b\")\n"))
        (astRes (py/parsePythonAst! path))
        (astVal (resultOr astRes (json/jnull)))
        (spec (par/buildParitySpec path (list "target") astVal))
        (specText (par/formatParitySpec spec))
        (_ (assert (removeScratchPath! path) "temporary Python probe is removed"))]
    (do
      (refute (stringContains? specText "a\\b") "parity escapes backslashes in argument strings")
      true))

fn testPythonMissing! -> Bool
  (let [(res (py/parsePythonAstWithTool! (fixturePath "f1_arith.py") "nonexistent_python_xyz"))
        (_ (assert (err? res) "missing python returns error"))
        (msg (mt res ((err m) m) ((ok _) "")))]
    (do
      (assert (stringStartsWith? msg "ERR_PYTHON3_MISSING") "error is ERR_PYTHON3_MISSING")
      true))

fn testCliExecution! -> Bool
  (let [(_ (ensureFixtures!))
        (outDir "scratch/cli_test")
        (res (m/main (list "py" (fixturePath "f1_arith.py") "--fn" "calc_score" "--out" outDir)))
        (planExists (mt (fileStat (str outDir "/plan.asn")) ((ok _) true) ((err _) false)))
        (draftExists (mt (fileStat (str outDir "/draft.asl")) ((ok _) true) ((err _) false)))
        (parityExists (mt (fileStat (str outDir "/parity.asn")) ((ok _) true) ((err _) false)))
        (chkRes (processRun (str (hostExe) " check " outDir "/draft.asl")))
        (_ (assert (removeScratchPath! (str outDir "/plan.asn")) "plan output is removed"))
        (_ (assert (removeScratchPath! (str outDir "/draft.asl")) "draft output is removed"))
        (_ (assert (removeScratchPath! (str outDir "/parity.asn")) "parity output is removed"))
        (_ (assert (removeScratchPath! outDir) "output directory is removed"))
        (badRes (m/main (list "bad_subcmd")))
        (unknownFlag (m/parseCliArgs (list "py" (fixturePath "f1_arith.py") "--unknown")))
        (missingFlagValue (m/parseCliArgs (list "py" (fixturePath "f1_arith.py") "--fn")))
        (missingOutValue (m/parseCliArgs (list "py" (fixturePath "f1_arith.py") "--out")))
        (flagUsedAsValue (m/parseCliArgs (list "py" (fixturePath "f1_arith.py") "--fn" "--out")))
        (failDirRes (m/main (list "py" (fixturePath "f1_arith.py") "--out" "/nonexistent/bad/path/cant/create")))
        (_ (cleanupFixtures!))]
    (do
      (assert (ok? res) "CLI executes with ok")
      (assert (= (resultOr res -1) 0) "CLI returns exit code 0")
      (assert (not unknownFlag.valid) "unknown CLI flag is rejected")
      (assert (not missingFlagValue.valid) "missing CLI flag value is rejected")
      (assert (not missingOutValue.valid) "missing output directory is rejected")
      (assert (not flagUsedAsValue.valid) "flag cannot be consumed as a value")
      (assert (ok? badRes) "bad CLI args execute with ok")
      (assert (= (resultOr badRes -1) 2) "bad CLI args return exit code 2")
      (assert (ok? failDirRes) "unwritable dir executes with ok")
      (assert (= (resultOr failDirRes -1) 1) "unwritable dir returns exit code 1")
      (assert planExists "plan.asn created")
      (assert draftExists "draft.asl created")
      (assert parityExists "parity.asn created")
      (assert (= chkRes.exitCode 0) "generated draft.asl checks with the stage-0 runner")
      true))


fn f1Content -> String
  "def calc_score(a, b, c):\n    if a > b:\n        diff = a - b\n        return diff * c\n    elif a == b:\n        return a + b + c\n    else:\n        rem = (b - a) % c\n        return rem + 1\n\n\ndef run_calc():\n    return calc_score(10, 4, 3)\n"

fn f2Content -> String
  "def transform_text(raw, sep):\n    cleaned = raw.strip()\n    if cleaned.startswith(\"msg:\"):\n        body = cleaned.replace(\"msg:\", \"\")\n        words = body.split(sep)\n        joined = \"-\".join(words)\n        return f\"formatted:{joined}\"\n    else:\n        return f\"plain:{cleaned}\"\n\n\ndef run_transform():\n    return transform_text(\"  msg:alpha,beta,gamma  \", \",\")\n"

fn f3Content -> String
  "def sum_squares_range(n):\n    total = 0\n    for i in range(n):\n        sq = i * i\n        total = total + sq\n    return total\n\n\ndef sum_list_elements(items):\n    total = 0\n    for x in items:\n        total = total + x\n    return total\n\n\ndef run_loops():\n    return sum_squares_range(5) + sum_list_elements([10, 20, 30])\n"

fn f4Content -> String
  "def evaluate_grade(score, extra):\n    if score < 0:\n        return {\"grade\": \"invalid\", \"points\": 0}\n    if score > 100:\n        return {\"grade\": \"overflow\", \"points\": 100}\n    adjusted = score + extra\n    if adjusted >= 90:\n        return {\"grade\": \"A\", \"points\": adjusted}\n    if adjusted >= 80:\n        return {\"grade\": \"B\", \"points\": adjusted}\n    return {\"grade\": \"C\", \"points\": adjusted}\n\n\ndef run_evaluate():\n    return evaluate_grade(83, 7)\n"

fn f5Content -> String
  "def safe_div(a, b):\n    try:\n        return a // b\n    except Exception:\n        return 0\n\n\ndef run_div():\n    return safe_div(10, 2) + safe_div(10, 0)\n"

fn f6Content -> String
  "def stream_numbers(n):\n    for i in range(n):\n        yield i\n"

fn ensureFixtures! -> Bool
  (do
    (cleanupFixtures!)
    (assert (ok? (dirCreate "scratch/asl_port_fixtures")) "fixture directory is created")
    (assert (ok? (fileWrite (fixturePath "f1_arith.py") (f1Content))) "fixture f1 is written")
    (assert (ok? (fileWrite (fixturePath "f2_str.py") (f2Content))) "fixture f2 is written")
    (assert (ok? (fileWrite (fixturePath "f3_loop.py") (f3Content))) "fixture f3 is written")
    (assert (ok? (fileWrite (fixturePath "f4_cond.py") (f4Content))) "fixture f4 is written")
    (assert (ok? (fileWrite (fixturePath "f5_try.py") (f5Content))) "fixture f5 is written")
    (assert (ok? (fileWrite (fixturePath "f6_gap.py") (f6Content))) "fixture f6 is written")
    true)

fn cleanupFixtures! -> Bool
  (do
    (assert (removeScratchPath! (fixturePath "f1_arith.py")) "fixture f1 is removed")
    (assert (removeScratchPath! (fixturePath "f2_str.py")) "fixture f2 is removed")
    (assert (removeScratchPath! (fixturePath "f3_loop.py")) "fixture f3 is removed")
    (assert (removeScratchPath! (fixturePath "f4_cond.py")) "fixture f4 is removed")
    (assert (removeScratchPath! (fixturePath "f5_try.py")) "fixture f5 is removed")
    (assert (removeScratchPath! (fixturePath "f6_gap.py")) "fixture f6 is removed")
    (assert (removeScratchPath! "scratch/asl_port_fixtures/__pycache__") "fixture bytecode cache is removed")
    (assert (removeScratchPath! "scratch/asl_port_fixtures") "fixture directory is removed")
    true)

fn ! runTests -> Bool
  (let [(_ (ensureFixtures!))
        (t1 (testPlanGeneration!))
        (t2 (testFixture1Arith!))
        (t3 (testFixture2Str!))
        (t4 (testFixture3Loop!))
        (t5 (testFixture4Cond!))
        (t6 (testFixture5Try!))
        (t7 (testFixture6Gap!))
        (t8 (testParitySpecGeneration!))
        (t9 (testPlanTraversalEdges!))
        (t10 (testTranslationEdges!))
        (t12 (testPythonMissing!))
        (t13 (testCliExecution!))
        (_ (testUnsupportedSemanticsGap!))
        (_ (testParityEscaping!))
        (_ (cleanupFixtures!))]
    (do true))
