(module asl-intel/search
  :x [analyzeImpact! extractOutline! querySymbols!]
  :i [(asl-intel/text :a t)
      (asl-intel/rx :a r)
      (asl-intel/pats :a p)
      (asl-intel/host :a h)
      (asl-intel/model :a m)
      (asl-intel/coupling :a c)])

fn walkAsl! ctx: h/Ctx dir: String -> (Result (List String) String)
  (mt (h/findTree! ctx dir false (list "*.asl"))
    ((err e) (err e))
    ((ok tree) (ok (h/walkFiles! tree))))

fn quoted10 xs: (List String) -> String
  (t/joinWith (map (fn [(x String)] -> String (str "\"" x "\"")) (t/takeN xs 10)) " ")

fn analyzeImpact! ctx: h/Ctx sym: String -> (Result String String)
  (let [(root ctx.home) (rex (p/patWordLit! sym))]
    (mt (walkAsl! ctx (t/joinPath (t/joinPath root "asl") "packages"))
      ((err e) (err e))
      ((ok files)
        (let [(hits (fold (fn [(acc (Pair (List String) (List String))) (f String)] -> (Pair (List String) (List String))
                            (mt (h/readText! f)
                              ((err _) acc)
                              ((ok code)
                                (let [(b (stringToBytes code))]
                                  (if (and (stringContains? code sym) (r/rexHas? rex b (bytesLength b)))
                                    (let [(rel (t/relPath f root ctx.cwd))]
                                      (if (stringContains? (t/lowerAscii rel) "test")
                                        (pair (pairFirst acc) (cons rel (pairSecond acc)))
                                        (pair (cons rel (pairFirst acc)) (pairSecond acc))))
                                    acc)))))
                          (pair (list) (list)) files))
              (direct (listReverse (pairFirst hits)))
              (tests (listReverse (pairSecond hits)))
              (score (min 100 (+ (* (listLength direct) 10) (* (listLength tests) 2))))]
          (ok (t/joinWith (list "(:impactReport" "  :status :ok"
                                (str "  :symbol \"" sym "\"")
                                (str "  :blastRadius " (t/intStr score))
                                (str "  :directCallersCount " (t/intStr (listLength direct)))
                                (str "  :testCallersCount " (t/intStr (listLength tests)))
                                (str "  :directCallers [" (quoted10 direct) "]")
                                (str "  :testCallers [" (quoted10 tests) "])"))
                          "\n"))))))

fn globEscape s: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "*" "\\*") "?" "\\?") "[" "\\[")

fn walkFind! ctx: h/Ctx root: String fpath: String -> (Result (Option String) String)
  (if (or (stringEmpty? fpath) (stringContains? fpath "/")) (ok (none))
    (mt (h/findTree! ctx root false (list (globEscape fpath)))
      ((err e) (err e))
      ((ok tree)
        (ok (listHead (filter (fn [(f String)] -> Bool (= (t/baseName f) fpath)) (h/walkFiles! tree)))))))

fn fnItem code: String exports: (List String) caps: (List Int64) -> m/OutlineItem
  (let [(name (t/pyStrip (optionOr (r/rexGroup code caps 1) "")))
        (g2 (t/pyStrip (optionOr (r/rexGroup code caps 2) "")))
        (sig (t/pyStrip (mt (r/rexGroup code caps 3) ((some g3) (str g2 " -> " (t/pyStrip g3))) ((none) g2))))]
    (m/makeOutlineItem name "fn" sig (listContains? exports name)))

fn kindItems rex: r/Rex kind: String code: String b: Bytes exports: (List String) -> (List m/OutlineItem)
  (map (fn [(caps (List Int64))] -> m/OutlineItem
         (let [(name (t/pyStrip (optionOr (r/rexGroup code caps 1) "")))]
           (m/makeOutlineItem name kind "" (listContains? exports name))))
       (r/rexFindAll rex b (bytesLength b)))

fn itemText it: m/OutlineItem -> String
  (let [(x (if it.exported "true" "false"))]
    (if (= it.kind "fn")
      (str "(:item :name \"" it.name "\" :kind \"fn\" :signature \"" it.signature "\" :exported " x ")")
      (str "(:item :name \"" it.name "\" :kind \"" it.kind "\" :exported " x ")")))

