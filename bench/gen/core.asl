(module aslBench/gen/core
  :x [Sx sxAtom sxStr sxList Case Task Grade Req Reply Config Trial Turn Outcome RunState Card
      charAt slice sliceFrom clip asnQuote readSx readForms sxItems sxText kwFind kwText kwInt kwBool kwList
      loadTask loadTasks renderAsl renderPy renderTs snake armLang allArms armKnown?
      aslHarness pyHarness tsHarness extractCode stripModuleHeader parenToBracket bracketToParen toWrapFn fromWrapFn
      normaliseAsl toArm sigFor userPrompt repairPrompt exampleLine conventionFor formatFor
      languageSection cardFor parenSubs wrapFnSubs loadCards cardOf sha256Of labArms loadCardsFor
      infraOf settle! promptShaOf reqPromptSha expectedPromptSha hasWord? definesEntry? rowVerdict
      gradeCode! gradeReply! healedPass! healedStage! runTrial! runAll! trialKey trialRow planTrials planSig callCost reqChars
      fakeReply! fakeCaller usdToMicro dateOf toolVersion! removeDir! failingOf headerRow usdText priorSpend headOf stageOfReply]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref FABLE-LANG-01 :do "generation-baseline bench core for asl/EXPERIMENT.md protocol v2: task rows, value rendering per language, graded children under fleet limits, trial loop over a caller, one ASN row per trial")

(enum Sx
  (:c sxAtom [(text String)])
  (:c sxStr [(text String)])
  (:c sxList [(items (List Sx))]))

(schema Case
  (:f name String)
  (:f args (List Sx))
  (:f want Sx))

(schema Task
  (:f id String)
  (:f family String)
  (:f difficulty String)
  (:f statement String)
  (:f entry String)
  (:f entryPy String)
  (:f sigAsl String)
  (:f sigPy String)
  (:f sigTs String)
  (:f examples (List Case))
  (:f cases (List Case)))

(schema Grade
  (:f stage String)
  (:f output String)
  (:f failing (List String)))

(schema Req
  (:f model String)
  (:f arm String)
  (:f task String)
  (:f rep Int64)
  (:f turn Int64)
  (:f system String)
  (:f messages (List (Pair String String)))
  (:f maxTokens Int64)
  (:f sendsLeft Int64 :default 8))

(schema Reply
  (:f text String)
  (:f tokIn Int64)
  (:f tokOut Int64)
  (:f served String)
  (:f error String)
  (:f abandoned Int64 :default 0)
  (:f abandonedIn Int64 :default 0)
  (:f abandonedOut Int64 :default 0))

(schema Config
  (:f root String)
  (:f aslBin String)
  (:f work String)
  (:f out String)
  (:f repairs Int64)
  (:f maxTokens Int64)
  (:f priceIn Int64)
  (:f priceOut Int64)
  (:f capPico Int64)
  (:f checkFirst Bool)
  (:f infraTries Int64 :default 6)
  (:f infraWaitMs Int64 :default 20000))

(schema Trial
  (:f idx Int64)
  (:f arm String)
  (:f task Task)
  (:f model String)
  (:f rep Int64))

(schema Turn
  (:f stage String)
  (:f tokIn Int64)
  (:f tokOut Int64)
  (:f reply String))

(schema Prog
  (:f turns (List Turn))
  (:f healedPass Bool)
  (:f served String)
  (:f error String)
  (:f stripped Bool)
  (:f spent Int64)
  (:f promptSha String :default "")
  (:f abandoned Int64 :default 0)
  (:f abandonedPico Int64 :default 0))

(schema Outcome
  (:f trial Trial)
  (:f turns (List Turn))
  (:f rawPass Bool)
  (:f healedPass Bool)
  (:f solved Bool)
  (:f served String)
  (:f error String)
  (:f wallMs Int64)
  (:f sysTok Int64)
  (:f stripped Bool)
  (:f spent Int64)
  (:f promptSha String :default "")
  (:f abandoned Int64 :default 0)
  (:f abandonedPico Int64 :default 0))

(schema RunState
  (:f spent Int64)
  (:f done Int64)
  (:f skipped Int64)
  (:f callFails Int64)
  (:f stopped String))

(schema Card
  (:f arm String)
  (:f text String)
  (:f sha String)
  (:f tokens Int64))

fn charAt text: String i: Int64 -> String
  (optionOr (stringSlice text i (+ i 1)) "")

fn slice text: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice text a (min b (stringLength text))) "")

fn sliceFrom text: String i: Int64 -> String
  (optionOr (stringSlice text i (stringLength text)) "")

fn clip text: String n: Int64 -> String
  (if (> (stringLength text) n) (slice text 0 n) text)

fn asnQuote s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\t" "\\t") "\r" "\\r") "\"")

fn space? c: String -> Bool
  (or (= c " ") (or (= c "\n") (or (= c "\t") (= c "\r"))))

fn opener? c: String -> Bool
  (or (= c "(") (or (= c "[") (= c "{")))

fn closer? c: String -> Bool
  (or (= c ")") (or (= c "]") (= c "}")))

fn tailrec skipWs text: String i: Int64 -> Int64
  (if (space? (charAt text i)) (skipWs text (+ i 1)) i)

fn tailrec strEnd text: String i: Int64 -> Int64
  (let [(c (charAt text i))]
    (cond
      ((stringEmpty? c) i)
      ((= c "\\") (strEnd text (+ i 2)))
      ((= c "\"") i)
      (else (strEnd text (+ i 1)))))

fn tailrec atomEnd text: String i: Int64 -> Int64
  (let [(c (charAt text i))]
    (if (or (stringEmpty? c) (or (space? c) (or (opener? c) (or (closer? c) (= c "\"")))))
      i
      (atomEnd text (+ i 1))))

fn unescStep st: (Pair String Bool) piece: String -> (Pair String Bool)
  (if (pairSecond st)
    (pair (str (pairFirst st) piece) false)
    (if (stringEmpty? piece)
      (pair (str (pairFirst st) "\\") true)
      (let [(c (charAt piece 0))
            (rest (sliceFrom piece 1))]
        (pair (str (pairFirst st) (cond ((= c "n") "\n") ((= c "t") "\t") ((= c "r") "\r") (else c)) rest) false))))

fn unescape s: String -> String
  (let [(pieces (stringSplit s "\\"))]
    (pairFirst (fold unescStep (pair (optionOr (listHead pieces) "") false) (listDrop pieces 1))))

fn readSx text: String i0: Int64 -> (Result (Pair Sx Int64) String)
  (let [(i (skipWs text i0))
        (c (charAt text i))]
    (cond
      ((stringEmpty? c) (err "unexpected end of text"))
      ((= c "(") (readItems text (+ i 1) (list)))
      ((= c ")") (err (str "unexpected ) at byte " (stringFromInt64 i))))
      ((= c "\"")
        (let [(e (strEnd text (+ i 1)))]
          (if (= (charAt text e) "\"")
            (ok (pair (sxStr (unescape (slice text (+ i 1) e))) (+ e 1)))
            (err "unclosed string"))))
      (else
        (let [(e (atomEnd text i))]
          (if (= e i)
            (err (str "unexpected character at byte " (stringFromInt64 i)))
            (ok (pair (sxAtom (slice text i e)) e)))))))

fn readItems text: String i0: Int64 acc: (List Sx) -> (Result (Pair Sx Int64) String)
  (let [(i (skipWs text i0))
        (c (charAt text i))]
    (cond
      ((stringEmpty? c) (err "unclosed ("))
      ((= c ")") (ok (pair (sxList acc) (+ i 1))))
      (else
        (match (readSx text i)
          ((err e) (err e))
          ((ok p) (readItems text (pairSecond p) (listAppend acc (list (pairFirst p)))))))))

fn readFormsFrom text: String i0: Int64 acc: (List Sx) -> (Result (List Sx) String)
  (let [(i (skipWs text i0))]
    (if (stringEmpty? (charAt text i))
      (ok acc)
      (match (readSx text i)
        ((err e) (err e))
        ((ok p) (readFormsFrom text (pairSecond p) (listAppend acc (list (pairFirst p))))))))

fn readForms text: String -> (Result (List Sx) String)
  (readFormsFrom text 0 (list))

fn sxItems v: Sx -> (List Sx)
  (match v
    ((sxList items) items)
    (_ (list)))

fn sxText v: Sx -> String
  (match v
    ((sxAtom t) t)
    ((sxStr t) t)
    (_ ""))

fn tailrec kwFind items: (List Sx) key: String -> (Option Sx)
  (match (listHead items)
    ((none) (none))
    ((some h)
      (let [(rest (listDrop items 1))]
        (match h
          ((sxAtom t) (if (= t key) (listHead rest) (kwFind rest key)))
          (_ (kwFind rest key))))))

fn kwText items: (List Sx) key: String -> String
  (match (kwFind items key)
    ((some v) (sxText v))
    ((none) ""))

fn kwInt items: (List Sx) key: String -> Int64
  (optionOr (stringToInt64 (kwText items key)) 0)

fn kwBool items: (List Sx) key: String -> Bool
  (= (kwText items key) "true")

fn kwList items: (List Sx) key: String -> (List Sx)
  (match (kwFind items key)
    ((some v) (sxItems v))
    ((none) (list)))

