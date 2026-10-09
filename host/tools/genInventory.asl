(module asl/host/tools/genInventory :x [main] :i [])
(schema Captured (:f exitCode Int64) (:f stdout String) (:f stderr String))
(schema Clean (:f text String) (:f mode Int64) (:f depth Int64) (:f done Bool) (:f stop Int64))

fn readAll! fd: Int64 acc: String -> (Result String String)
  (mt (fdRead fd 65536) ((err e) (err e)) ((ok s) (if (stringEmpty? s) (ok acc) (readAll! fd (str acc s)))))

fn capture! sp: SpawnedProc -> (Result Captured String)
  (let [(ci (fdClose sp.stdin)) (o (readAll! sp.stdout "")) (e (readAll! sp.stderr "")) (co (fdClose sp.stdout)) (ce (fdClose sp.stderr)) (w (procWaitPid sp.pid false))]
    (mt w ((err x) (err x)) ((ok code) (mt o ((err x) (err x)) ((ok out) (mt e ((err x) (err x)) ((ok errout) (if (and (ok? ci) (and (ok? co) (ok? ce))) (ok (Captured :exitCode (optionOr code -1) :stdout out :stderr errout)) (err "close failed")))))))))

fn runv! argv: (List String) -> (Result Captured String)
  (mt (procSpawnv argv (none) (none)) ((err e) (err e)) ((ok sp) (capture! sp)))

fn byteAt bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (>= i 0) (< i n)) (bytesGet bs i) -1)

fn identStart? b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (or (and (>= b 97) (<= b 122)) (= b 95)))

fn wordByte? b: Int64 -> Bool
  (or (identStart? b) (and (>= b 48) (<= b 57)))

fn spaceByte? b: Int64 -> Bool
  (or (= b 32) (and (>= b 9) (<= b 13)))

fn wordEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (wordByte? (byteAt bs n i)) (wordEnd bs n (+ i 1)) i)

fn skipSpaces bs: Bytes n: Int64 i: Int64 -> Int64
  (if (spaceByte? (byteAt bs n i)) (skipSpaces bs n (+ i 1)) i)

fn skipSpaceStars bs: Bytes n: Int64 i: Int64 -> Int64
  (let [(b (byteAt bs n i))] (if (or (spaceByte? b) (= b 42)) (skipSpaceStars bs n (+ i 1)) i))

fn skipStars bs: Bytes n: Int64 i: Int64 -> Int64
  (if (= (byteAt bs n i) 42) (skipStars bs n (+ i 1)) i)

fn indexFrom bs: Bytes n: Int64 i: Int64 b: Int64 -> Int64
  (cond ((>= i n) n) ((= (bytesGet bs i) b) i) (else (indexFrom bs n (+ i 1) b)))

fn startsWithAny? line: String words: (List String) -> Bool
  (not (listEmpty? (filter (fn [(w String)] -> Bool (stringStartsWith? line w)) words)))

fn structBody? bs: Bytes n: Int64 line: String -> Bool
  (and (stringStartsWith? line "struct")
    (let [(s (skipSpaces bs n 6)) (e (wordEnd bs n s))] (and (> s 6) (and (> e s) (= (byteAt bs n (skipSpaces bs n e)) 123)))))

fn bodyFollows? bs: Bytes n: Int64 i: Int64 semi: Int64 -> Bool
  (cond ((>= i semi) false)
        ((and (= (bytesGet bs i) 41) (= (byteAt bs n (skipSpaces bs n (+ i 1))) 123)) true)
        (else (bodyFollows? bs n (+ i 1) semi)))

fn fnClassByte? b: Int64 -> Bool
  (or (wordByte? b) (or (spaceByte? b) (or (= b 42) (or (= b 40) (or (= b 41) (= b 44))))))

fn fnFrom bs: Bytes n: Int64 line: String p: Int64 -> (Option String)
  (if (>= p n) (none)
    (let [(b (bytesGet bs p)) (e (wordEnd bs n p)) (paren (skipSpaces bs n e))]
      (if (and (identStart? b) (and (not (wordByte? (bytesGet bs (- p 1)))) (and (= (byteAt bs n paren) 40) (bodyFollows? bs n (+ paren 1) (indexFrom bs n (+ paren 1) 59)))))
        (stringSlice line p e)
        (if (fnClassByte? b) (fnFrom bs n line (+ p 1)) (none)))))

