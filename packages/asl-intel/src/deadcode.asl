(module asl-intel/deadcode
  :x [DeadCodeSummary analyzeDeadcode! deadcodeJson formatDeadcodeAsn formatDeadcodeSummary runDeadcode! walkIgnoring!]
  :i [(asl-intel/text :a t)
      (asl-intel/rx :a r)
      (asl-intel/pats :a p)
      (asl-intel/json :a j)
      (asl-intel/host :a h)
      (asl-intel/coupling :a c)
      (asl-intel/tab :a tb)])

(schema Def
  (:f file String)
  (:f name String)
  (:f kind String)
  (:f exported Bool))

(schema DeadCodeSummary
  (:f filesScanned Int64)
  (:f totalDefs Int64)
  (:f dead (List Def)))

fn walkIgnoring! ctx: h/Ctx root: String -> (Result (List String) String)
  (mt (h/findTree! ctx root true (list "*.asl"))
    ((err e) (err e))
    ((ok tree) (ok (h/walkFiles! tree))))

fn fileDefs! code: String rel: String -> (List Def)
  (let [(b (stringToBytes code)) (n (bytesLength b))
        (exports (mt (c/firstGroup (p/patExports!) code) ((some g) (t/pySplit g)) ((none) (list))))
        (fns (fold (fn [(acc (List Def)) (caps (List Int64))] -> (List Def)
                     (let [(name (t/pyStrip (optionOr (r/rexGroup code caps 1) "")))]
                       (if (or (listContains? (list "main" "RunTests" "runTests") name) (stringStartsWith? name "!")) acc
                         (cons (Def :file rel :name name :kind "fn" :exported (listContains? exports name)) acc))))
                   (list) (r/rexFindAll (p/patDeadFn!) b n)))
        (schemas (map (fn [(caps (List Int64))] -> Def
                        (let [(name (t/pyStrip (optionOr (r/rexGroup code caps 1) "")))]
                          (Def :file rel :name name :kind "schema" :exported (listContains? exports name))))
                      (r/rexFindAll (p/patSchemaLine!) b n)))]
    (listAppend (listReverse fns) schemas))

fn prodFile? fpath: String -> Bool
  (not (or (stringContains? fpath "/tests/") (or (stringContains? fpath "/fixtures/") (or (stringContains? fpath "corpus/") (stringContains? fpath "/examples/")))))

fn deadIn! code: String defs: (List Def) -> (List Def)
  (let [(b (stringToBytes code)) (n (bytesLength b))
        (priv (filter (fn [(d Def)] -> Bool (not d.exported)) defs))
        (tab (fold (fn [(tb tb/Strtab) (d Def)] -> tb/Strtab (if (allWord? d.name) (pairFirst (tb/internStr! tb d.name)) tb))
                   (tb/strtabNew (listLength priv)) priv))
        (counts (tb/ivNew (tb/strtabCount tab)))]
    (do (runCounts! b n tab counts 0)
        (filter (fn [(d Def)] -> Bool
                  (let [(id (tb/lookupStr tab d.name))]
                    (if (>= id 0) (<= (tb/ivGet counts id) 1)
                      (let [(w (stringToBytes d.name))] (<= (t/wordHits b n w (bytesLength w) 0 2 0) 1)))))
                priv)))

fn allWord? s: String -> Bool
  (let [(b (stringToBytes s))]
    (allWordLoop b (bytesLength b) 0))

fn allWordLoop b: Bytes n: Int64 i: Int64 -> Bool
  (cond
    ((>= i n) (> n 0))
    ((t/isWordByteAscii (bytesGet b i)) (allWordLoop b n (+ i 1)))
    (else false))

fn runCounts! b: Bytes n: Int64 tab: tb/Strtab counts: Bytes i: Int64 -> Unit
  (cond
    ((>= i n) ())
    ((t/wordAt? b n i)
      (let [(j (runStop b n i))]
        (do (let [(id (tb/lookup tab b i j))] (if (>= id 0) (tb/ivAdd! counts id 1) ()))
            (runCounts! b n tab counts j))))
    (else (runCounts! b n tab counts (+ i (max 1 (t/utf8Len (bytesGet b i)))))))