fn nth items: (List Sx) i: Int64 -> Sx
  (optionOr (listGet items i) (sxAtom ""))

fn casesOf prefix: String rows: (List Sx) -> (List Case)
  (map (fn [(i Int64)] -> Case
         (let [(row (sxItems (nth rows i)))]
           (Case :name (str prefix (stringFromInt64 (+ i 1))) :args (kwList row ":args") :want (optionOr (kwFind row ":want") (sxAtom "")))))
       (range 0 (listLength rows)))

fn taskOf v: Sx -> (Result Task String)
  (let [(items (sxItems v))
        (id (kwText items ":id"))
        (t (Task :id id :family (kwText items ":family") :difficulty (kwText items ":difficulty") :statement (kwText items ":statement")
                 :entry (kwText items ":entry") :entryPy (kwText items ":entryPy")
                 :sigAsl (kwText items ":sigAsl") :sigPy (kwText items ":sigPy") :sigTs (kwText items ":sigTs")
                 :examples (casesOf "e" (kwList items ":examples")) :cases (casesOf "c" (kwList items ":cases"))))]
    (cond
      ((stringEmpty? id) (err "task row has no :id"))
      ((or (stringEmpty? t.entry) (stringEmpty? t.entryPy)) (err (str id ": missing :entry or :entryPy")))
      ((or (stringEmpty? t.sigAsl) (or (stringEmpty? t.sigPy) (stringEmpty? t.sigTs))) (err (str id ": missing a signature")))
      ((stringEmpty? t.statement) (err (str id ": missing :statement")))
      ((!= (listLength t.examples) 2) (err (str id ": expected 2 examples")))
      ((!= (listLength t.cases) 6) (err (str id ": expected 6 graded cases")))
      (else (ok t))))

fn ! loadTask root: String id: String -> (Result Task String)
  (match (fileReadString (str root "/asl/bench/gen/tasks/" id ".asn"))
    ((err e) (err e))
    ((ok text)
      (match (readSx text 0)
        ((err e) (err (str id ": " e)))
        ((ok p) (taskOf (pairFirst p))))))

fn ! loadTasks root: String -> (Result (List Task) String)
  (match (dirList (str root "/asl/bench/gen/tasks"))
    ((err e) (err e))
    ((ok names)
      (fold (fn [(acc (Result (List Task) String)) (name String)] -> (Result (List Task) String)
              (match acc
                ((err e) (err e))
                ((ok ts)
                  (if (stringEndsWith? name ".asn")
                    (match (loadTask root (stringReplace name ".asn" ""))
                      ((err e) (err e))
                      ((ok t) (ok (listAppend ts (list t)))))
                    (ok ts)))))
            (ok (list))
            names)))

fn headOf v: Sx -> String
  (sxText (nth (sxItems v) 0))

fn restOf v: Sx -> (List Sx)
  (listDrop (sxItems v) 1)

fn fieldName f: Sx -> String
  (sxText (nth (sxItems f) 0))

fn fieldValue f: Sx -> Sx
  (nth (sxItems f) 1)

fn joinMap f: (fn [Sx] -> String) xs: (List Sx) sep: String -> String
  (stringJoin (map f xs) sep)

fn snake name: String -> String
  (stringJoin (map (fn [(c String)] -> String (if (!= c (stringLower c)) (str "_" (stringLower c)) c)) (stringChars name)) "")

fn capitalize name: String -> String
  (str (stringUpper (slice name 0 1)) (sliceFrom name 1))

fn renderAsl v: Sx -> String
  (match v
    ((sxStr t) (asnQuote t))
    ((sxAtom t) t)
    ((sxList items)
      (let [(h (headOf v))
            (rest (restOf v))]
        (cond
          ((= h "list") (if (listEmpty? rest) "(list)" (str "(list " (joinMap renderAsl rest " ") ")")))
          ((= h "tuple") (str "(pair " (joinMap renderAsl rest " ") ")"))
          ((= h "some") (str "(some " (renderAsl (nth rest 0)) ")"))
          ((= h "none") "(none)")
          ((= h "ok") (str "(ok " (renderAsl (nth rest 0)) ")"))
          ((= h "dict")
            (if (listEmpty? rest)
              "(mapEmpty)"
              (str "(mapFromPairs (list "
                   (joinMap (fn [(e Sx)] -> String (str "(pair " (renderAsl (fieldNameSx e)) " " (renderAsl (fieldValue e)) ")")) rest " ")
                   "))")))
          ((= h "tag") (str "(" (sxText (nth rest 1)) ")"))
          ((= h "variant")
            (if (listEmpty? (listDrop rest 1))
              (str "(" (sxText (nth rest 0)) ")")
              (str "(" (sxText (nth rest 0)) " " (joinMap (fn [(f Sx)] -> String (renderAsl (fieldValue f))) (listDrop rest 1) " ") ")")))
          ((= h "record")
            (str "(" (sxText (nth rest 0)) " "
                 (joinMap (fn [(f Sx)] -> String (str ":" (fieldName f) " " (renderAsl (fieldValue f)))) (listDrop rest 1) " ")
                 ")"))
          (else (str "(unknownValue " h ")"))))))

fn fieldNameSx f: Sx -> Sx
  (nth (sxItems f) 0)

fn pyAtom t: String -> String
  (cond
    ((= t "true") "True")
    ((= t "false") "False")
    (else t))

fn renderPy v: Sx -> String
  (match v
    ((sxStr t) (asnQuote t))
    ((sxAtom t) (pyAtom t))
    ((sxList items)
      (let [(h (headOf v))
            (rest (restOf v))]
        (cond
          ((= h "list") (str "[" (joinMap renderPy rest ", ") "]"))
          ((= h "tuple") (str "(" (joinMap renderPy rest ", ") ")"))
          ((= h "some") (renderPy (nth rest 0)))
          ((= h "none") "None")
          ((= h "ok") (renderPy (nth rest 0)))
          ((= h "dict") (str "{" (joinMap (fn [(e Sx)] -> String (str (renderPy (fieldNameSx e)) ": " (renderPy (fieldValue e)))) rest ", ") "}"))
          ((= h "tag") (str (sxText (nth rest 0)) "." (stringUpper (snake (sxText (nth rest 1))))))
          ((= h "variant")
            (str (capitalize (sxText (nth rest 0))) "("
                 (joinMap (fn [(f Sx)] -> String (str (snake (fieldName f)) "=" (renderPy (fieldValue f)))) (listDrop rest 1) ", ")
                 ")"))
          ((= h "record")
            (str (sxText (nth rest 0)) "("
                 (joinMap (fn [(f Sx)] -> String (str (snake (fieldName f)) "=" (renderPy (fieldValue f)))) (listDrop rest 1) ", ")
                 ")"))
          (else (str "unknown_value_" h))))))

fn renderTs v: Sx -> String
  (match v
    ((sxStr t) (asnQuote t))
    ((sxAtom t) t)
    ((sxList items)
      (let [(h (headOf v))
            (rest (restOf v))]
        (cond
          ((or (= h "list") (= h "tuple")) (str "[" (joinMap renderTs rest ", ") "]"))
          ((= h "some") (renderTs (nth rest 0)))
          ((= h "none") "undefined")
          ((= h "ok") (renderTs (nth rest 0)))
          ((= h "dict")
            (if (listEmpty? rest)
              "new Map()"
              (str "new Map([" (joinMap (fn [(e Sx)] -> String (str "[" (renderTs (fieldNameSx e)) ", " (renderTs (fieldValue e)) "]")) rest ", ") "])")))
          ((= h "tag") (asnQuote (sxText (nth rest 1))))
          ((= h "variant")
            (str "{ kind: " (asnQuote (sxText (nth rest 0)))
                 (stringJoin (map (fn [(f Sx)] -> String (str ", " (fieldName f) ": " (renderTs (fieldValue f)))) (listDrop rest 1)) "")
                 " }"))
          ((= h "record")
            (str "{ " (joinMap (fn [(f Sx)] -> String (str (fieldName f) ": " (renderTs (fieldValue f)))) (listDrop rest 1) ", ") " }"))
          (else (str "unknownValue_" h))))))

fn allArms -> (List String)
  (list "py" "ts" "asl" "aslParen" "aslWrapFn")

fn labArms -> (List String)
  (list "aslCardAsn" "aslCardContrast" "aslCardExample" "aslCardMin" "aslCardStr" "aslCardSig" "aslCardTextEx")

fn armKnown? arm: String -> Bool
  (or (listContains? (allArms) arm) (listContains? (labArms) arm))

fn armLang arm: String -> String
  (cond
    ((= arm "py") "py")
    ((= arm "ts") "ts")
    (else "asl"))

fn fails? c: Case -> Bool
  (= (headOf c.want) "fails")

fn callAsl entry: String args: (List Sx) -> String
  (if (listEmpty? args) (str "(" entry ")") (str "(" entry " " (joinMap renderAsl args " ") ")"))

fn callPy entry: String args: (List Sx) -> String
  (str entry "(" (joinMap renderPy args ", ") ")")

fn callTs entry: String args: (List Sx) -> String
  (str entry "(" (joinMap renderTs args ", ") ")")

