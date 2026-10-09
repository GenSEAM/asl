(module ws/asl/tools/observe/tokenCost
  :x [observeTokenCost! kindOf shebangInterp?]
  :i [(ws/asl/tools/observe/common :a c)
      (asl-tokenizer/tokenizer :a tok)])

(schema Entry (:f path String) (:f kind String) (:f count Int64) (:f binary Bool))

fn foreignExts -> (List String)
  (list ".c" ".h" ".py" ".pyw" ".sh" ".bash" ".zsh" ".js" ".mjs" ".cjs" ".jsx" ".ts" ".tsx" ".rs" ".go" ".swift" ".rb" ".java" ".kt" ".cpp" ".cc" ".hpp" ".m" ".mm" ".zig" ".lua" ".pl" ".php" ".ps1")

fn shebangNames -> (List String)
  (list "bash" "sh" "zsh" "python" "python3" "node" "perl" "ruby")

fn hasNul bs: Bytes i: Int64 end: Int64 -> Bool
  (cond ((>= i end) false) ((= (bytesGet bs i) 0) true) (else (hasNul bs (+ i 1) end)))

fn firstLineEnd bs: Bytes i: Int64 end: Int64 -> Int64
  (cond ((>= i end) end) ((= (bytesGet bs i) 10) (+ i 1)) (else (firstLineEnd bs (+ i 1) end)))

fn asciiDigit? b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn versionRest? bs: Bytes i: Int64 n: Int64 -> Bool
  (cond ((>= i n) true)
        ((let [(b (bytesGet bs i))] (or (asciiDigit? b) (= b 46) (= b 95) (= b 45))) (versionRest? bs (+ i 1) n))
        (else false))

fn versionTail? t: String -> Bool
  (let [(bs (stringToBytes t)) (n (bytesLength bs))
        (i0 (if (and (> n 0) (let [(b (bytesGet bs 0))] (or (= b 45) (= b 95) (= b 46)))) 1 0))
        (i1 (if (and (< i0 n) (= (bytesGet bs i0) 118)) (+ i0 1) i0))]
    (or (= n 0) (and (< i1 n) (asciiDigit? (bytesGet bs i1)) (versionRest? bs (+ i1 1) n))))

fn shebangInterp? interp: String -> Bool
  (let [(low (stringLower interp))]
    (listAny? (fn [(name String)] -> Bool
                (and (stringStartsWith? low name) (versionTail? (optionOr (stringSlice low (stringLength name) (stringLength low)) ""))))
              (shebangNames)))

fn wordsLoop s: String bs: Bytes i: Int64 n: Int64 start: Int64 acc: (List String) -> (List String)
  (let [(flush (fn [(end Int64)] -> (List String) (if (> end start) (cons (optionOr (stringSlice s start end) "") acc) acc)))]
    (if (>= i n)
      (listReverse (flush n))
      (let [(sp (c/spaceLenAt bs i n))]
        (if (> sp 0)
          (wordsLoop s bs (+ i sp) n (+ i sp) (flush i))
          (wordsLoop s bs (+ i 1) n start acc)))))

fn pyWords s: String -> (List String)
  (let [(bs (stringToBytes s))] (wordsLoop s bs 0 (bytesLength bs) 0 (list)))

fn skipFlags words: (List String) -> (Option String)
  (mt (listHead words)
    ((none) (none))
    ((some w) (if (stringStartsWith? w "-") (skipFlags (optionOr (listTail words) (list))) (some w))))

fn shebangKind txt: String -> String
  (let [(bs (stringToBytes txt))
        (end (firstLineEnd bs 0 (min 1024 (bytesLength bs))))
        (first (optionOr (stringSlice txt 0 end) ""))]
    (if (or (hasNul bs 0 end) (not (c/utf8Valid? first)))
      "other"
      (let [(line (c/pyStrip first))]
        (if (not (stringStartsWith? line "#!"))
          "other"
          (let [(words (pyWords (c/pyStrip (optionOr (stringSlice line 2 (stringLength line)) ""))))]
            (mt (listHead words)
              ((none) "other")
              ((some w0)
                (let [(interp (if (= (c/baseName w0) "env") (skipFlags (optionOr (listTail words) (list))) (some w0)))]
                  (mt interp
                    ((none) "other")
                    ((some w) (if (shebangInterp? (c/baseName w)) "foreign" "other")))))))))))

fn kindOf path: String txt: String -> String
  (let [(ext (stringLower (pairSecond (c/splitExt path))))]
    (cond ((or (= ext ".md") (= ext ".txt")) "prose")
          ((= ext ".asl") "asl") ((= ext ".asn") "asn")
          ((listContains? (foreignExts) ext) "foreign")
          ((not (stringEmpty? ext)) "other")
          (else (shebangKind txt))))

fn entries! tok: tok/Tokenizer root: String paths: (List String) -> (List Entry)
  (listReverse (fold (fn [(acc (List Entry)) (rel String)] -> (List Entry)
          (mt (fileReadString (c/joinPath root rel))
            ((err _) acc)
            ((ok txt)
              (let [(bs (stringToBytes txt))
                    (binary (or (hasNul bs 0 (bytesLength bs)) (not (c/utf8Valid? txt))))]
                (cons (Entry :path rel :kind (kindOf rel txt) :count (if binary 0 (tok/countTokensBytes! tok bs)) :binary binary) acc)))))
        (list) paths))