fn runStop b: Bytes n: Int64 i: Int64 -> Int64
  (if (t/wordAt? b n i) (runStop b n (+ i (max 1 (t/utf8Len (bytesGet b i))))) i)

fn analyzeDeadcode! ctx: h/Ctx root: String pkgFilter: String -> (Result DeadCodeSummary String)
  (mt (walkIgnoring! ctx root)
    ((err e) (err e))
    ((ok files)
      (let [(res (fold (fn [(st (Pair Int64 (Pair Int64 (List Def)))) (f String)] -> (Pair Int64 (Pair Int64 (List Def)))
                         (mt (h/readText! f)
                           ((err _) st)
                           ((ok code)
                             (let [(scanned (+ (pairFirst st) 1)) (rel (t/relPath f root ctx.cwd))]
                               (if (or (not (prodFile? f)) (and (not (stringEmpty? pkgFilter)) (not (stringContains? rel pkgFilter))))
                                 (pair scanned (pairSecond st))
                                 (let [(defs (fileDefs! code rel))]
                                   (pair scanned (pair (+ (pairFirst (pairSecond st)) (listLength defs))
                                                       (listAppend (listReverse (deadIn! code defs)) (pairSecond (pairSecond st)))))))))))
                       (pair 0 (pair 0 (list))) files))]
        (ok (DeadCodeSummary :filesScanned (pairFirst res) :totalDefs (pairFirst (pairSecond res)) :dead (listReverse (pairSecond (pairSecond res))))))))

fn formatDeadcodeAsn res: DeadCodeSummary -> String
  (t/joinWith (list "(:deadCodeAudit" "  :status :ok"
                    (str "  :filesScanned " (t/intStr res.filesScanned))
                    (str "  :totalDefinitions " (t/intStr res.totalDefs))
                    (str "  :deadPrivateCount " (t/intStr (listLength res.dead)))
                    (if (listEmpty? res.dead) "  :sampleDeadSymbols []"
                      (str "  :sampleDeadSymbols [\n    "
                           (t/joinWith (map (fn [(d Def)] -> String (str "(:file \"" d.file "\" :name \"" d.name "\" :kind \"" d.kind "\")")) (t/takeN res.dead 25)) "\n    ")
                           "\n  ]"))
                    ")")
              "\n")

fn formatDeadcodeSummary res: DeadCodeSummary -> String
  (t/joinWith (listAppend
                (list "=== ASL DEAD CODE & UNREFERENCED SYMBOLS AUDIT ==="
                      (str "Files Scanned:       " (t/intStr res.filesScanned))
                      (str "Source Definitions:  " (t/intStr res.totalDefs))
                      (str "Dead Private Funcs:  " (t/intStr (listLength res.dead))))
                (if (listEmpty? res.dead) (list)
                  (cons "" (cons "--- Detected Unreferenced Private Symbols (Sample) ---"
                    (map (fn [(d Def)] -> String (str "  • " d.file ": " d.kind " " d.name)) (t/takeN res.dead 25))))))
              "\n")

fn deadcodeJson res: DeadCodeSummary -> j/Json
  (j/jObj (list (pair "status" (j/jStr "ok"))
                (pair "filesScanned" (j/jInt res.filesScanned))
                (pair "totalDefinitions" (j/jInt res.totalDefs))
                (pair "deadPrivateCount" (j/jInt (listLength res.dead)))
                (pair "deadPrivateSymbols" (j/jArr (map (fn [(d Def)] -> j/Json (j/jObj (list (pair "file" (j/jStr d.file)) (pair "name" (j/jStr d.name)) (pair "kind" (j/jStr d.kind))))) res.dead)))))

fn runDeadcode! ctx: h/Ctx fmt: String pkgFilter: String -> h/Outcome
  (mt (analyzeDeadcode! ctx ctx.home pkgFilter)
    ((err e) (h/outcome "" (str "Error: " e "\n") 1))
    ((ok res)
      (h/outcome (str (cond ((= fmt "json") (j/dumps (deadcodeJson res))) ((= fmt "summary") (formatDeadcodeSummary res)) (else (formatDeadcodeAsn res))) "\n") "" 0)))