fn fnName line: String -> (Option String)
  (let [(bs (stringToBytes line)) (n (bytesLength bs))]
    (if (or (startsWithAny? line (list "typedef" "extern" "#" "enum" "union")) (or (structBody? bs n line) (not (identStart? (byteAt bs n 0)))))
      (none)
      (mt (fnFrom bs n line 1)
        ((some name) (if (listContains? (list "if" "for" "while" "switch" "sizeof" "return" "__attribute__") name) (none) (some name)))
        ((none) (none)))))

fn skipBrackets bs: Bytes n: Int64 i: Int64 -> Int64
  (if (= (byteAt bs n i) 91)
    (let [(close (indexFrom bs n (+ i 1) 93))] (if (< close n) (skipBrackets bs n (+ close 1)) i))
    i)

fn declaredAt bs: Bytes n: Int64 line: String i: Int64 -> (Option String)
  (if (not (identStart? (byteAt bs n i))) (none)
    (let [(e (wordEnd bs n i)) (after (byteAt bs n (skipSpaces bs n (skipBrackets bs n (skipSpaces bs n e)))))]
      (if (or (= after 61) (or (= after 59) (= after 44))) (stringSlice line i e) (none))))

fn keywordThenSpace bs: Bytes n: Int64 line: String i: Int64 word: String -> (Option Int64)
  (let [(k (stringLength word)) (s (skipSpaces bs n (+ i k)))]
    (if (and (= (optionOr (stringSlice line i (+ i k)) "") word) (> s (+ i k))) (some s) (none)))

fn optionals found: (Option Int64) i: Int64 -> (List Int64)
  (mt found ((some j) (list j i)) ((none) (list i)))

fn typedFrom bs: Bytes n: Int64 line: String i: Int64 -> (Option String)
  (if (not (identStart? (byteAt bs n i))) (none)
    (let [(e (wordEnd bs n i)) (r (skipSpaceStars bs n e))]
      (if (= r e) (none)
        (mt (keywordThenSpace bs n line r "const")
          ((some c) (mt (declaredAt bs n line (skipStars bs n c)) ((some name) (some name)) ((none) (declaredAt bs n line r))))
          ((none) (declaredAt bs n line r))))))

fn structPrefix bs: Bytes n: Int64 line: String i: Int64 -> (Option Int64)
  (mt (keywordThenSpace bs n line i "struct")
    ((some s) (let [(e (wordEnd bs n s)) (t (skipSpaces bs n e))] (if (and (> e s) (> t e)) (some t) (none))))
    ((none) (none)))

fn firstSome xs: (List (Option String)) -> (Option String)
  (mt (listHead xs) ((none) (none)) ((some x) (mt x ((some v) (some v)) ((none) (firstSome (optionOr (listTail xs) (list)))))))

fn varName line: String -> (Option String)
  (let [(bs (stringToBytes line)) (n (bytesLength bs))
        (starts (fold (fn [(acc (List Int64)) (s Int64)] -> (List Int64) (listAppend acc (optionals (keywordThenSpace bs n line s "const") s))) (list) (optionals (keywordThenSpace bs n line 0 "static") 0)))
        (typeStarts (fold (fn [(acc (List Int64)) (s Int64)] -> (List Int64) (listAppend acc (mt (keywordThenSpace bs n line s "unsigned") ((some u) (list u s)) ((none) (optionals (structPrefix bs n line s) s))))) (list) starts))
        (head (optionOr (stringSlice line 0 (optionOr (stringIndexOf line "=") n)) line))]
    (if (or (startsWithAny? line (list "typedef" "extern" "#" "return")) (stringContains? head "("))
      (none)
      (firstSome (map (fn [(s Int64)] -> (Option String) (typedFrom bs n line s)) typeStarts))))

