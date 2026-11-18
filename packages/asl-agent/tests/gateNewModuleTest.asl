(module aslAgent/tests/gateNewModuleTest
  :x [runTests]
  :i [(aslAgent/gateIntegrity :a gi) (aslAgent/gates :a g) (asl-tools/fleet/run :a fr)])

; (:m :ref GATEINTEGRITY-NEW-MODULE :do "a new module with a real test passes the integrity check by a mutant that fails the test by assertion, not by a compile-only revert; a vacuous test still fails; a module that exists at the revert revision keeps the revert check")
fn src -> String
  "(module std/deque\n  :x [size]\n  :i [])\n\nfn helper n: Int64 -> Int64\n  (+ n 1)\n\nfn size n: Int64 -> Int64\n  (helper n)\n"

; (:m :ref GATEINTEGRITY-NEW-MODULE :do "a new module with one export the mutant cannot cut (Bytes has no default here); its test checks only that export, so a green gate on the mutant proves nothing about the test")
fn partialSrc -> String
  "(module std/deque\n  :x [size blob]\n  :i [])\n\nfn size n: Int64 -> Int64\n  (+ n 1)\n\nfn blob -> Bytes\n  (stringToBytes \"ab\")\n"

fn partialGate -> String
  "if [ ! -f src/deque.asl ]; then echo 'ERR_UNRESOLVED_SYMBOL blob'; exit 1; fi\nif /usr/bin/grep -q 'stringToBytes' src/deque.asl; then echo '(:gate :asserts 1 :failed 0)'; exit 0; fi\necho 'ERR_ASSERT: assertion failed: blob'; echo '(:gate :asserts 1 :failed 1)'; exit 1\n"

fn cutSrc -> String
  "(module std/m\n  :x [s r p q]\n  :i [])\n\nfn s x: Str -> Str\n  (str x x)\n\nfn r x: Int64 -> (Result Int64 Str)\n  (ok x)\n\nfn p x: Int64 -> (Pair I64 (List Str))\n  (pair x (list))\n\nfn q x: Int64 -> (Pair Int64 Node)\n  (keepQ x)\n"

fn realGate -> String
  "if [ ! -f src/deque.asl ]; then echo 'ERR_UNRESOLVED_SYMBOL size'; exit 1; fi\nif /usr/bin/grep -q '(helper n)' src/deque.asl; then echo '(:gate :asserts 1 :failed 0)'; exit 0; fi\necho 'ERR_ASSERT: assertion failed: size 1 is 2'; echo '(:gate :asserts 1 :failed 1)'; exit 1\n"

fn vacuousGate -> String
  "if [ ! -f src/deque.asl ]; then echo 'ERR_UNRESOLVED_SYMBOL size'; exit 1; fi\necho '(:gate :asserts 1 :failed 0)'; exit 0\n"

fn compileGate -> String
  "if [ ! -f src/deque.asl ]; then echo 'ERR_UNRESOLVED_SYMBOL size'; exit 1; fi\nif /usr/bin/grep -q '(helper n)' src/deque.asl; then echo '(:gate :asserts 1 :failed 0)'; exit 0; fi\necho 'ERR_UNKNOWN_SYMBOL cut'; exit 1\n"

fn ! fixture! base: String tag: String gate: String -> String
  (let [root (str base "/" tag)
        made (and (ok? (dirCreate (str root "/src"))) (and (ok? (fileWrite (str root "/src/deque.asl") (src))) (ok? (fileWrite (str root "/gate.sh") gate))))]
    (if made root ""))

fn green -> (List g/GateResult)
  (list (g/makeGateResult "sh gate.sh" 0 "(:gate :asserts 1 :failed 0)" "" false 1))

fn ! check! root: String -> (Pair Bool String)
  (gi/gateIntegrityWithChanged! (list "sh gate.sh") root (green) 60 none (list "src/deque.asl") none "HEAD" none)

fn ! git! root: String args: (List String) -> Bool
  (= (fr/runOneLimited (fr/job (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@t" "-c" "commit.gpgsign=false") args) root (list "PATH=/usr/bin:/bin" "GIT_CONFIG_NOSYSTEM=1")) (fr/limits 60 4)).exit 0)

fn ! runTests -> Bool
  (let [base (str (optionOr (envGet "TMPDIR") "/tmp") "/gateNewModule" (stringFromInt64 (monotonicNs)))
        partRoot (fixture! base "partial" (partialGate))
        partWrote (ok? (fileWrite (str partRoot "/src/deque.asl") (partialSrc)))
        part (check! partRoot)
        partKept (resultOr (fileReadString (str partRoot "/src/deque.asl")) "")
        cut (gi/cutExports (cutSrc))
        realRoot (fixture! base "real" (realGate))
        real (check! realRoot)
        kept (resultOr (fileReadString (str realRoot "/src/deque.asl")) "")
        vacRoot (fixture! base "vacuous" (vacuousGate))
        vac (check! vacRoot)
        cmpRoot (fixture! base "noCompile" (compileGate))
        cmp (check! cmpRoot)
        oldRoot (fixture! base "existing" (realGate))
        broken (ok? (fileWrite (str oldRoot "/src/deque.asl") (stringReplace (src) "(helper n)\n" "(+ n 2)\n")))
        committed (and broken (and (git! oldRoot (list "init" "-q")) (and (git! oldRoot (list "add" "src/deque.asl" "gate.sh")) (git! oldRoot (list "commit" "-q" "-m" "base")))))
        changed (and committed (ok? (fileWrite (str oldRoot "/src/deque.asl") (src))))
        old (check! oldRoot)
        cleaned (ok? (pathRemove base))]
    (do
      (assert (and (pairFirst real) (and (stringContains? (pairSecond real) ":revertKind mutant") (not (stringContains? (pairSecond real) ":revertKind compile")))) (str "a new module whose real test fails on its mutant passes as written, not on a compile-only revert: " (pairSecond real)))
      (assert (= kept (src)) "the module is restored byte for byte after the mutant run")
      (assert (and (not (pairFirst vac)) (stringContains? (pairSecond vac) "(:gateVacuous ")) (str "a new module whose test passes on the mutant still fails the check as vacuous: " (pairSecond vac)))
      (assert (and changed (and (pairFirst old) (not (stringContains? (pairSecond old) ":revertKind mutant")))) (str "a module that exists at the revert revision keeps the revert check: " (pairSecond old)))
      (assert (and (pairFirst cmp) (stringContains? (pairSecond cmp) ":revertKind compile")) (str "a mutant that does not compile proves nothing and keeps the compile answer: " (pairSecond cmp)))
      (assert (and partWrote (and (pairFirst part) (and (stringContains? (pairSecond part) ":revertKind compile") (not (stringContains? (pairSecond part) "(:gateVacuous "))))) (str "a mutant that leaves an export uncut and stays green proves nothing: the compile answer stands, not gateVacuous: " (pairSecond part)))
      (assert (= partKept (partialSrc)) "the partial module is restored byte for byte after the mutant run")
      (assert (and (stringContains? cut "fn s x: Str -> Str\n  \"\"\n") (and (stringContains? cut "-> (Result Int64 Str)\n  (err \"\")\n") (stringContains? cut "-> (Pair I64 (List Str))\n  (pair 0 (list))\n"))) (str "Str, a Result with a string error and a Pair of defaultable types are cut to defaults: " cut))
      (assert (stringContains? cut "-> (Pair Int64 Node)\n  (keepQ x)") "a Pair with a member that has no default keeps its body")
      (assert cleaned "the fixture directory was removed")
      true))
