(module asl-forms/tests/driverParityTest
  :x [runTests]
  :i [(asl-forms/kernel :a k) (asl-forms/gate :a g) (asl-forms/ops :a ops) (asl-forms/main :a main)])


(schema CaseSpec
  (:f id Int64)
  (:f scenario String)
  (:f form String)
  (:f want String)
  (:f exit Int64)
  (:f scriptDir String))

(schema Tally (:f cases Int64) (:f failures Int64) (:f packNotPorted Int64) (:f batchDiverged Int64) (:f packFlagFailures Int64))

fn expectedPackArgs id: Int64 -> String
  (cond
    ((= id 4) "pack --target wat --quick")
    ((= id 5) "pack --target c --dist")
    ((= id 6) "pack --target py --self")
    ((= id 7) "pack --target go --install")
    ((= id 8) "pack --target llvm --version 0.2.0")
    ((= id 9) "pack --target rs --skip-gates")
    (else ""))


fn kwOr kw: (Map String String) key: String fallback: String -> String
  (optionOr (mapGet kw key) fallback)

fn parseCase line: String -> CaseSpec
  (let [(p (k/parseStep line))
        (kw p.kwargs)]
    (CaseSpec :id (optionOr (stringToInt64 (kwOr kw "id" "0")) 0)
              :scenario (kwOr kw "scenario" "")
              :form (kwOr kw "form" "")
              :want (kwOr kw "want" "")
              :exit (optionOr (stringToInt64 (kwOr kw "exit" "0")) 0)
              :scriptDir (kwOr kw "scriptDir" "")))

fn stubScript -> String
  "#!/bin/sh\ncase \"$1\" in\n  pack)\n    printf '%s' \"$*\" > \"$ASL_TEST_PACK_ARGS\"\n    case \"$*\" in\n      *--target\\ fail*) printf 'pack error: compile failed\\n' >&2; exit 1 ;;\n      *--target\\ long*) i=0; while [ $i -lt 50 ]; do printf 'long-pack-error-%02d ' \"$i\" >&2; i=$((i+1)); done; printf '\\n' >&2; exit 2 ;;\n      *) printf 'pack ok\\n'; exit 0 ;;\n    esac ;;\n  *)\n    exit 64 ;;\nesac\n"

fn prepareStubs! -> String
  (let [(tmp (str (optionOr (envGet "TMPDIR") "/tmp/") "aslDriverStubs_" (stringFromInt64 (mod (nowNs) 1000000))))
        (bin (str tmp "/bin"))
        (aslFile (str bin "/asl"))
        (d (dirCreate bin))
        (w (fileWrite aslFile (stubScript)))
        (c (g/runArgv! (list "chmod" "+x" aslFile) (none) (none) 5000 0))]
    bin)

fn cleanStubs! bin: String -> Bool
  (let [(rm (g/runArgv! (list "rm" "-rf" (k/dirName bin)) (none) (none) 5000 0))]
    true)

fn buildEnv! root: String defaultStubs: String c: CaseSpec -> (List String)
  (let [(sDir (if (stringEmpty? c.scriptDir) defaultStubs c.scriptDir))
        (baseEnv (list (str "ROOT_DIR=" root)
                       (str "SCRIPT_DIR=" sDir)
                       (str "PATH=" sDir ":" (optionOr (envGet "PATH") ""))
                       (str "ASL_TEST_PACK_ARGS=" defaultStubs "/pack-args")
                       "ASL_GATEWAY_PORT=1"))]
    baseEnv)

fn ! driveWrite root: String lines: (List String) -> main/Drive
  (main/driveOutcome! root (list) 1 true
    (main/Drive :lines (list) :failed (list) :heads (list) :errs 0 :stop "")
    (k/parseStep "(:write :file \"x.txt\" :content \"y\")")
    (ops/StepOutcome :lines lines :errCount 0))

fn ported? output: String -> Bool
  (not (stringContains? output "ERR_NOT_PORTED"))