fn cleanFrom bs: Bytes n: Int64 line: String i: Int64 c: Clean -> Clean
  (if (or (>= i n) c.done) c
    (let [(b (bytesGet bs i)) (next (byteAt bs n (+ i 1))) (mode c.mode) (depth c.depth) (text c.text)]
      (cond
        ((= mode 1) (if (and (= b 42) (= next 47)) (cleanFrom bs n line (+ i 2) (Clean :text (str text " ") :mode 0 :depth depth :done false :stop -1)) (cleanFrom bs n line (+ i 1) c)))
        ((or (= mode 2) (= mode 3)) (cond ((= b 92) (cleanFrom bs n line (+ i 2) c))
                                          ((or (and (= mode 2) (= b 34)) (and (= mode 3) (= b 39))) (cleanFrom bs n line (+ i 1) (Clean :text (str text " ") :mode 0 :depth depth :done false :stop -1)))
                                          (else (cleanFrom bs n line (+ i 1) c))))
        ((and (= b 47) (= next 47)) (Clean :text text :mode 0 :depth depth :done false :stop -1))
        ((and (= b 47) (= next 42)) (cleanFrom bs n line (+ i 2) (Clean :text text :mode 1 :depth depth :done false :stop -1)))
        ((= b 34) (cleanFrom bs n line (+ i 1) (Clean :text text :mode 2 :depth depth :done false :stop -1)))
        ((= b 39) (cleanFrom bs n line (+ i 1) (Clean :text text :mode 3 :depth depth :done false :stop -1)))
        ((and (= b 59) (= depth 0)) (Clean :text text :mode 0 :depth 0 :done true :stop (+ i 1)))
        (else (let [(d (cond ((or (= b 40) (or (= b 91) (= b 123))) (+ depth 1)) ((and (> depth 0) (or (= b 41) (or (= b 93) (= b 125)))) (- depth 1)) (else depth)))]
          (cleanFrom bs n line (+ i 1) (Clean :text (str text (optionOr (stringSlice line i (+ i 1)) "")) :mode mode :depth d :done false :stop -1)))))))

fn declText lines: (List String) c: Clean -> String
  (mt (listHead lines)
    ((none) c.text)
    ((some line) (let [(bs (stringToBytes line)) (r (cleanFrom bs (bytesLength bs) line 0 c))]
      (if r.done r.text (declText (optionOr (listTail lines) (list)) (Clean :text (str r.text " ") :mode r.mode :depth r.depth :done false :stop -1))))))

fn splitTop bs: Bytes n: Int64 text: String i: Int64 start: Int64 depth: Int64 acc: (List String) -> (List String)
  (if (>= i n) (listAppend acc (list (optionOr (stringSlice text start n) "")))
    (let [(b (bytesGet bs i))]
      (cond ((and (= b 44) (= depth 0)) (splitTop bs n text (+ i 1) (+ i 1) depth (listAppend acc (list (optionOr (stringSlice text start i) "")))))
            ((or (= b 40) (or (= b 91) (= b 123))) (splitTop bs n text (+ i 1) start (+ depth 1) acc))
            ((or (= b 41) (or (= b 93) (= b 125))) (splitTop bs n text (+ i 1) start (- depth 1) acc))
            (else (splitTop bs n text (+ i 1) start depth acc)))))

fn lastName bs: Bytes n: Int64 text: String i: Int64 depth: Int64 found: (Option String) -> (Option String)
  (if (>= i n) found
    (let [(b (bytesGet bs i))]
      (cond ((and (= b 61) (= depth 0)) found)
            ((or (= b 40) (or (= b 91) (= b 123))) (lastName bs n text (+ i 1) (+ depth 1) found))
            ((or (= b 41) (or (= b 93) (= b 125))) (lastName bs n text (+ i 1) (- depth 1) found))
            ((wordByte? b) (let [(e (wordEnd bs n i))]
              (lastName bs n text e depth (if (and (= depth 0) (identStart? b)) (stringSlice text i e) found))))
            (else (lastName bs n text (+ i 1) depth found)))))