fn inKind rows: (List Entry) kind: String -> (List Entry)
  (filter (fn [(e Entry)] -> Bool (= e.kind kind)) rows)

fn sumCounts rows: (List Entry) -> Int64
  (fold (fn [(n Int64) (e Entry)] -> Int64 (+ n e.count)) 0 rows)

fn textEntries rows: (List Entry) -> (List Entry)
  (filter (fn [(e Entry)] -> Bool (not e.binary)) rows)

fn binaryCount rows: (List Entry) -> Int64
  (fold (fn [(n Int64) (e Entry)] -> Int64 (+ n (if e.binary 1 0))) 0 rows)

fn maxCount rows: (List Entry) -> String
  (mt (listHead (listSortBy (fn [(e Entry)] -> Int64 (- 0 e.count)) (textEntries rows)))
    ((none) "")
    ((some e) (str " :max (" (c/quoted e.path) " " (stringFromInt64 e.count) ")")))

fn kindForm rows: (List Entry) kind: String -> String
  (let [(same (inKind rows kind))]
    (str "(:kind " kind " :files " (stringFromInt64 (listLength same)) " :tok " (stringFromInt64 (sumCounts same)) (maxCount same) ")"))

fn sortEntries rows: (List Entry) -> (List Entry)
  (listSortBy (fn [(e Entry)] -> Int64 (- 0 e.count)) rows)

fn topEntry e: Entry -> String
  (str "(" (c/quoted e.path) " " (stringFromInt64 e.count) ")")

fn topItems rows: (List Entry) n: Int64 -> String
  (c/joinWith (map topEntry (listTake (textEntries rows) n)) " ")

fn receiptFit head: String rows: (List Entry) total: Int64 shown: Int64 -> (Pair String Int64)
  (let [(receipt (str head " :top (" (topItems rows shown) ") :more " (stringFromInt64 (- total shown)) ")"))]
    (if (or (< (stringLength receipt) 4096) (= shown 0))
      (pair receipt shown)
      (receiptFit head rows total (- shown 1))))

fn tokenizerDir! root: String ctx: c/Ctx -> (Option String)
  (let [(roots (listAppend (mt (c/ctxEnv ctx "ASL_CLI_ROOT") ((none) (list)) ((some r) (if (stringEmpty? r) (list) (list r)))) (list root)))]
    (listHead (filter c/isDir? (map (fn [(r String)] -> String (c/joinPath r "data/tokenizers")) roots))))

fn runDate! ctx: c/Ctx -> (Result String String)
  (if (stringEmpty? ctx.date) (localDate) (ok ctx.date))

fn tokenReceipt! root: String scope: String limit: Int64 ctx: c/Ctx -> (Result String String)
  (mt (tokenizerDir! root ctx)
    ((none) (err (c/rejectLine "ERR_NO_ENCODER" "data/tokenizers is not found under ASL_CLI_ROOT or the workspace; token counts are not estimated" " :method none")))
    ((some dataDir)
      (mt (tok/loadTokenizer! dataDir)
        ((err e) (err (c/rejectLine "ERR_TOKENIZER" e " :method none")))
        ((ok tokenizer)
          (mt (runDate! ctx)
            ((err e) (err (c/rejectLine "ERR_DATE" (str "local date unavailable: " e) "")))
            ((ok date)
              (mt (c/git! (if (stringEmpty? scope) (list "ls-files" "-z") (list "ls-files" "-z" "--" scope)) root ctx)
                ((err e) (err e))
                ((ok git)
                  (if (!= (pairFirst git) 0)
                    (err (c/rejectLine "ERR_GIT" (str "git ls-files failed in " root) ""))
                    (let [(paths (c/sortUnique (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (c/splitByte (pairSecond git) 0))))
                          (rows (sortEntries (entries! tokenizer root paths)))
                          (rev (resultOr (c/shortRev! root ctx) "none"))
                          (kinds (c/joinWith (map (fn [(k String)] -> String (kindForm rows k)) (list "prose" "asl" "asn" "foreign" "other")) " "))
                          (head (str "(:observe :dim tokenCost :v 1 :method o200kBase :scope " (c/quoted (if (stringEmpty? scope) "." scope)) " :rev " rev " :date " date " :kinds (" kinds ") :binary " (stringFromInt64 (binaryCount rows)) " :missing " (stringFromInt64 (- (listLength paths) (listLength rows)))))
                          (total (listLength (textEntries rows)))
                          (fit (receiptFit head rows total (min limit total)))
                          (receipt (pairFirst fit))]
                      (if (>= (stringLength receipt) 4096)
                        (err (c/rejectLine "ERR_RECEIPT_TOO_LARGE" "tokenCost receipt exceeds 4096 bytes with an empty :top" ""))
                        (ok receipt))))))))))))

fn ! observeTokenCost! root: String scope: String limit: Int64 ctx: c/Ctx -> (Result String String)
  (tokenReceipt! root scope limit ctx)