fn nestAnd names: (List String) -> String
  (match (listHead names)
    ((none) "true")
    ((some h) (if (= (listLength names) 1) h (str "(and " h " " (nestAnd (listDrop names 1)) ")"))))

fn aslCaseBind c: Case entry: String -> String
  (str "(g" c.name " (genCase " (asnQuote c.name) " "
       (if (fails? c)
         (str "(match " (callAsl entry c.args) " ((err _) true) ((ok _) false))")
         (str "(= " (callAsl entry c.args) " " (renderAsl c.want) ")"))
       "))")

fn aslHarness modName: String code: String t: Task cases: (List Case) -> String
  (str "(module " modName " :x [runTests])\n\n" code "\n\n"
       "fn genCase name: String passed: Bool -> Bool\n"
       "  (if passed true (do (println \"FAILCASE\" name) false))\n\n"
       "fn runTests -> Bool\n"
       "  (let [" (stringJoin (map (fn [(c Case)] -> String (aslCaseBind c t.entry)) cases) "\n        ") "]\n"
       "    (assert " (nestAnd (map (fn [(c Case)] -> String (str "g" c.name)) cases)) " \"graded cases\")\n"
       "    true)\n")

fn pyCaseLine c: Case entry: String -> String
  (if (fails? c)
    (str "    chk_fails(" (asnQuote c.name) ", lambda: " (callPy entry c.args) ")\n")
    (str "    chk(" (asnQuote c.name) ", lambda: " (callPy entry c.args) ", " (renderPy c.want) ")\n"))

fn pyHarness code: String t: Task cases: (List Case) -> String
  (str code "\n\n\n"
       "def __gen_main():\n"
       "    import sys\n"
       "    fails = []\n\n"
       "    def chk(name, thunk, want):\n"
       "        try:\n"
       "            got = thunk()\n"
       "        except Exception as exc:\n"
       "            print(\"FAILCASE\", name, \"raised\", type(exc).__name__ + \":\", exc)\n"
       "            fails.append(name)\n"
       "            return\n"
       "        if got != want or isinstance(got, bool) != isinstance(want, bool):\n"
       "            print(\"FAILCASE\", name)\n"
       "            fails.append(name)\n\n"
       "    def chk_fails(name, thunk):\n"
       "        try:\n"
       "            thunk()\n"
       "        except ValueError:\n"
       "            return\n"
       "        except Exception as exc:\n"
       "            print(\"FAILCASE\", name, \"raised\", type(exc).__name__ + \":\", exc)\n"
       "            fails.append(name)\n"
       "            return\n"
       "        print(\"FAILCASE\", name, \"did not fail\")\n"
       "        fails.append(name)\n\n"
       (stringJoin (map (fn [(c Case)] -> String (pyCaseLine c t.entryPy)) cases) "")
       "    print(\"GENRESULT\", \"fail\" if fails else \"pass\", len(fails))\n"
       "    sys.exit(1 if fails else 0)\n\n\n"
       "__gen_main()\n")

fn tsCaseLine c: Case entry: String -> String
  (if (fails? c)
    (str "__genChkFails(" (asnQuote c.name) ", () => " (callTs entry c.args) ");\n")
    (str "__genChk(" (asnQuote c.name) ", () => " (callTs entry c.args) ", " (renderTs c.want) ");\n"))

fn tsHarness code: String t: Task cases: (List Case) -> String
  (str code "\n\n"
       "function __genDeepEq(a: unknown, b: unknown): boolean {\n"
       "  if (a === b) return true;\n"
       "  if (a instanceof Map && b instanceof Map) {\n"
       "    if (a.size !== b.size) return false;\n"
       "    for (const [k, v] of a) { if (!b.has(k) || !__genDeepEq(v, b.get(k))) return false; }\n"
       "    return true;\n"
       "  }\n"
       "  if (Array.isArray(a) && Array.isArray(b)) {\n"
       "    if (a.length !== b.length) return false;\n"
       "    for (let i = 0; i < a.length; i++) { if (!__genDeepEq(a[i], b[i])) return false; }\n"
       "    return true;\n"
       "  }\n"
       "  if (typeof a === \"object\" && typeof b === \"object\" && a !== null && b !== null) {\n"
       "    if (Array.isArray(a) || Array.isArray(b) || a instanceof Map || b instanceof Map) return false;\n"
       "    const ra = a as Record<string, unknown>;\n"
       "    const rb = b as Record<string, unknown>;\n"
       "    for (const k of new Set<string>([...Object.keys(ra), ...Object.keys(rb)])) { if (!__genDeepEq(ra[k], rb[k])) return false; }\n"
       "    return true;\n"
       "  }\n"
       "  return false;\n"
       "}\n"
       "const __genFails: string[] = [];\n"
       "function __genChk(name: string, thunk: () => unknown, want: unknown): void {\n"
       "  let got: unknown;\n"
       "  try { got = thunk(); } catch (e) { console.log(\"FAILCASE \" + name + \" threw \" + String(e)); __genFails.push(name); return; }\n"
       "  if (!__genDeepEq(got, want)) { console.log(\"FAILCASE \" + name); __genFails.push(name); }\n"
       "}\n"
       "function __genChkFails(name: string, thunk: () => unknown): void {\n"
       "  try { thunk(); } catch (e) { return; }\n"
       "  console.log(\"FAILCASE \" + name + \" did not fail\"); __genFails.push(name);\n"
       "}\n"
       (stringJoin (map (fn [(c Case)] -> String (tsCaseLine c t.entry)) cases) "")
       "console.log(\"GENRESULT \" + (__genFails.length > 0 ? \"fail\" : \"pass\") + \" \" + __genFails.length);\n"
       "if (__genFails.length > 0) { (globalThis as any).process.exit(1); }\n"
       "export {};\n")

fn extractCode reply: String -> (Option String)
  (match (stringIndexOf reply "```")
    ((none) (none))
    ((some a)
      (let [(afterTicks (sliceFrom reply (+ a 3)))]
        (match (stringIndexOf afterTicks "\n")
          ((none) (none))
          ((some nl)
            (let [(body (sliceFrom afterTicks (+ nl 1)))]
              (match (stringIndexOf body "```")
                ((none) (none))
                ((some b) (some (slice body 0 b))))))))))

; (:m :ref GEN-OUTPUT-CAP :do "a reply that came back empty because the output cap was reached is its own stage outputCap: a truncated reply carries no code, so it must not be recorded as an extraction failure")
fn stageOfReply text: String tokOut: Int64 maxTokens: Int64 fallback: String -> String
  (if (and (> maxTokens 0) (and (stringEmpty? text) (>= tokOut maxTokens))) "outputCap" fallback)

fn withStage g: Grade s: String -> Grade
  (with g :stage s)

fn tailrec formEndLoop text: String i: Int64 depth: Int64 -> (Option Int64)
  (let [(c (charAt text i))]
    (cond
      ((stringEmpty? c) (none))
      ((= c "\"")
        (let [(e (strEnd text (+ i 1)))]
          (if (stringEmpty? (charAt text e)) (none) (formEndLoop text (+ e 1) depth))))
      ((opener? c) (formEndLoop text (+ i 1) (+ depth 1)))
      ((closer? c) (if (<= depth 1) (some (+ i 1)) (formEndLoop text (+ i 1) (- depth 1))))
      (else (formEndLoop text (+ i 1) depth))))

fn formEnd text: String i: Int64 -> (Option Int64)
  (if (opener? (charAt text i)) (formEndLoop text i 0) (none))

fn stripModuleHeader code: String -> (Pair String Bool)
  (let [(i (skipWs code 0))]
    (if (stringStartsWith? (sliceFrom code i) "(module")
      (match (formEnd code i)
        ((none) (pair code false))
        ((some e) (pair (sliceFrom code (skipWs code e)) true)))
      (pair code false)))

fn tailrec parenToBracketLoop text: String i: Int64 closes: (List Int64) out: String -> String
  (let [(c (charAt text i))]
    (cond
      ((stringEmpty? c) out)
      ((= c "\"")
        (let [(e (strEnd text (+ i 1)))]
          (parenToBracketLoop text (+ e 1) closes (str out (slice text i (+ e 1))))))
      ((and (= c ")") (listContains? closes i)) (parenToBracketLoop text (+ i 1) closes (str out "]")))
      ((= c "(")
        (let [(tokEnd (atomEnd text (+ i 1)))
              (tok (slice text (+ i 1) tokEnd))
              (g (skipWs text tokEnd))]
          (if (and (or (= tok "let") (= tok "fn")) (= (charAt text g) "("))
            (match (formEnd text g)
              ((none) (parenToBracketLoop text (+ i 1) closes (str out c)))
              ((some gEnd) (parenToBracketLoop text (+ g 1) (listAppend closes (list (- gEnd 1))) (str out (slice text i g) "["))))
            (parenToBracketLoop text (+ i 1) closes (str out c)))))
      (else (parenToBracketLoop text (+ i 1) closes (str out c)))))

fn parenToBracket text: String -> String
  (parenToBracketLoop text 0 (list) "")