fn declarators lines: (List String) -> (List String)
  (let [(text (declText lines (Clean :text "" :mode 0 :depth 0 :done false :stop -1))) (bs (stringToBytes text))]
    (fold (fn [(acc (List String)) (part String)] -> (List String)
            (let [(pb (stringToBytes part))] (mt (lastName pb (bytesLength pb) part 0 0 (none)) ((some name) (listAppend acc (list name))) ((none) acc))))
      (list) (splitTop bs (bytesLength bs) text 0 0 0 (list))))

fn key file: String name: String -> String
  (str file "|" name)

fn scanLines lines: (List String) file: String table: (Map String String) -> (Map String String)
  (mt (listHead lines)
    ((none) table)
    ((some line) (let [(rest (optionOr (listTail lines) (list)))]
      (mt (fnName line)
        ((some name) (scanLines rest file (mapSet table (key file name) "fn")))
        ((none) (mt (varName line)
          ((none) (scanLines rest file table))
          ((some name) (let [(next (fold (fn [(m (Map String String)) (d String)] -> (Map String String) (mapSet m (key file d) "var")) (mapSet table (key file name) "var") (declarators lines)))
                             (more (sameLineRest line))]
            (scanLines (if (stringEmpty? more) rest (listAppend (list more) rest)) file next)))))))))

fn sameLineRest line: String -> String
  (let [(bs (stringToBytes line)) (n (bytesLength bs)) (r (cleanFrom bs n line 0 (Clean :text "" :mode 0 :depth 0 :done false :stop -1)))]
    (if r.done (stringTrim (optionOr (stringSlice line r.stop n) "")) ""))

fn tempSymbol? raw: String -> Bool
  (startsWithAny? raw (list "l_" "ltmp" "L" "lCPI" "___"))

fn nmLines lines: (List String) file: String table: (Map String String) -> (Map String String)
  (mt (listHead lines)
    ((none) table)
    ((some line) (let [(rest (optionOr (listTail lines) (list))) (ps (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit line " ")))
                       (raw (optionOr (listGet ps 0) "")) (kind (optionOr (listGet ps 1) ""))]
      (if (or (< (listLength ps) 2) (or (listContains? (list "U" "w" "v") kind) (tempSymbol? raw)))
        (nmLines rest file table)
        (nmLines rest file (mapSet table (key file (if (stringStartsWith? raw "_") (optionOr (stringSlice raw 1 (stringLength raw)) raw) raw)) kind))))))

fn nmObjects! names: (List String) objDir: String table: (Map String String) -> (Result (Map String String) String)
  (mt (listHead names)
    ((none) (ok table))
    ((some o) (mt (runv! (list "nm" "-P" (str objDir "/" o)))
      ((err e) (err (str "nm failed on " o ": " e)))
      ((ok r) (if (= r.exitCode 0)
        (nmObjects! (optionOr (listTail names) (list)) objDir (nmLines (stringLines r.stdout) (str (optionOr (stringSlice o 0 (- (stringLength o) 2)) o) ".c") table))
        (err (str "nm failed on " o ": " r.stderr)))))))

fn lineCount text: String -> Int64
  (let [(bs (stringToBytes text)) (n (bytesLength bs)) (breaks (stringCountChar text "\n"))]
    (if (and (> n 0) (not (= (bytesGet bs (- n 1)) 10))) (+ breaks 1) breaks))

(schema Source (:f name String) (:f text String))

fn readSources! src: (List String) dir: String acc: (List Source) -> (Result (List Source) String)
  (mt (listHead src)
    ((none) (ok acc))
    ((some name) (mt (fileReadString (str dir "/" name))
      ((err e) (err (str "source read failed " name ": " e)))
      ((ok text) (readSources! (optionOr (listTail src) (list)) dir (listAppend acc (list (Source :name name :text text))))))))

fn wordStart bs: Bytes i: Int64 -> Int64
  (if (and (> i 0) (wordByte? (bytesGet bs (- i 1)))) (wordStart bs (- i 1)) i)

fn oddParts parts: (List String) keep: Bool acc: (List String) -> (List String)
  (mt (listHead parts)
    ((none) acc)
    ((some p) (oddParts (optionOr (listTail parts) (list)) (not keep) (if keep (listAppend acc (list p)) acc))))

