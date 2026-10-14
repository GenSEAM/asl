(module asl-gates/gates :x [verifySourceSyntax verifyFileSemantic verifyForeignExt verifyBalance verifyManifestString verifyManifests collectDirectoryFiles findForeignFilesInPaths allowlistedPaths isForeignFile? auditPackageTreeZeroForeignAt auditPackageTreeZeroForeign runSuite main] :i [(asl-parser/ast :a a) (asl-compiler/compiler :a comp) (asl-checker/types :a ty) (asl-checker/check :a chk) (asl-gates/manifestGate :a mg) (asl-gates/auditForeign :a af)])

fn verifySourceSyntax src: Str -> Bool
  (mt (a/parse src) ((ok _) true) ((err _) false))

(schema BalanceState (:f closers (List Str)) (:f inStr Bool) (:f escaped Bool) (:f broken Bool))

fn closerFor ch: Str -> Str
  (if (= ch "(") ")" (if (= ch "[") "]" (if (= ch "{") "}" "")))

fn balanceStep st: BalanceState ch: Str -> BalanceState
  (let [(closers st.closers) (broken (BalanceState :closers closers :inStr false :escaped false :broken true))] (if st.broken st (if st.inStr (if st.escaped (BalanceState :closers closers :inStr true :escaped false :broken false) (if (= ch "\\") (BalanceState :closers closers :inStr true :escaped true :broken false) (if (= ch "\"") (BalanceState :closers closers :inStr false :escaped false :broken false) st))) (if (= ch "\"") (BalanceState :closers closers :inStr true :escaped false :broken false) (if (= ch "@") broken (let [(closer (closerFor ch))] (if (not (stringEmpty? closer)) (BalanceState :closers (cons closer closers) :inStr false :escaped false :broken false) (if (or (= ch ")") (or (= ch "]") (= ch "}"))) (mt (listHead closers) ((some top) (if (= top ch) (BalanceState :closers (optionOr (listTail closers) (list)) :inStr false :escaped false :broken false) broken)) ((none) broken)) st))))))))

fn verifyBalance src: Str -> Bool
  (let [(final (fold (fn [(st BalanceState) (ch Str)] -> BalanceState (balanceStep st ch)) (BalanceState :closers (list) :inStr false :escaped false :broken false) (stringChars src)))] (and (not final.broken) (and (not final.inStr) (listEmpty? final.closers))))

fn verifyManifestString content: Str -> Bool
  (let [(pkg (mg/parsePackageId content))] (and (> (stringLength pkg) 2) (mg/isValidPkgName? pkg)))

fn ! verifyManifests manifestPaths: (List Str) -> (Result I64 (List Str))
  (let [(problems (fold (fn [(acc (List Str)) (path Str)] -> (List Str) (mt (fileRead path) ((err e) (listAppend acc (list (str "Failed to read manifest " path ": " e)))) ((ok content) (if (verifyManifestString content) acc (listAppend acc (list (str path ": no valid package id"))))))) (list) manifestPaths))]
    (if (listEmpty? problems) (ok (listLength manifestPaths)) (err problems)))

fn ! verifyFileSemantic path: Str -> (Result Unit Str)
  (mt (fileRead path) ((err e) (err (str "Failed to read file " path ": " e))) ((ok src) (mt (a/parse src) ((err pe) (err (str path ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": " pe.msg))) ((ok forms) (let [(diags (chk/checkModule forms (mapEmpty) path))] (if (listEmpty? diags) (ok ()) (err (str path ": " (stringFromInt64 (listLength diags)) " semantic error(s)"))))))))

fn verifyForeignExt ext: Str -> Bool
  (or (= ext ".asl") (= ext ".asn"))

fn shellQuote s: Str -> Str
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! collectDirectoryFiles dir: Str -> (Result (List Str) Str)
  (let [(cmd (str "find " (shellQuote dir) " -type f ! -path '*/.*' ! -path '*/node_modules/*' ! -path '*/dist/*' ! -path '*/asl-quantum/*' ! -path '*/asl-arduino/*'")) (res (processRun cmd))]
    (if (= res.exitCode 0)
      (ok (filter (fn [(p Str)] -> Bool (not (stringEmpty? p))) (stringSplit res.stdout "\n")))
      (err (str "Failed to list files under " dir ": find exited " (stringFromInt64 res.exitCode) ": " (stringTrim res.stderr)))))