fn tailrec bracketToParenLoop text: String i: Int64 out: String -> String
  (let [(c (charAt text i))]
    (cond
      ((stringEmpty? c) out)
      ((= c "\"")
        (let [(e (strEnd text (+ i 1)))]
          (bracketToParenLoop text (+ e 1) (str out (slice text i (+ e 1))))))
      ((= c "[")
        (let [(prev (stringTrim out))]
          (if (or (stringEndsWith? prev "(let") (stringEndsWith? prev "(fn"))
            (bracketToParenLoop text (+ i 1) (str out "("))
            (bracketToParenLoop text (+ i 1) (str out (if (= (charAt text (+ i 1)) "]") "(list" "(list "))))))
      ((= c "]") (bracketToParenLoop text (+ i 1) (str out ")")))
      (else (bracketToParenLoop text (+ i 1) (str out c)))))

fn bracketToParen text: String -> String
  (bracketToParenLoop text 0 "")

fn wrapHeader line: String -> String
  (let [(rest (stringTrim (sliceFrom line 3)))
        (arrow (stringIndexOf rest " -> "))
        (head (match arrow ((some a) (slice rest 0 a)) ((none) rest)))
        (ret (match arrow ((some a) (str " -> " (sliceFrom rest (+ a 4)))) ((none) "")))
        (nameEnd (atomEnd head 0))
        (name (slice head 0 nameEnd))
        (params (stringTrim (sliceFrom head nameEnd)))]
    (str "(fn " name " [" params "]" ret))

fn tailrec lastFilled lines: (List String) i: Int64 -> Int64
  (if (< i 0)
    -1
    (if (stringEmpty? (stringTrim (optionOr (listGet lines i) ""))) (lastFilled lines (- i 1)) i))

fn closeLast lines: (List String) -> (List String)
  (let [(i (lastFilled lines (- (listLength lines) 1)))]
    (if (< i 0)
      lines
      (listAppend (listTake lines i) (listAppend (list (str (optionOr (listGet lines i) "") ")")) (listDrop lines (+ i 1))))))

fn wrapStep st: (Pair (List String) Bool) line: String -> (Pair (List String) Bool)
  (let [(acc (pairFirst st))
        (open (pairSecond st))
        (col0 (and (not (stringEmpty? line)) (not (space? (charAt line 0)))))]
    (cond
      ((stringStartsWith? line "fn ") (pair (listAppend (if open (closeLast acc) acc) (list (wrapHeader line))) true))
      (col0 (pair (listAppend (if open (closeLast acc) acc) (list line)) false))
      (else (pair (listAppend acc (list line)) open))))

fn toWrapFn code: String -> String
  (let [(st (fold wrapStep (pair (list) false) (stringLines code)))]
    (stringJoin (if (pairSecond st) (closeLast (pairFirst st)) (pairFirst st)) "\n"))

fn indentLines body: String -> String
  (stringJoin (map (fn [(l String)] -> String (if (stringEmpty? (stringTrim l)) l (str "  " l))) (stringLines body)) "\n")

fn unwrapForm inner: String -> (Option String)
  (let [(nameStart (skipWs inner 2))
        (nameEnd (atomEnd inner nameStart))
        (name (slice inner nameStart nameEnd))
        (p (skipWs inner nameEnd))]
    (if (or (stringEmpty? name) (!= (charAt inner p) "["))
      (none)
      (match (formEnd inner p)
        ((none) (none))
        ((some pEnd)
          (let [(params (stringTrim (slice inner (+ p 1) (- pEnd 1))))
                (a (skipWs inner pEnd))
                (hasRet (= (slice inner a (+ a 2)) "->"))
                (r (if hasRet (skipWs inner (+ a 2)) a))
                (rEnd (if hasRet
                        (if (opener? (charAt inner r)) (optionOr (formEnd inner r) r) (atomEnd inner r))
                        r))
                (ret (if hasRet (str " -> " (slice inner r rEnd)) ""))
                (body (stringTrim (sliceFrom inner rEnd)))]
            (some (str "fn " name (if (stringEmpty? params) "" (str " " params)) ret "\n" (indentLines body))))))))

fn tailrec fromWrapFnLoop text: String i: Int64 out: String -> String
  (if (>= i (stringLength text))
    out
    (let [(lineEnd (match (stringIndexOf (sliceFrom text i) "\n") ((some n) (+ i (+ n 1))) ((none) (stringLength text))))
          (wrapped (if (= (slice text i (+ i 4)) "(fn ")
                     (match (formEnd text i)
                       ((none) (none))
                       ((some e) (match (unwrapForm (slice text (+ i 1) (- e 1))) ((some u) (some (pair u e))) ((none) (none)))))
                     (none)))]
      (match wrapped
        ((some w) (fromWrapFnLoop text (pairSecond w) (str out (pairFirst w))))
        ((none) (fromWrapFnLoop text lineEnd (str out (slice text i lineEnd)))))))

fn fromWrapFn text: String -> String
  (fromWrapFnLoop text 0 "")

fn normaliseAsl arm: String code: String -> (Pair String Bool)
  (stripModuleHeader
    (cond
      ((= arm "aslParen") (parenToBracket code))
      ((= arm "aslWrapFn") (fromWrapFn code))
      (else code)))

fn toArm arm: String code: String -> String
  (cond
    ((= arm "aslParen") (bracketToParen code))
    ((= arm "aslWrapFn") (toWrapFn code))
    (else code))

fn sigFor arm: String t: Task -> String
  (cond
    ((= arm "py") t.sigPy)
    ((= arm "ts") t.sigTs)
    ((= arm "aslWrapFn")
      (stringJoin (map (fn [(l String)] -> String (if (stringStartsWith? l "fn ") (str (wrapHeader l) " body)") l)) (stringLines t.sigAsl)) "\n"))
    (else t.sigAsl))

fn exampleLine arm: String t: Task c: Case -> String
  (let [(lang (armLang arm))]
    (cond
      ((= lang "py") (str (callPy t.entryPy c.args) (if (fails? c) " raises ValueError" (str " returns " (renderPy c.want)))))
      ((= lang "ts") (str (callTs t.entry c.args) (if (fails? c) " throws an Error" (str " returns " (renderTs c.want)))))
      (else (str (callAsl t.entry c.args) (if (fails? c) " returns (err message)" (str " returns " (renderAsl c.want)))))))

fn conventionFor lang: String -> String
  (cond
    ((= lang "py") "Where the task says the function returns nothing, return None. Where it says the function fails, raise ValueError.")
    ((= lang "ts") "Where the task says the function returns nothing, return undefined. Where it says the function fails, throw an Error.")
    (else "Where the task says the function returns nothing, return (none). Where it says the function fails, return (err message) with a String message; a success is then (ok value)."))

fn formatFor lang: String -> String
  (str "Reply with exactly one fenced code block holding the complete solution: the declarations shown in the signature, the function and any helpers. "
       "The grader appends its own tests; write no tests, no example calls and no text outside the block."
       (if (= lang "asl") " Write no module header; the grader supplies it." ""))

fn userPrompt arm: String t: Task -> String
  (str "Task: " t.statement "\n\n"
       "Signature:\n" (sigFor arm t) "\n\n"
       "Examples:\n" (stringJoin (map (fn [(c Case)] -> String (exampleLine arm t c)) t.examples) "\n") "\n\n"
       (conventionFor (armLang arm)) "\n"
       (formatFor (armLang arm)) "\n")

fn repairPrompt g: Grade -> String
  (if (= g.stage "outputCap")
    (str "The reply was cut off at the output token limit before any code block.\n"
         "Reply with a shorter answer, and put the fenced code block first.\n")
    (str "The solution failed at stage " g.stage ".\n"
         "Tool output (first 2000 characters):\n" (clip g.output 2000) "\n"
         (if (listEmpty? g.failing) "" (str "Failing cases: " (stringJoin g.failing ", ") "\n"))
         "Reply with exactly one fenced code block holding the corrected complete solution.\n"))

fn languageSection llms: String -> (Result String String)
  (match (stringIndexOf llms "## The language\n\n")
    ((none) (err "llms.txt has no section: The language"))
    ((some a)
      (let [(body (sliceFrom llms (+ a 18)))]
        (match (stringIndexOf body "\n\n## ")
          ((none) (err "llms.txt: section The language has no end"))
          ((some b) (ok (slice body 0 b)))))))

fn substituteAll text: String subs: (List (Pair String String)) -> (Result String String)
  (fold (fn [(acc (Result String String)) (p (Pair String String))] -> (Result String String)
          (match acc
            ((err e) (err e))
            ((ok t) (if (stringContains? t (pairFirst p))
                      (ok (stringReplace t (pairFirst p) (pairSecond p)))
                      (err (str "card source lacks: " (pairFirst p)))))))
        (ok text)
        subs)

fn parenSubs -> (List (Pair String String))
  (list (pair ":x [exported names] :i [(other/module :a alias)]" ":x (exported names) :i ((other/module :a alias))")
        (pair "(let [(x e)])" "(let ((x e)))")
        (pair "(fn [x] (* x 2))" "(fn (x) (* x 2))")
        (pair "( ) forms, [ ] lists, { } records" "( ) forms and lists, a list being (list a b), and { } records; square brackets are not used")
        (pair "(let [(a 1) (b (+ a 1))] body)" "(let ((a 1) (b (+ a 1))) body)")
        (pair "(fn [x] body)" "(fn (x) body)")
        (pair "(module ws/t :x [runTests])" "(module ws/t :x (runTests))"))