fn checkCase! root: String defaultStubs: String host: String mainPath: String c: CaseSpec t: Tally -> Tally
  (let [(env (buildEnv! root defaultStubs c))
        (r (g/runArgv! (list host "run" mainPath c.form) (some root) (some env) 10000 0))
        (got (stringTrim r.out))
        (code r.code)
        (same (and (= got c.want) (= code c.exit)))
        (expectedArgs (expectedPackArgs c.id))
        (gotArgs (if (stringEmpty? expectedArgs) "" (resultOr (fileReadString (str defaultStubs "/pack-args")) "<missing>")))
        (argsSame (or (stringEmpty? expectedArgs) (= gotArgs expectedArgs)))
        (isPackNP (and (stringContains? c.scenario "pack") (stringContains? got "ERR_NOT_PORTED")))
        (isBatchDiv (and (stringStartsWith? c.scenario "batchMixed") (not same)))]
    (do
      (assert (ported? got) (str "driver case " (stringFromInt64 c.id) " never falls back to ERR_NOT_PORTED"))
      (if same
        (print "")
        (println (str "(:driverDiff :id " (stringFromInt64 c.id) " :scenario \"" c.scenario
                      "\" :wantExit " (stringFromInt64 c.exit) " :gotExit " (stringFromInt64 code)
                      " :want \"" (k/escapeAsnVal c.want) "\" :got \"" (k/escapeAsnVal got) "\")")))
      (Tally :cases (+ t.cases 1)
             :failures (+ t.failures (if same 0 1) (if argsSame 0 1))
             :packNotPorted (+ t.packNotPorted (if isPackNP 1 0))
             :batchDiverged (+ t.batchDiverged (if isBatchDiv 1 0))
             :packFlagFailures (+ t.packFlagFailures (if argsSame 0 1)))))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (stubs (prepareStubs!))
        (host (k/joinPath root "asl/host/out/asl-host"))
        (mainPath (k/joinPath root "asl/packages/asl-forms/src/main.asl"))
        (fixturePath (k/joinPath root "asl/packages/asl-forms/tests/fixtures/recorded/driver.asn"))
        (text (resultOr (fileReadString fixturePath) ""))
        (lines (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:case ")) (stringSplit text "\n")))
        (cases (map parseCase lines))
        (t (fold (fn [(acc Tally) (c CaseSpec)] -> Tally (checkCase! root stubs host mainPath c acc))
                 (Tally :cases 0 :failures 0 :packNotPorted 0 :batchDiverged 0 :packFlagFailures 0) cases))
        (rejectedDrive (main/driveOutcome! root (list) 1 true
                        (main/Drive :lines (list) :failed (list) :heads (list) :errs 0 :stop "")
                        (k/parseStep "(:write :file \"x.txt\" :content \"y\")")
                        (ops/StepOutcome :lines (list "(:step :id 1 :op \"write\" :status \"rejected\")") :errCount 0)))
        (rejectedWithZeroErrors (main/driveExitCode rejectedDrive))
        (rejectionShortCircuits (stringContains? rejectedDrive.stop "short-circuit after step 1"))
        (mixedDrive (driveWrite root (list "(:step :id 1 :op \"write\" :status \"ok\")" "(:step :id 1 :op \"write\" :status \"rejected\")")))
        (numericDrive (driveWrite root (list "(:step :id 1 :op \"write\" :count 3 :status \"rejected\")")))
        (statusKeyDrive (driveWrite root (list "(:step :id 1 :op \"write\" :status-x \"a\" :status \"rejected\")")))
        (escapedDrive (driveWrite root (list "  (:step :id 2 :op \"w\\\"x\" :file \"a b\" :reason \"q\\\\\" :status \"rejected\" :error \"E\")")))
        (gone (cleanStubs! stubs))]
    (do
      (println (str "(:driverParity :cases " (stringFromInt64 t.cases)
                    " :failures " (stringFromInt64 t.failures)
                    " :packNotPorted " (stringFromInt64 t.packNotPorted)
                    " :batchDiverged " (stringFromInt64 t.batchDiverged) ")"))
      (assert (= t.cases 52) "recorded fixture has 52 cases")
      (assert (= rejectedWithZeroErrors 1) "a rejected step with zero reported errors exits 1 through the driver")
      (assert rejectionShortCircuits "a rejected mutating step short-circuits the sequential driver")
      (assert (= mixedDrive.failed (list false false)) "failed flags follow the step error count, not its rejected lines")
      (assert (= (main/driveExitCode mixedDrive) 1) "an ok line beside a rejected line with zero errors still exits 1")
      (assert (stringContains? mixedDrive.stop "short-circuit after step 1") "a rejected line among ok lines short-circuits the sequential driver")
      (assert (= (main/driveExitCode numericDrive) 0) "a step with an unquoted value before :status is not rejected under _STEP_REJECTED")
      (assert (stringEmpty? numericDrive.stop) "a step with an unquoted value before :status does not short-circuit")
      (assert (= (main/driveExitCode statusKeyDrive) 0) "a status-prefixed key before :status is not rejected under _STEP_REJECTED")
      (assert (= (main/driveExitCode escapedDrive) 1) "escaped quotes, quoted fields and leading spaces still mark a rejected step")
      (assert (= t.failures 0) "legacy parity cases and intentional FR1 rejections must match their fixture outputs")
      (assert (= t.packFlagFailures 0) "pack cases 4 through 9 pass every requested flag to the pack executable")
      (assert (stringContains? text ":legacyCases \"1-12,21,27,33-34,36-41,43-45,49,51-52\" :authoredRejections \"13-20,22-26,28-32,35,42,46-48,50\"") "fixture identifies its legacy reference and authored rejection cases")
      (assert (not (stringContains? text "env_ASL_GATEWAY_PORT")) "fixture leaves the controlled closed gateway port to the test harness")
      (assert (= t.packNotPorted 0) "no pack case should report ERR_NOT_PORTED")
      (assert (= t.batchDiverged 0) "no mixed batch should diverge")
      true))