fn floorBlocks text: String bs: Bytes from: Int64 acc: (Map String String) -> (Map String String)
  (let [(marker " :symbols (")]
    (mt (stringIndexOf (optionOr (stringSlice text from (bytesLength bs)) "") marker)
      ((none) acc)
      ((some rel) (let [(at (+ from rel)) (open (+ at (stringLength marker))) (start (wordStart bs at))
                        (close (indexFrom bs (bytesLength bs) open 41))
                        (block (optionOr (stringSlice text start at) ""))
                        (names (oddParts (stringSplit (optionOr (stringSlice text open close) "") "\"") false (list)))]
        (floorBlocks text bs close
          (if (and (< start at) (and (< close (bytesLength bs)) (= (optionOr (stringSlice text (- start 2) start) "") "(:")))
            (fold (fn [(m (Map String String)) (name String)] -> (Map String String) (mapSet m name block)) acc names)
            acc))))))

fn target file: String -> (Option String)
  (mapGet (mapFromPairs (list (pair "reader.c" "reader") (pair "value.c" "value") (pair "gc.c" "memory") (pair "gcHooks.c" "memory") (pair "resolve.c" "resolve") (pair "compile.c" "compile")
                              (pair "vm.c" "eval") (pair "hostBuiltins.c" "eval") (pair "prelude.c" "prelude") (pair "float.c" "float") (pair "loader.c" "loader") (pair "test.c" "runner")
                              (pair "check.c" "runner") (pair "main.c" "main") (pair "embed.c" "build") (pair "arrays.c" "arrays") (pair "zstd.c" "zstd")
                              (pair "snappy.c" "snappy") (pair "thrift.c" "thrift") (pair "parquet.c" "parquet") (pair "abi.c" "value") (pair "types.c" "value")
                              (pair "kernels.c" "arrays") (pair "parallel.c" "eval") (pair "sys.c" "runner") (pair "sysNet.c" "runner") (pair "verbs.c" "main")))
    file)

fn viaBuiltin name: String -> (Option String)
  (mapGet (mapFromPairs (list (pair "bStringLength" "stringLength") (pair "bStringSlice" "stringSlice") (pair "bStringConcat" "stringConcat"))) name)

fn floorRuling file: String name: String -> Bool
  (or (= file "strFloor.c")
      (and (= file "abi.c")
           (listContains? (list "asl_rt_init" "asl_rt_global_root" "asl_rt_spill" "globalSlots" "nglobalSlots" "capglobalSlots" "stackTop" "scanStack"
                                "locateStack" "scanFakeFrames" "externalRoots" "abiGcRoots" "gcMutatorRoots" "ready") name)))

(schema Row (:f text String) (:f floor Bool) (:f classified Bool))

fn row k: String nm: (Map String String) scan: (Map String String) floors: (Map String String) -> Row
  (let [(cut (optionOr (stringIndexOf k "|") 0)) (file (optionOr (stringSlice k 0 cut) "")) (name (optionOr (stringSlice k (+ cut 1) (stringLength k)) ""))
        (inNm (mapGet nm k)) (inScan (mapGet scan k))
        (origin (if (some? inNm) (if (some? inScan) "nm+scan" "nm") "scan"))
        (lead (str "  (:s :file \"" file "\" :sym \"" name "\" :kind \"" (optionOr inNm (optionOr inScan "")) "\" :origin " origin))]
    (if (= file "gcHooks.c")
      (Row :text (str lead " :class fixture :reason \"test-only GC hooks\")") :floor false :classified true)
      (mt (mapGet floors name)
        ((some block) (Row :text (str lead " :class floor :block " block ")") :floor true :classified true))
        ((none) (mt (viaBuiltin name)
          ((some alias) (Row :text (str lead " :class floor :block stringPrimitives :allowlistName \"" alias "\")") :floor true :classified true))
          ((none) (if (floorRuling file name)
            (Row :text (str lead " :class floor :block memory :ruling FLOORRT)") :floor true :classified true)
            (mt (target file)
              ((some t) (Row :text (str lead " :class toMigrate :target \"asl/packages/asl-eval/src/" t ".asl\")") :floor false :classified true))
              ((none) (Row :text (str lead " :class unclassified)") :floor false :classified false))))))))))