fn wrapFnSubs -> (List (Pair String String))
  (list (pair "A function is a bare line, fn name a: Int64 b: String -> Bool, with its body indented below; that line is not a form, so the body closes only its own parentheses."
              "A function is one form starting in column 0, (fn name [a: Int64 b: String] -> Bool body), closed by its own parenthesis after the body.")
        (pair "and fn main with no -> binds args" "and (fn main [] body) with no -> binds args")
        (pair "with fn runTests -> Bool ending true" "with (fn runTests [] -> Bool body) ending true"))

fn cardFor arm: String llms: String -> (Result String String)
  (cond
    ((= arm "py") (ok "You write Python 3.13 with type hints, using only the standard library."))
    ((= arm "ts") (ok "You write TypeScript that compiles under tsc --strict with target es2022, using only the standard library."))
    (else
      (match (languageSection llms)
        ((err e) (err e))
        ((ok section)
          (cond
            ((= arm "asl") (ok section))
            ((= arm "aslParen") (substituteAll section (parenSubs)))
            ((= arm "aslWrapFn") (substituteAll section (wrapFnSubs)))
            (else (err (str "unknown arm " arm))))))))

fn sha256Of text: String -> String
  (bytesSha256 (stringToBytes text))

fn ! loadCard root: String row: (List Sx) -> (Result Card String)
  (let [(arm (kwText row ":arm"))]
    (match (fileReadString (str root "/asl/bench/gen/" (kwText row ":file")))
      ((err e) (err e))
      ((ok text)
        (if (= (sha256Of text) (kwText row ":sha256"))
          (ok (Card :arm arm :text text :sha (kwText row ":sha256") :tokens (kwInt row ":tokens")))
          (err (str "card " arm " differs from its cards.asn sha256; rerun the cards command and recount tokens"))))))

fn ! loadCards root: String -> (Result (List Card) String)
  (match (fileReadString (str root "/asl/bench/gen/cards.asn"))
    ((err e) (err e))
    ((ok text)
      (match (readForms text)
        ((err e) (err (str "cards.asn: " e)))
        ((ok forms)
          (fold (fn [(acc (Result (List Card) String)) (form Sx)] -> (Result (List Card) String)
                  (match acc
                    ((err e) (err e))
                    ((ok cs)
                      (if (= (headOf form) ":card")
                        (match (loadCard root (sxItems form))
                          ((err e) (err e))
                          ((ok c) (ok (listAppend cs (list c)))))
                        (ok cs)))))
                (ok (list))
                forms)))))

fn ! loadCardRows root: String file: String -> (Result (List Card) String)
  (match (fileReadString (str root "/asl/bench/gen/" file))
    ((err e) (err e))
    ((ok text)
      (match (readForms text)
        ((err e) (err (str file ": " e)))
        ((ok forms)
          (fold (fn [(acc (Result (List Card) String)) (form Sx)] -> (Result (List Card) String)
                  (match acc
                    ((err e) (err e))
                    ((ok cs)
                      (if (= (headOf form) ":card")
                        (match (loadCard root (sxItems form))
                          ((err e) (err e))
                          ((ok c) (ok (listAppend cs (list c)))))
                        (ok cs)))))
                (ok (list))
                forms)))))

fn ! loadCardsFor root: String arms: (List String) -> (Result (List Card) String)
  (match (loadCards root)
    ((err e) (err e))
    ((ok base)
      (if (listAny? (fn [(a String)] -> Bool (listContains? (labArms) a)) arms)
        (match (loadCardRows root "cardLab/cards.asn")
          ((err e) (err e))
          ((ok lab) (ok (listAppend base lab))))
        (ok base))))

fn cardOf cards: (List Card) arm: String -> Card
  (optionOr (listFind (fn [(c Card)] -> Bool (= c.arm arm)) cards) (Card :arm arm :text "" :sha "" :tokens 0))

fn failingOf out: String -> (List String)
  (map (fn [(l String)] -> String (optionOr (listGet (stringSplit l " ") 1) ""))
       (filter (fn [(l String)] -> Bool (stringStartsWith? l "FAILCASE ")) (stringLines out)))

fn cleanOut out: String dir: String -> String
  (stringReplace out (str dir "/") "")

fn ! child! argv: (List String) dir: String env: (List String) timeoutS: Int64 -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "nice" "-n" "10") argv) dir env) (fr/limits timeoutS 16))

fn ! removeDir! dir: String -> Bool
  (if (or (stringEmpty? dir) (or (= dir "/") (not (stringContains? dir "aslBenchGen"))))
    false
    (= (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "/" (fr/childEnv (list))) (fr/limits 60 4)).exit 0))

fn ! toolVersion! argv: (List String) -> String
  (let [(d (child! argv "/" (fr/childEnv (list)) 30))]
    (if (= d.exit 0) (stringTrim d.out) "absent"))

; (:m :ref GENRUN-CROSSWIRE :do "a tool child that says nothing about the program is infrastructure, never a model failure: the launcher reporting a stale or absent native CLI or a refused rebuild, a child ended by the fleet limits (a check waiting on a native CLI rebuild ends at its 30 s limit), and a check that exits non-zero without one diagnostic; the result is the reason, empty when the child judged the program; a compile unit failure naming cand. or candHealed. is the program's own fault -- a healed copy that does not compile is a failed heal at the stage the candidate failed -- never infrastructure, so the run continues.")
fn infraOf d: fr/Done step: String -> String
  (cond
    ((or (and (stringContains? d.out "ERR_NATIVE_")
              (not (or (stringContains? d.out "compile unit failed: cand.")
                       (stringContains? d.out "compile unit failed: candHealed."))))
         (stringContains? d.out ":code rebuildRefused"))
      "nativeCli")
    ((and (not (stringEmpty? d.verdict)) (!= d.verdict "exit")) d.verdict)
    ((and (= step "check")
          (and (!= d.exit 0)
               (not (or (stringContains? d.out "ERR_") (or (stringContains? d.out ":status :failed") (stringContains? d.out ": parse "))))))
      "noDiagnostic")
    (else ""))

fn infraGrade why: String d: fr/Done dir: String -> Grade
  (Grade :stage "infra" :output (str why ": " (clip (cleanOut d.out dir) 300)) :failing (list))

; (:m :ref GENRUN-CROSSWIRE :do "an infra grade is tried again after a wait, up to the given number of attempts; any other grade is final at once")
fn ! settle! tries: Int64 waitMs: Int64 attempt: (fn [Int64] -> Grade) n: Int64 -> Grade
  (let [(g (attempt n))]
    (if (and (= g.stage "infra") (< n tries))
      (do (sleepMs waitMs) (settle! tries waitMs attempt (+ n 1)))
      g))

fn ! cliAlive! cfg: Config -> Bool
  (= (child! (list cfg.aslBin "version") "/" (fr/childEnv (list)) 30).exit 0)

fn ! runAslFile! cfg: Config dir: String path: String -> Grade
  (let [(env (fr/childEnv (list (str "ASL_ROOT=" dir))))
        (chk (if cfg.checkFirst (child! (list cfg.aslBin "check" path) dir env 30) (fr/Done :idx 0 :exit 0 :out "" :ms 0 :verdict "")))
        (chkInfra (infraOf chk "check"))]
    (cond
      ((not (stringEmpty? chkInfra)) (infraGrade chkInfra chk dir))
      ((or (!= chk.exit 0) (stringContains? chk.out ":status :failed"))
        (Grade :stage (if (or (stringContains? chk.out ": parse ") (stringContains? chk.out "ERR_UNBALANCED")) "parse" "check")
               :output (cleanOut chk.out dir) :failing (list)))
      (else (runAslTest! cfg dir path env))))

; (:m :ref GENRUN-CROSSWIRE :do "a test child ended by the limits is the program's own loop when the CLI still answers version, and infrastructure when it does not")
fn ! runAslTest! cfg: Config dir: String path: String env: (List String) -> Grade
  (let [(run (child! (list cfg.aslBin "test" path) dir env 30))
        (runInfra (infraOf run "test"))]
    (cond
      ((= run.exit 0) (Grade :stage "ok" :output (cleanOut run.out dir) :failing (list)))
      ((and (not (stringEmpty? runInfra)) (or (= runInfra "nativeCli") (not (cliAlive! cfg)))) (infraGrade runInfra run dir))
      ((or (stringContains? run.out "FAILCASE") (stringContains? run.out "ERR_ASSERT"))
        (Grade :stage "correct" :output (cleanOut run.out dir) :failing (failingOf run.out)))
      ((or (stringContains? run.out ": parse ") (stringContains? run.out "ERR_UNBALANCED")) (Grade :stage "parse" :output (cleanOut run.out dir) :failing (list)))
      ((and (not cfg.checkFirst) (stringContains? run.out "ERR_")) (Grade :stage "check" :output (cleanOut run.out dir) :failing (list)))
      (else (Grade :stage "execute" :output (cleanOut run.out dir) :failing (list)))))

