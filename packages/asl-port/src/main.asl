(module asl-port/main
  :x [main runPortPy! parseCliArgs CliOptions]
  :i [(asl-port/pyAst :a py)
      (asl-port/plan :a pl)
      (asl-port/translate :a tr)
      (asl-port/parity :a par)])

(schema CliOptions
  (:f valid Bool)
  (:f file String)
  (:f selectedFns (List String))
  (:f outDir String)
  (:f errMsg String))

fn usage -> String
  "usage: asl-host run asl/packages/asl-port/src/main.asl py FILE.py [--fn NAME ...] [--out DIR]"

fn validFlags? args: (List String) -> Bool
  (mt (listHead args)
    ((some flag)
      (let [(rest (optionOr (listTail args) (list)))]
        (if (or (= flag "--fn") (= flag "--out"))
          (mt (listHead rest)
            ((some value) (and (not (stringEmpty? value)) (and (!= value "--fn") (and (!= value "--out") (validFlags? (optionOr (listTail rest) (list)))))))
            ((none) false))
          false)))
    ((none) true))

fn parseFlags args: (List String) sel: (List String) out: String -> (Pair (List String) String)
  (mt (listHead args)
    ((some a)
      (let [(rest (optionOr (listTail args) (list)))]
        (cond
          ((= a "--fn")
            (mt (listHead rest)
              ((some fnName)
                (parseFlags (optionOr (listTail rest) (list)) (listAppend sel (list fnName)) out))
              ((none)
                (pair sel out))))
          ((= a "--out")
            (mt (listHead rest)
              ((some oDir)
                (parseFlags (optionOr (listTail rest) (list)) sel oDir))
              ((none)
                (pair sel out))))
          (else
            (pair (listAppend sel (list "")) out)))))
    ((none)
      (pair sel out)))

fn parseCliArgs args: (List String) -> CliOptions
  (if (< (listLength args) 2)
    (CliOptions :valid false :file "" :selectedFns (list) :outDir "" :errMsg (usage))
    (let [(subcmd (optionOr (listHead args) ""))
          (filePath (optionOr (listGet args 1) ""))]
      (if (!= subcmd "py")
        (CliOptions :valid false :file "" :selectedFns (list) :outDir "" :errMsg (usage))
        (let [(flagArgs (optionOr (listSlice args 2 (listLength args)) (list)))
              (parsed (parseFlags flagArgs (list) ""))
              (sel (pairFirst parsed))
              (outDir (pairSecond parsed))]
          (CliOptions :valid (validFlags? flagArgs) :file filePath :selectedFns sel :outDir outDir :errMsg "")))))

fn runPortPy! opts: CliOptions -> (Result Int64 String)
  (let [(astRes (py/parsePythonAst! opts.file))]
    (mt astRes
      ((err e)
        (do (eprintln e)
            (ok 1)))
      ((ok astVal)
        (let [(plan (pl/buildPortPlan opts.file astVal))
              (planStr (pl/formatPortPlan plan))
              (sel opts.selectedFns)
              (draft (tr/translateModule opts.file astVal sel))
              (draftStr (tr/formatDraftFile "portDraft" draft.functions draft.gaps))
              (spec (par/buildParitySpec opts.file sel astVal))
              (specStr (par/formatParitySpec spec))
              (outDir opts.outDir)]
          (if (stringEmpty? outDir)
            (do (println planStr)
                (println draftStr)
                (println specStr)
                (ok 0))
            (mt (dirCreate outDir)
              ((err e)
                (do (eprintln (str "ERR_DIR_CREATE: " e))
                    (ok 1)))
              ((ok _)
                (mt (fileWrite (str outDir "/plan.asn") planStr)
                  ((err e)
                    (do (eprintln (str "ERR_WRITE: " e))
                        (ok 1)))
                  ((ok _)
                    (mt (fileWrite (str outDir "/draft.asl") draftStr)
                      ((err e)
                        (do (eprintln (str "ERR_WRITE: " e))
                            (ok 1)))
                      ((ok _)
                        (mt (fileWrite (str outDir "/parity.asn") specStr)
                          ((err e)
                            (do (eprintln (str "ERR_WRITE: " e))
                                (ok 1)))
                          ((ok _)
                            (do (println (str "Wrote port artifacts to " outDir))
                                (ok 0)))))))))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(opts (parseCliArgs args))]
    (if (not opts.valid)
      (do (eprintln opts.errMsg)
          (ok 2))
      (runPortPy! opts)))