fn findForeignFilesInPaths paths: (List Str) -> (List Str)
  (filter (fn [(p Str)] -> Bool (not (or (stringEndsWith? p ".asl") (or (stringEndsWith? p ".asn") (stringEndsWith? p ".md"))))) paths)

fn ! allowlistedPaths allowlistPath: Str -> (Result (List Str) Str)
  (mt (fileRead allowlistPath)
    ((err e) (err (str "Failed to read foreign-file allowlist " allowlistPath ": " e)))
    ((ok c)
      (mt (a/parse c)
        ((err pe) (err (str "Foreign-file allowlist " allowlistPath " does not parse: " (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": " pe.msg)))
        ((ok _)
          (let [(allow (af/parseAllowlist c))]
            (cond
              ((not (listEmpty? allow.bad)) (err (str "Foreign-file allowlist " allowlistPath " has malformed entries: " (stringJoin allow.bad "; "))))
              ((listEmpty? allow.order) (err (str "Foreign-file allowlist " allowlistPath " has zero (:path ...) entries")))
              (else (ok allow.order))))))))

fn ! isForeignFile? p: Str -> (Result Bool Str)
  (mt (af/foreignLangOf! p p) ((ok lang) (ok (not (stringEmpty? lang)))) ((err e) (err (str "Failed to read file " p " for foreign-language detection: " e))))

(schema FileSweep (:f files (List Str)) (:f problems (List Str)))

fn ! auditPackageTreeZeroForeignAt roots: (List Str) allowlistPath: Str -> (Result I64 (List Str))
  (mt (allowlistedPaths allowlistPath)
    ((err msg) (err (list msg)))
    ((ok allowed)
      (let [(effectiveRoots (if (listEmpty? roots) (list "asl/packages") roots))
            (listed (fold (fn [(acc FileSweep) (r Str)] -> FileSweep (mt (collectDirectoryFiles r) ((ok fs) (FileSweep :files (listAppend acc.files fs) :problems acc.problems)) ((err e) (FileSweep :files acc.files :problems (listAppend acc.problems (list e)))))) (FileSweep :files (list) :problems (list)) effectiveRoots))
            (allFiles listed.files)
            (violations (fold (fn [(acc (List Str)) (p Str)] -> (List Str) (if (listContains? allowed p) acc (mt (isForeignFile? p) ((err e) (listAppend acc (list e))) ((ok isForeign) (if isForeign (listAppend acc (list p)) acc))))) listed.problems allFiles))]
        (if (listEmpty? violations) (ok (listLength allFiles)) (err violations)))))

fn ! auditPackageTreeZeroForeign roots: (List Str) -> (Result I64 (List Str))
  (auditPackageTreeZeroForeignAt roots "scripts/audit/foreignAllowlist.asn")

fn ! runSuite paths: (List Str) -> (Result I64 Str)
  (fold (fn [(acc (Result I64 Str)) (p Str)] -> (Result I64 Str) (mt acc ((err e) (err e)) ((ok count) (mt (verifyFileSemantic p) ((ok _) (ok (+ count 1))) ((err msg) (err msg)))))) (ok 0) paths)

fn ! main args: (List Str) -> (Result Unit IoError)
  (if (listEmpty? args) (let [(u1 (println "AgentSlang Gate Runner: 0 files specified. Verification clean."))] (ok ())) (mt (runSuite args) ((ok count) (let [(u2 (println (str "=== [Pure ASL Gate] ALL " (stringFromInt64 count) " FILE(S) VERIFIED CLEANLY ===")))] (ok ()))) ((err msg) (let [(u3 (eprintln (str "=== [Pure ASL Gate] FAILED: " msg " ===")))] (err (other))))))