fn ! gradeAsl! cfg: Config dir: String modName: String code: String t: Task cases: (List Case) -> Grade
  (let [(path (str dir "/" modName ".asl"))]
    (match (fileWrite path (aslHarness modName code t cases))
      ((err e) (Grade :stage "harness" :output e :failing (list)))
      ((ok _) (settle! cfg.infraTries cfg.infraWaitMs (fn [(n Int64)] -> Grade (runAslFile! cfg dir path)) 1))))

fn ! gradePy! cfg: Config dir: String code: String t: Task cases: (List Case) -> Grade
  (let [(path (str dir "/cand.py"))]
    (match (fileWrite path (pyHarness code t cases))
      ((err e) (Grade :stage "harness" :output e :failing (list)))
      ((ok _)
        (let [(run (child! (list "python3" "-I" path) dir (fr/childEnv (list)) 30))
              (out (cleanOut run.out dir))]
          (cond
            ((and (= run.exit 0) (stringContains? run.out "GENRESULT pass")) (Grade :stage "ok" :output out :failing (list)))
            ((stringContains? run.out "GENRESULT fail") (Grade :stage "correct" :output out :failing (failingOf run.out)))
            ((or (stringContains? run.out "SyntaxError") (or (stringContains? run.out "IndentationError") (stringContains? run.out "TabError")))
              (Grade :stage "parse" :output out :failing (list)))
            (else (Grade :stage "execute" :output out :failing (list))))))))

fn ! gradeTs! cfg: Config dir: String code: String t: Task cases: (List Case) -> Grade
  (let [(path (str dir "/cand.ts"))]
    (match (fileWrite path (tsHarness code t cases))
      ((err e) (Grade :stage "harness" :output e :failing (list)))
      ((ok _)
        (let [(env (fr/childEnv (list)))
              (tsc (child! (list "tsc" "--strict" "--target" "es2022" "--module" "commonjs" path) dir env 60))]
          (if (!= tsc.exit 0)
            (Grade :stage (if (stringContains? tsc.out "error TS1") "parse" "check") :output (cleanOut tsc.out dir) :failing (list))
            (let [(run (child! (list "node" (str dir "/cand.js")) dir env 30))
                  (out (cleanOut run.out dir))]
              (cond
                ((and (= run.exit 0) (stringContains? run.out "GENRESULT pass")) (Grade :stage "ok" :output out :failing (list)))
                ((stringContains? run.out "GENRESULT fail") (Grade :stage "correct" :output out :failing (failingOf run.out)))
                (else (Grade :stage "execute" :output out :failing (list))))))))))

fn ! gradeCode! cfg: Config dir: String arm: String t: Task cases: (List Case) code: String -> (Pair Grade Bool)
  (let [(lang (armLang arm))]
    (cond
      ((= lang "py") (pair (gradePy! cfg dir code t cases) false))
      ((= lang "ts") (pair (gradeTs! cfg dir code t cases) false))
      (else
        (let [(n (normaliseAsl arm code))]
          (pair (gradeAsl! cfg dir "cand" (pairFirst n) t cases) (pairSecond n))))))

fn ! gradeReply! cfg: Config dir: String arm: String t: Task reply: String -> (Pair Grade Bool)
  (match (extractCode reply)
    ((none) (pair (Grade :stage "extract" :output "The reply holds no complete fenced code block." :failing (list)) false))
    ((some code) (gradeCode! cfg dir arm t t.cases code)))

; (:m :ref GENRUN-CROSSWIRE :do "the stage of the healed copy: ok, a failing stage, or infra when the heal child or the grade after it was infrastructure through every attempt")
fn ! healedStage! cfg: Config dir: String arm: String t: Task reply: String -> String
  (match (extractCode reply)
    ((none) "extract")
    ((some code)
      (let [(n (normaliseAsl arm code))
            (path (str dir "/candHealed.asl"))]
        (match (fileWrite path (aslHarness "candHealed" (pairFirst n) t t.cases))
          ((err _) "harness")
          ((ok _)
            (settle! cfg.infraTries cfg.infraWaitMs
                     (fn [(k Int64)] -> Grade
                       (let [(healed (child! (list cfg.aslBin "heal" path) dir (fr/childEnv (list (str "ASL_ROOT=" dir))) 30))
                             (why (infraOf healed "heal"))]
                         (if (stringEmpty? why) (runAslFile! cfg dir path) (infraGrade why healed dir))))
                     1).stage)))))

fn ! healedPass! cfg: Config dir: String arm: String t: Task reply: String -> Bool
  (= (healedStage! cfg dir arm t reply) "ok")

fn reqChars r: Req -> Int64
  (+ (stringLength r.system) (listSum (map (fn [(m (Pair String String))] -> Int64 (stringLength (pairSecond m))) r.messages)))

fn callCost cfg: Config tokIn: Int64 tokOut: Int64 -> Int64
  (+ (* tokIn cfg.priceIn) (* tokOut cfg.priceOut))

fn callReserve cfg: Config r: Req -> Int64
  (callCost cfg (/ (reqChars r) 2) r.maxTokens)

fn ! turnLoop! cfg: Config tr: Trial dir: String system: String messages: (List (Pair String String)) turn: Int64 call: (fn [S Req] -> (Pair S Reply)) state: S pr: Prog -> (Pair S Prog)
  (let [(plain (Req :model tr.model :arm tr.arm :task tr.task.id :rep tr.rep :turn turn :system system :messages messages :maxTokens cfg.maxTokens))
        (req (with plain :sendsLeft (max 1 (/ (- cfg.capPico pr.spent) (max 1 (callReserve cfg plain))))))]
    (if (> (+ pr.spent (callReserve cfg req)) cfg.capPico)
      (pair state (with pr :error "budget"))
      (let [(res (call state req))
            (state2 (pairFirst res))
            (rep (pairSecond res))
            (lost (callCost cfg rep.abandonedIn rep.abandonedOut))
            (spent2 (+ (+ pr.spent (callCost cfg rep.tokIn rep.tokOut)) lost))
            (pa (with pr :abandoned (+ pr.abandoned rep.abandoned) :abandonedPico (+ pr.abandonedPico lost)))]
        (if (not (stringEmpty? rep.error))
          (pair state2 (with pa :error (str "call: " rep.error) :spent spent2))
          (let [(gr (gradeReply! cfg dir tr.arm tr.task rep.text))
                (g0 (pairFirst gr))
                (stage (stageOfReply rep.text rep.tokOut cfg.maxTokens g0.stage))
                (g (withStage g0 stage))
                (healStage (cond
                             ((!= turn 1) "kept")
                             ((= stage "ok") "ok")
                             ((and (= (armLang tr.arm) "asl") (not (listContains? (list "extract" "infra" "outputCap") stage))) (healedStage! cfg dir tr.arm tr.task rep.text))
                             (else "none")))
                (healed (if (= turn 1) (= healStage "ok") pr.healedPass))
                (pr2 (with pa :turns (listAppend pr.turns (list (Turn :stage g.stage :tokIn rep.tokIn :tokOut rep.tokOut :reply rep.text)))
                              :healedPass healed :served rep.served :stripped (or pr.stripped (pairSecond gr)) :spent spent2
                              :promptSha (if (= turn 1) (reqPromptSha req) pr.promptSha)))]
            (cond
              ((= g.stage "infra") (pair state2 (with pa :error (str "infra: " (clip g.output 300)) :spent spent2)))
              ((= healStage "infra") (pair state2 (with pa :error "infra: the healed copy could not be graded" :spent spent2)))
              ((or (= g.stage "ok") (> turn cfg.repairs)) (pair state2 pr2))
              (else
                (turnLoop! cfg tr dir system
                           (listAppend messages (list (pair "assistant" rep.text) (pair "user" (repairPrompt g))))
                           (+ turn 1) call state2 pr2))))))))

fn stageAt turns: (List Turn) i: Int64 -> String
  (match (listGet turns i)
    ((some t) t.stage)
    ((none) "none"))

fn ! runTrial! cfg: Config cards: (List Card) tr: Trial call: (fn [S Req] -> (Pair S Reply)) state: S spent: Int64 -> (Pair S Outcome)
  (let [(dir (str cfg.work "/t" (stringFromInt64 tr.idx)))
        (made (dirCreate dir))
        (conf (fileWrite (str dir "/.asl.config.asn") "(:aslConfig :workspace \"aslBenchGenSandbox\")"))
        (card (cardOf cards tr.arm))
        (t0 (monotonicNs))
        (res (turnLoop! cfg tr dir card.text (list (pair "user" (userPrompt tr.arm tr.task))) 1 call state
                        (Prog :turns (list) :healedPass false :served "" :error "" :stripped false :spent spent)))
        (pr (pairSecond res))
        (n (listLength pr.turns))]
    (pair (pairFirst res)
          (Outcome :trial tr :turns pr.turns :rawPass (= (stageAt pr.turns 0) "ok") :healedPass pr.healedPass
                   :solved (and (> n 0) (= (stageAt pr.turns (- n 1)) "ok"))
                   :served pr.served :error pr.error :wallMs (/ (- (monotonicNs) t0) 1000000) :sysTok card.tokens
                   :stripped pr.stripped :spent pr.spent :promptSha pr.promptSha :abandoned pr.abandoned :abandonedPico pr.abandonedPico)))