fn budgets -> (List (Pair String (Pair (List String) Int64)))
  (list (pair "reader" (pair (list "reader.c" "reader.h") 900)) (pair "valueGc" (pair (list "value.c" "value.h" "gc.c") 1000))
        (pair "resolveCompile" (pair (list "resolve.c" "compile.c" "compile.h") 1800)) (pair "vm" (pair (list "vm.c" "hostBuiltins.c") 1200))
        (pair "prelude" (pair (list "prelude.c") 2500)) (pair "float" (pair (list "float.c") 150)) (pair "loader" (pair (list "loader.c") 500))
        (pair "mainTestCheck" (pair (list "main.c" "test.c" "check.c" "verbs.c") 900)) (pair "arrays" (pair (list "arrays.c") 500))
        (pair "zstd" (pair (list "zstd.c") 1800)) (pair "snappy" (pair (list "snappy.c") 300)) (pair "thriftParquet" (pair (list "thrift.c" "thrift.h" "parquet.c") 1500))
        (pair "embed" (pair (list "embed.c") 200)))

fn sumLines files: (List String) counts: (Map String Int64) -> Int64
  (fold (fn [(acc Int64) (f String)] -> Int64 (+ acc (optionOr (mapGet counts f) 0))) 0 files)

fn quoteAll names: (List String) -> String
  (stringJoin (map (fn [(s String)] -> String (str "\"" s "\"")) names) " ")

fn linesSection sources: (List Source) -> String
  (let [(counts (fold (fn [(m (Map String Int64)) (s Source)] -> (Map String Int64) (mapSet m s.name (lineCount s.text))) (mapEmpty) sources))
        (names (map (fn [(s Source)] -> String s.name) sources))
        (covered (fold (fn [(acc (List String)) (b (Pair String (Pair (List String) Int64)))] -> (List String) (listAppend acc (pairFirst (pairSecond b)))) (list) (budgets)))
        (missing (filter (fn [(s String)] -> Bool (not (listContains? covered s))) names))]
    (str "  (:lines :method \"wc -l per file\"\n"
      (stringJoin (map (fn [(s String)] -> String (str "    (:f \"" s "\" :lines " (stringFromInt64 (optionOr (mapGet counts s) 0)) ")\n")) names) "")
      (stringJoin (map (fn [(b (Pair String (Pair (List String) Int64)))] -> String
                         (let [(total (sumLines (pairFirst (pairSecond b)) counts)) (limit (pairSecond (pairSecond b)))]
                           (str "    (:budget " (pairFirst b) " :lines " (stringFromInt64 total) " :limit " (stringFromInt64 limit) " :within " (if (<= total limit) "true" "false") ")\n")))
                    (budgets)) "")
      "    (:total " (stringFromInt64 (sumLines names counts)) " :limit 13150)"
      (if (listEmpty? missing) "" (str "\n    (:unbudgeted " (quoteAll missing) ")"))
      ")\n"))