fn extractOutline! ctx: h/Ctx fpath: String -> (Result String String)
  (let [(root (t/absPath (if (stringEmpty? ctx.aslRoot) ctx.home ctx.aslRoot) ctx.cwd))
        (direct (if (stringStartsWith? fpath "/") fpath (t/joinPath root fpath)))
        (found (if (fileExists? direct) (ok (some direct)) (walkFind! ctx root fpath)))]
    (mt found
      ((err e) (err e))
      ((ok hit)
        (let [(resolved (optionOr hit direct))]
          (if (not (h/isFile? resolved))
            (ok (str "(:outline :status :error :message \"File not found: " fpath "\")"))
            (mt (h/readText! resolved)
              ((err e) (err (str "cannot read " resolved ": " e)))
              ((ok code)
                (let [(b (stringToBytes code))
                      (modId (optionOr (c/firstGroup (p/patModuleId!) code) (t/baseName resolved)))
                      (exports (mt (c/firstGroup (p/patExports!) code) ((some g) (t/pySplit g)) ((none) (list))))
                      (fns (map (fn [(caps (List Int64))] -> m/OutlineItem (fnItem code exports caps)) (r/rexFindAll (p/patOutlineFn!) b (bytesLength b))))
                      (items (listAppend fns (listAppend (kindItems (p/patSchemaLine!) "schema" code b exports) (kindItems (p/patMacroLine!) "macro" code b exports))))
                      (outl (m/makeModuleOutline modId (t/relPath resolved root ctx.cwd) items))]
                  (ok (t/joinWith (list "(:outline" "  :status :ok"
                                        (str "  :file \"" outl.file "\"")
                                        (str "  :module \"" outl.moduleName "\"")
                                        (str "  :itemsCount " (t/intStr outl.totalSymbols))
                                        "  :items ["
                                        (str "    " (t/joinWith (map itemText outl.items) "\n    "))
                                        "  ])")
                                  "\n"))))))))))

fn fileMatches! ctx: h/Ctx root: String f: String qb: Bytes acc: (List String) -> (List String)
  (mt (h/readText! f)
    ((err _) acc)
    ((ok code)
      (let [(b (stringToBytes code)) (n (bytesLength b)) (rel (t/relPath f root ctx.cwd))]
        (if (< (t/foldIndexOf b n qb (bytesLength qb) 0) 0) acc
          (lineMatches code b (t/splitLinesPy b n) qb (p/patQueryDecl!) rel acc)))))

fn lineMatches code: String b: Bytes lines: (List (Pair Int64 Int64)) qb: Bytes dRex: r/Rex rel: String acc: (List String) -> (List String)
  (mt (listHead lines)
    ((none) acc)
    ((some ln)
      (let [(s (pairFirst ln)) (e (pairSecond ln)) (rest (optionOr (listTail lines) (list)))]
        (if (< (t/foldIndexOf b e qb (bytesLength qb) s) 0)
          (lineMatches code b rest qb dRex rel acc)
          (mt (r/rexSearch dRex b e s)
            ((none) (lineMatches code b rest qb dRex rel acc))
            ((some caps)
              (let [(sym (t/pyStrip (optionOr (r/rexGroup code caps 1) "")))
                    (acc2 (cons (str "(:symbol \"" sym "\" :file \"" rel "\")") acc))]
                (if (>= (listLength acc2) 20) acc2 (lineMatches code b rest qb dRex rel acc2)))))))))

fn dirGroups files: (List String) -> (List (List String))
  (listReverse (map listReverse
    (fold (fn [(acc (List (List String))) (f String)] -> (List (List String))
            (mt (listHead acc)
              ((some g) (if (= (t/dirName (optionOr (listHead g) "")) (t/dirName f)) (cons (cons f g) (optionOr (listTail acc) (list))) (cons (list f) acc)))
              ((none) (list (list f)))))
          (list) files)))

fn querySymbols! ctx: h/Ctx q: String -> (Result String String)
  (let [(root ctx.home) (qb (stringToBytes q))]
    (mt (walkAsl! ctx (t/joinPath (t/joinPath root "asl") "packages"))
      ((err e) (err e))
      ((ok files)
        (let [(ms (listReverse (fold (fn [(acc (List String)) (g (List String))] -> (List String)
                                       (if (>= (listLength acc) 20) acc
                                         (fold (fn [(a2 (List String)) (f String)] -> (List String) (fileMatches! ctx root f qb a2)) acc g)))
                                     (list) (dirGroups files))))]
          (ok (t/joinWith (list "(:intelQuery" "  :status :ok"
                                (str "  :query \"" q "\"")
                                (str "  :matchesCount " (t/intStr (listLength ms)))
                                (str "  :matches [" (t/joinWith ms " ") "])"))
                          "\n"))))))