; (:m :ref GENRUN-CROSSWIRE :do "a row carries the digest of the prompt its first call sent: sha256 of the card digest, a line break and the user prompt; the scorer rebuilds it from the header card digest and the task and refuses a row whose digest differs")
fn promptShaOf cardSha: String user: String -> String
  (sha256Of (str cardSha "\n" user))

fn reqPromptSha r: Req -> String
  (promptShaOf (sha256Of r.system) (match (listHead r.messages) ((some m) (pairSecond m)) ((none) "")))

fn expectedPromptSha cardSha: String arm: String t: Task -> String
  (promptShaOf cardSha (userPrompt arm t))

fn wordChar? c: String -> Bool
  (or (and (>= c "a") (<= c "z")) (or (and (>= c "A") (<= c "Z")) (or (and (>= c "0") (<= c "9")) (= c "_"))))

fn tailrec hasWord? text: String name: String -> Bool
  (match (if (stringEmpty? name) (none) (stringIndexOf text name))
    ((none) false)
    ((some i)
      (if (and (not (wordChar? (if (= i 0) "" (charAt text (- i 1))))) (not (wordChar? (charAt text (+ i (stringLength name))))))
        true
        (hasWord? (sliceFrom text (+ i 1)) name))))

fn definesEntry? text: String name: String -> Bool
  (or (hasWord? text (str "fn " name)) (or (hasWord? text (str "def " name)) (hasWord? text (str "function " name))))

fn ownEntry arm: String t: Task -> String
  (if (= (armLang arm) "py") t.entryPy t.entry)

fn otherEntry arm: String t: Task -> String
  (if (= (armLang arm) "py") t.entry t.entryPy)

fn foreignTask tasks: (List Task) arm: String own: Task reply: String -> String
  (if (hasWord? reply (ownEntry arm own))
    ""
    (match (listFind (fn [(t Task)] -> Bool
                       (if (= t.id own.id)
                         (and (!= (otherEntry arm t) (ownEntry arm t)) (definesEntry? reply (otherEntry arm t)))
                         (or (definesEntry? reply t.entry) (definesEntry? reply t.entryPy))))
                     tasks)
      ((some t) (if (= t.id own.id) (str t.id " in another arm") t.id))
      ((none) "")))

fn tailrec tokInDrop ins: (List Int64) last: Int64 -> Bool
  (match (listHead ins)
    ((none) false)
    ((some v)
      (cond
        ((<= v 1) (tokInDrop (listDrop ins 1) last))
        ((<= v last) true)
        (else (tokInDrop (listDrop ins 1) v)))))

; (:m :ref GENRUN-CROSSWIRE :do "what a stored trial row says about itself, empty when nothing contradicts its task: a reply that does not name the entry of its task and defines the entry of another task (or of its own task in the spelling of another arm) answers another request; so does a prompt token count that does not grow from one turn to the next, because every turn resends the conversation plus one reply and one repair prompt (a count of 1 marks a reply the runner recorded as cut at max tokens and is skipped)")
fn rowVerdict tasks: (List Task) arm: String taskId: String replies: (List String) tokIns: (List Int64) -> String
  (match (listFind (fn [(t Task)] -> Bool (= t.id taskId)) tasks)
    ((none) "")
    ((some own)
      (let [(named (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map (fn [(r String)] -> String (foreignTask tasks arm own r)) replies)))]
        (cond
          ((not (listEmpty? named)) (str "a reply answers task " (optionOr (listHead named) "")))
          ((tokInDrop tokIns 0) "prompt token counts do not grow turn over turn")
          (else "")))))

fn trialKey tr: Trial -> String
  (str tr.arm "|" tr.task.id "|" tr.model "|" (stringFromInt64 tr.rep))

fn intList xs: (List Int64) -> String
  (str "(" (stringJoin (map stringFromInt64 xs) " ") ")")

fn boolText b: Bool -> String
  (if b "true" "false")

; (:m :ref GENRUN-CROSSWIRE :do "a request left in flight at its limit is billed by the provider though its answer is never read: the caller reports how many it abandoned with the reserve of one call each (half the prompt characters as tokens in, max tokens out), the trial adds that estimate to its spend so the cap sees it, and the row says so; the request carries how many sends the cap still covers, so retries stop at the cap")
fn abandonedText o: Outcome -> String
  (if (= o.abandoned 0) "" (str " :abandoned (:n " (stringFromInt64 o.abandoned) " :estUsd " (asnQuote (usdText o.abandonedPico)) ")"))

fn trialRow o: Outcome cost: Int64 -> String
  (let [(ins (map (fn [(t Turn)] -> Int64 t.tokIn) o.turns))
        (outs (map (fn [(t Turn)] -> Int64 t.tokOut) o.turns))
        (calls (listLength o.turns))]
    (str "(:trial :key " (asnQuote (trialKey o.trial))
         " :arm " (asnQuote o.trial.arm) " :task " (asnQuote o.trial.task.id) " :family " (asnQuote o.trial.task.family)
         " :model " (asnQuote o.trial.model) " :served " (asnQuote o.served) " :rep " (stringFromInt64 o.trial.rep)
         " :rawPass " (boolText o.rawPass) " :healedPass " (boolText o.healedPass) " :solved " (boolText o.solved)
         " :calls " (stringFromInt64 calls) " :repairTurns " (stringFromInt64 (- calls 1))
         " :firstFail " (asnQuote (stageAt o.turns 0))
         " :stages (" (stringJoin (map (fn [(t Turn)] -> String (asnQuote t.stage)) o.turns) " ") ")"
         " :tokIn " (intList ins) " :tokOut " (intList outs)
         " :tokInSum " (stringFromInt64 (listSum ins)) " :tokOutSum " (stringFromInt64 (listSum outs))
         " :tokToGreen " (stringFromInt64 (if o.solved (+ (listSum ins) (listSum outs)) 0))
         " :sysTok " (stringFromInt64 o.sysTok) " :costPico " (stringFromInt64 cost) " :wallMs " (stringFromInt64 o.wallMs)
         " :headerStripped " (boolText o.stripped)
         " :promptSha " (asnQuote o.promptSha)
         (abandonedText o)
         " :replies (" (stringJoin (map (fn [(t Turn)] -> String (asnQuote t.reply)) o.turns) " ") "))"))

fn planTrials models: (List String) arms: (List String) tasks: (List Task) reps: Int64 seed: Int64 -> (List Trial)
  (let [(all (listFlatMap (fn [(m String)] -> (List Trial)
                 (listFlatMap (fn [(a String)] -> (List Trial)
                   (listFlatMap (fn [(t Task)] -> (List Trial)
                     (map (fn [(r Int64)] -> Trial (Trial :idx 0 :arm a :task t :model m :rep r)) (range 1 (+ reps 1))))
                     tasks))
                   arms))
                 models))
        (shuffled (listSortBy (fn [(tr Trial)] -> Int64 (fnv1a64 (str (stringFromInt64 seed) "|" (trialKey tr)))) all))]
    (map (fn [(i Int64)] -> Trial (withIdx (optionOr (listGet shuffled i) (Trial :idx 0 :arm "" :task (emptyTask) :model "" :rep 0)) i))
         (range 0 (listLength shuffled))))

fn withIdx tr: Trial i: Int64 -> Trial
  (with tr :idx i)

fn emptyTask -> Task
  (Task :id "" :family "" :difficulty "" :statement "" :entry "" :entryPy "" :sigAsl "" :sigPy "" :sigTs "" :examples (list) :cases (list))

fn planSig models: (List String) arms: (List String) tasks: (List Task) reps: Int64 repairs: Int64 maxTokens: Int64 seed: Int64 -> String
  (stringFromInt64 (fnv1a64 (str (stringJoin models ",") "|" (stringJoin arms ",") "|" (stringJoin (map (fn [(t Task)] -> String t.id) tasks) ",") "|"
                                 (stringFromInt64 reps) "|" (stringFromInt64 repairs) "|" (stringFromInt64 maxTokens) "|" (stringFromInt64 seed))))

fn ! trialStep! cfg: Config cards: (List Card) existing: String total: Int64 call: (fn [S Req] -> (Pair S Reply)) acc: (Pair S RunState) tr: Trial -> (Pair S RunState)
  (stepKnown! cfg cards existing total call (pairFirst acc) (pairSecond acc) tr)