fn render keys: (List String) rows: (List Row) floors: (Map String String) sources: (List Source) -> String
  (let [(floorCount (listLength (filter (fn [(r Row)] -> Bool r.floor) rows)))
        (fixtureCount (listLength (filter (fn [(r Row)] -> Bool (stringContains? r.text ":class fixture")) rows)))
        (gcRest (map (fn [(k String)] -> String (optionOr (stringSlice k 5 (stringLength k)) "")) (filter (fn [(k String)] -> Bool (and (stringStartsWith? k "gc.c|") (none? (mapGet floors (optionOr (stringSlice k 5 (stringLength k)) ""))))) keys)))]
    (str "(:floorInventory :v 1 :unit U13 :allowlist \"tests/acceptance/r1Host/floor.asn\"\n"
      "  :method \"keys = nm -P over the objects of sh asl/host/build.sh (libaslhost.a and libaslrt.a members but gcAsl.o, which is ASL, plus main.c at -O2), undefined U w v and compiler temporaries l_ ltmp L lCPI ___ excluded, function-local statics keep the nm name, union a column-0 definition scan of asl/host/src/*.c taking every declarator of a variable declaration; generated by asl/host/tools/genInventory.asl\"\n"
      "  :counts (:total " (stringFromInt64 (listLength rows)) " :floor " (stringFromInt64 floorCount) " :toMigrate " (stringFromInt64 (- (listLength rows) (+ floorCount fixtureCount))) " :fixture " (stringFromInt64 fixtureCount) " :unclassified 0)\n"
      "  :note \"floor entries named by C function rather than allowlist name carry :allowlistName; R2 renames or the allowlist maps them, since nm minus floor.asn is by name\"\n"
      (linesSection sources)
      "  (:disputes :by R1impl :for R1gate :d \"classified toMigrate because floor.asn does not name them; each is memory or syscall work by role\"\n"
      "    (:x :syms (" (quoteAll gcRest) ") :role memory :d \"gc.c internals: allocator, mark stack, pacing; the allowlist names only the six asl_ entry points\")\n"
      "    (:x :syms (\"bFileReadBytes\" \"bFileReadString\" \"bPathCanonicalize\") :role syscalls :d \"fileReadBytes, fileReadString and realPath builtins, file_read and pathCanonicalize shims under other names\")\n"
      "    (:x :syms (\"legacy\") :role syscalls :d \"main.c exec of asl-core-legacy; retires with U11 and T3\"))\n"
      "  (:symbols\n" (stringJoin (map (fn [(r Row)] -> String r.text) rows) "\n") "))\n"))

fn aslObjects -> (List String)
  (list "gcAsl.o" "rtAbi.o")

fn inventory! root: String objDir: String -> (Result String String)
  (let [(src (str root "/asl/host/src"))]
    (mt (dirList objDir) ((err e) (err (str "object dir unreadable " objDir ": " e))) ((ok objEntries)
      (mt (dirList src) ((err e) (err (str "source dir unreadable " src ": " e))) ((ok srcEntries)
        (mt (nmObjects! (listSort (filter (fn [(s String)] -> Bool (and (stringEndsWith? s ".o") (not (listContains? (aslObjects) s)))) objEntries)) objDir (mapEmpty)) ((err e) (err e)) ((ok nm)
          (mt (readSources! (listSort (filter (fn [(s String)] -> Bool (or (stringEndsWith? s ".c") (stringEndsWith? s ".h"))) srcEntries)) src (list)) ((err e) (err e)) ((ok sources)
            (mt (fileReadString (str root "/tests/acceptance/r1Host/floor.asn")) ((err e) (err (str "floor.asn unreadable: " e))) ((ok floorText)
              (let [(scan (fold (fn [(m (Map String String)) (s Source)] -> (Map String String) (if (stringEndsWith? s.name ".c") (scanLines (stringLines s.text) s.name m) m)) (mapEmpty) sources))
                    (floors (floorBlocks floorText (stringToBytes floorText) 0 (mapEmpty)))
                    (keys (listSort (listAppend (mapKeys nm) (filter (fn [(k String)] -> Bool (none? (mapGet nm k))) (mapKeys scan)))))
                    (rows (map (fn [(k String)] -> Row (row k nm scan floors)) keys))
                    (unclassified (filter (fn [(r Row)] -> Bool (not r.classified)) rows))]
                (if (listEmpty? unclassified)
                  (ok (render keys rows floors sources))
                  (err (str "unclassified symbols:\n" (stringJoin (map (fn [(r Row)] -> String r.text) unclassified) "\n"))))))))))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (if (not (= (listLength args) 3)) (err "usage: genInventory ROOT OBJDIR OUT")
    (mt (inventory! (optionOr (listGet args 0) "") (optionOr (listGet args 1) ""))
      ((err e) (err e))
      ((ok text) (mt (fileWrite (optionOr (listGet args 2) "") text) ((err e) (err (str "write failed: " e))) ((ok _) (ok 0))))))