fn ! stepKnown! cfg: Config cards: (List Card) existing: String total: Int64 call: (fn [S Req] -> (Pair S Reply)) state: S rs: RunState tr: Trial -> (Pair S RunState)
  (let [(spentBefore rs.spent)]
    (cond
      ((not (stringEmpty? rs.stopped)) (pair state rs))
      ((stringContains? existing (str ":key " (asnQuote (trialKey tr)) " ")) (pair state (with rs :skipped (+ rs.skipped 1))))
      (else
        (let [(res (runTrial! cfg cards tr call state rs.spent))
              (o (pairSecond res))]
          (cond
            ((= o.error "budget")
              (let [(w (fileAppend cfg.out (str "(:stopped :reason \"budget\" :spentPico " (stringFromInt64 o.spent) " :capPico " (stringFromInt64 cfg.capPico)
                                                " :doneTrials " (stringFromInt64 (+ rs.done rs.skipped)) " :ofTrials " (stringFromInt64 total)
                                                " :atKey " (asnQuote (trialKey tr)) ")\n")))]
                (pair (pairFirst res) (with rs :spent o.spent :stopped "budget"))))
            ((stringStartsWith? o.error "infra: ")
              (let [(w (fileAppend cfg.out (str "(:infra :at " (asnQuote (trialKey tr)) " :error " (asnQuote (clip o.error 400))
                                                " :costPico " (stringFromInt64 (- o.spent rs.spent)) ")\n")))]
                (pair (pairFirst res) (with rs :spent o.spent :stopped "infra"))))
            ((not (stringEmpty? o.error))
              (let [(w (fileAppend cfg.out (str "(:callFailed :key " (asnQuote (trialKey tr)) " :error " (asnQuote (clip o.error 400))
                                                " :costPico " (stringFromInt64 (- o.spent rs.spent)) (abandonedText o) ")\n")))
                    (fails (+ rs.callFails 1))]
                (pair (pairFirst res) (with rs :spent o.spent :callFails fails :stopped (if (>= fails 3) "callFailures" "")))))
            (else
              (let [(w (fileAppend cfg.out (str (trialRow o (- o.spent rs.spent)) "\n")))]
                (pair (pairFirst res) (with rs :spent o.spent :done (+ rs.done 1) :callFails 0)))))))))

fn ! runAll! cfg: Config cards: (List Card) trials: (List Trial) existing: String spentBefore: Int64 call: (fn [S Req] -> (Pair S Reply)) state: S -> (Pair S RunState)
  (fold (fn [acc tr] (trialStep! cfg cards existing (listLength trials) call acc tr))
        (pair state (RunState :spent spentBefore :done 0 :skipped 0 :callFails 0 :stopped ""))
        trials)

fn planFor plan: (List (Pair String String)) arm: String task: String -> String
  (match (listFind (fn [(p (Pair String String))] -> Bool (= (pairFirst p) (str arm "|" task))) plan)
    ((some p) (pairSecond p))
    ((none)
      (match (listFind (fn [(p (Pair String String))] -> Bool (or (= (pairFirst p) task) (= (pairFirst p) "*"))) plan)
        ((some p) (pairSecond p))
        ((none) "good"))))

fn dedentStep st: (Pair (List String) Bool) line: String -> (Pair (List String) Bool)
  (pair (listAppend (pairFirst st) (list (if (pairSecond st) (stringTrim line) line))) (stringStartsWith? line "fn "))

fn healableCode code: String -> String
  (stringJoin (pairFirst (fold dedentStep (pair (list) false) (stringLines code))) "\n")

fn wrongCode kind: String lang: String arm: String task: String refText: String -> String
  (cond
    ((= kind "parse")
      (cond
        ((= lang "ts") (str refText "\n{\n"))
        (else (str (toArm arm refText) "\n(\n"))))
    ((and (= kind "execute") (= lang "py")) (str refText "\n\nraise RuntimeError(\"canned\")\n"))
    ((and (= kind "execute") (= lang "ts")) (str refText "\nthrow new Error(\"canned\");\n"))
    ((= lang "py") (str refText "\n\ndef " (snake task) "(*args):\n    return \"canned wrong\"\n"))
    ((= lang "ts") (str refText "\nconst cannedWrong: number = \"text\";\n"))
    (else (toArm arm (str refText "\nfn cannedWrong -> Int64\n  (cannedUndefinedSymbol 1)\n"))))

fn ! fakeReply! root: String plan: (List (Pair String String)) r: Req -> Reply
  (let [(planned (planFor plan r.arm r.task))
        (cut (stringIndexOf planned "="))
        (beh (match cut ((some i) (slice planned 0 i)) ((none) planned)))
        (lang (armLang r.arm))
        (refText (match cut
                   ((some i) (sliceFrom planned (+ i 1)))
                   ((none) (resultOr (fileReadString (str root "/asl/bench/gen/ref/" r.task "." lang)) ""))))
        (kind (cond
                ((= beh "good") "good")
                ((= beh "never") "wrong")
                ((> r.turn 1) "good")
                ((= beh "fixed") "wrong")
                (else beh)))
        (code (cond
                ((= kind "good") (toArm r.arm refText))
                ((= kind "heal") (if (= r.arm "asl") (healableCode refText) (toArm r.arm refText)))
                (else (wrongCode kind lang r.arm r.task refText))))
        (text (if (= kind "noBlock")
                "A loop over the input would solve this."
                (str "Here is the solution.\n\n```" lang "\n" code "\n```\n")))]
    (Reply :text text :tokIn (/ (reqChars r) 4) :tokOut (/ (stringLength text) 4) :served "fake"
           :error (if (stringEmpty? refText) (str "the fake model has no reference asl/bench/gen/ref/" r.task "." lang) "")))

fn fakeCaller root: String plan: (List (Pair String String)) -> (fn [Int64 Req] -> (Pair Int64 Reply))
  (fn [(n Int64) (r Req)] -> (Pair Int64 Reply) (pair (+ n 1) (fakeReply! root plan r)))

fn pow10 n: Int64 -> Int64
  (if (<= n 0) 1 (* 10 (pow10 (- n 1))))

fn usdToMicro text: String -> (Option Int64)
  (let [(parts (stringSplit (stringTrim text) "."))
        (whole (stringToInt64 (optionOr (listHead parts) "")))
        (fracText (clip (optionOr (listGet parts 1) "") 6))
        (frac (if (stringEmpty? fracText) (some 0) (stringToInt64 fracText)))]
    (match whole
      ((none) (none))
      ((some w)
        (match frac
          ((none) (none))
          ((some f)
            (if (or (< w 0) (or (< f 0) (> (listLength parts) 2)))
              (none)
              (some (+ (* w 1000000) (* f (pow10 (- 6 (stringLength fracText))))))))))))

fn pad2 n: Int64 -> String
  (if (< n 10) (str "0" (stringFromInt64 n)) (stringFromInt64 n))

fn dateOf epochNs: Int64 -> String
  (let [(z (+ (/ epochNs 86400000000000) 719468))
        (era (/ z 146097))
        (doe (- z (* era 146097)))
        (yoe (/ (- (+ (- doe (/ doe 1460)) (/ doe 36524)) (/ doe 146096)) 365))
        (doy (- doe (- (+ (* 365 yoe) (/ yoe 4)) (/ yoe 100))))
        (mp (/ (+ (* 5 doy) 2) 153))
        (d (+ (- doy (/ (+ (* 153 mp) 2) 5)) 1))
        (m (if (< mp 10) (+ mp 3) (- mp 9)))
        (y (+ (+ yoe (* era 400)) (if (<= m 2) 1 0)))]
    (str (stringFromInt64 y) "-" (pad2 m) "-" (pad2 d)))

fn usdText pico: Int64 -> String
  (let [(micro (/ pico 1000000))
        (frac (stringFromInt64 (mod micro 1000000)))]
    (str (stringFromInt64 (/ micro 1000000)) "." (stringRepeat "0" (- 6 (stringLength frac))) frac))

fn headerRow mode: String models: (List String) arms: (List String) tasks: (List Task) reps: Int64 seed: Int64 cfg: Config cards: (List Card) versions: (List (Pair String String)) date: String note: String -> String
  (str "(:run :id \"FABLE-LANG-01\" :protocol \"asl/EXPERIMENT.md v2\" :mode " (asnQuote mode)
       " :planSig " (asnQuote (planSig models arms tasks reps cfg.repairs cfg.maxTokens seed))
       " :models (" (stringJoin (map asnQuote models) " ") ")"
       " :arms (" (stringJoin (map asnQuote arms) " ") ")"
       " :taskIds (" (stringJoin (map (fn [(t Task)] -> String (asnQuote t.id)) tasks) " ") ")"
       " :reps " (stringFromInt64 reps) " :repairs " (stringFromInt64 cfg.repairs) " :maxTokens " (stringFromInt64 cfg.maxTokens)
       " :temperature \"0.2\" :seed " (stringFromInt64 seed)
       " :priceInMicroPerM " (stringFromInt64 cfg.priceIn) " :priceOutMicroPerM " (stringFromInt64 cfg.priceOut)
       " :capPico " (stringFromInt64 cfg.capPico) " :capUsd " (asnQuote (usdText cfg.capPico))
       " :cards (" (stringJoin (map (fn [(c Card)] -> String (str "(:arm " (asnQuote c.arm) " :sha256 " (asnQuote c.sha) " :tokens " (stringFromInt64 c.tokens) ")")) cards) " ") ")"
       " :tools (" (stringJoin (map (fn [(p (Pair String String))] -> String (str "(:name " (asnQuote (pairFirst p)) " :version " (asnQuote (pairSecond p)) ")")) versions) " ") ")"
       " :date " (asnQuote date) " :note " (asnQuote note) ")")

fn priorSpend existing: String -> (Result Int64 String)
  (match (readForms existing)
    ((err e) (err (str "existing results are unreadable: " e)))
    ((ok forms) (ok (listSum (map (fn [(f Sx)] -> Int64 (if (listContains? (list ":trial" ":infra" ":callFailed") (headOf f)) (kwInt (sxItems f) ":costPico") 0)) forms)))))
