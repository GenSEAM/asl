(module ws/asl/tools/contextSpend
  :x [main runPaths! loadCounter! summary initialMeter addTool]
  :i [(asl-tokenizer/tokenizer :a tok)
      (asl-json/json :a j)])

(schema ToolCount
  (:f n Int64)
  (:f tok Int64))

(schema Meter
  (:f files Int64)
  (:f replies (List Int64))
  (:f sendMessages Int64)
  (:f handbacks Int64)
  (:f briefs (List Int64))
  (:f byTool (Map String ToolCount))
  (:f oversize Int64)
  (:f nonText (Map String Int64))
  (:f peak Int64))

fn loadCounter! dataDir: String -> (Result tok/Tokenizer String)
  (tok/loadTokenizer! dataDir)

fn initialMeter -> Meter
  (Meter :files 0 :replies (list) :sendMessages 0 :handbacks 0 :briefs (list)
         :byTool (mapEmpty) :oversize 0 :nonText (mapEmpty) :peak 0)

fn value obj: j/Json key: String -> j/Json
  (optionOr (j/jsonGet obj key) (j/jnull))

fn stringValue v: j/Json -> String
  (mt v ((j/jstr s) s) (_ ""))

fn textValue v: j/Json -> (Option String)
  (mt v ((j/jstr s) (some s)) (_ none))

fn numberValue v: j/Json -> Int64
  (mt v
    ((j/jint n) n)
    ((j/jfloat f) (optionOr (float64ToInt64 f) 0))
    ((j/jnum f) (optionOr (float64ToInt64 f) 0))
    ((j/jstr s) (optionOr (stringToInt64 s) 0))
    (_ 0))

fn truthy v: j/Json -> Bool
  (mt v
    ((j/jnull) false)
    ((j/jbool b) b)
    ((j/jint n) (!= n 0))
    ((j/jfloat n) (!= n 0.0))
    ((j/jnum n) (!= n 0.0))
    ((j/jstr s) (not (stringEmpty? s)))
    ((j/jarr xs) (not (listEmpty? xs)))
    ((j/jobj xs) (not (listEmpty? xs))))

fn array v: j/Json -> (List j/Json)
  (mt v ((j/jarr xs) xs) (_ (list)))

fn isType obj: j/Json expected: String -> Bool
  (= (stringValue (value obj "type")) expected)

fn textBlock b: j/Json -> String
  (if (isType b "text") (stringValue (value b "text")) "")

fn contentText content: j/Json -> String
  (mt content
    ((j/jstr s) s)
    ((j/jarr xs) (stringJoin (map textBlock xs) ""))
    (_ ""))

fn tokenCount! tokenizer: tok/Tokenizer text: String -> Int64
  (tok/countTokens! tokenizer text)

fn summary values: (List Int64) -> String
  (if (listEmpty? values)
    "(:n 0 :tok 0 :median 0 :max 0)"
    (let [(sorted (listSort values))
          (n (listLength sorted))
          (sum (listSum sorted))
          (middle (optionOr (listGet sorted (/ n 2)) 0))
          (median (if (= (mod n 2) 1) middle
                    (/ (+ (optionOr (listGet sorted (- (/ n 2) 1)) 0) middle) 2)))
          (maximum (optionOr (listMax sorted) 0))]
      (str "(:n " (stringFromInt64 n) " :tok " (stringFromInt64 sum)
           " :median " (stringFromInt64 median) " :max " (stringFromInt64 maximum) ")")))

fn addTool m: Meter name: String size: Int64 -> Meter
  (let [(old (optionOr (mapGet m.byTool name) (ToolCount :n 0 :tok 0)))
        (nextCount (ToolCount :n (+ old.n 1) :tok (+ old.tok size)))
        (large (if (> size 2000) 1 0))]
    (with m :byTool (mapSet m.byTool name nextCount) :oversize (+ m.oversize large)))

fn addNonText m: Meter kind: String -> Meter
  (let [(count (optionOr (mapGet m.nonText kind) 0))]
    (with m :nonText (mapSet m.nonText kind (+ count 1))))

fn nonTextBlocks m: Meter blocks: (List j/Json) -> Meter
  (if (listEmpty? blocks) m
    (let [(head (optionOr (listHead blocks) (j/jnull)))
          (tail (optionOr (listTail blocks) (list)))
          (kind (value head "type"))]
      (mt kind
        ((j/jstr s) (if (= s "text") (nonTextBlocks m tail) (nonTextBlocks (addNonText m s) tail)))
        (_ (nonTextBlocks m tail)))))

fn addReply m: Meter n: Int64 -> Meter
  (with m :replies (cons n m.replies))

fn addBrief m: Meter n: Int64 -> Meter
  (with m :briefs (cons n m.briefs))

fn setPeak m: Meter n: Int64 -> Meter
  (with m :peak (max m.peak n))

fn setKinds m: Meter send: Int64 handback: Int64 -> Meter
  (with m :sendMessages send :handbacks handback)

fn assistantBlocks! tokenizer: tok/Tokenizer m: Meter names: (Map String String) blocks: (List j/Json) -> (Pair Meter (Map String String))
  (if (listEmpty? blocks) (pair m names)
    (let [(b (optionOr (listHead blocks) (j/jnull)))
          (tail (optionOr (listTail blocks) (list)))
          (kind (stringValue (value b "type")))]
      (if (!= kind "tool_use") (assistantBlocks! tokenizer m names tail)
        (let [(id (stringValue (value b "id")))
              (nameJ (value b "name"))
              (name (stringValue nameJ))
              (inp (value b "input"))
              (msg (value inp "message"))
              (nextNames (mapSet names id name))
              (reply (textValue msg))]
          (mt reply
            ((none) (assistantBlocks! tokenizer m nextNames tail))
            ((some text)
              (if (= name "SubagentHandback")
                (assistantBlocks! tokenizer
                  (setKinds (addReply m (tokenCount! tokenizer text)) m.sendMessages (+ m.handbacks 1))
                  nextNames tail)
                (if (and (= name "SendMessage")
                         (or (= (stringValue (value inp "to")) "team-lead")
                             (= (stringValue (value inp "to")) "main")))
                  (assistantBlocks! tokenizer
                    (setKinds (addReply m (tokenCount! tokenizer text)) (+ m.sendMessages 1) m.handbacks)
                    nextNames tail)
                  (assistantBlocks! tokenizer m nextNames tail)))))))))

fn resultBlocks! tokenizer: tok/Tokenizer m: Meter names: (Map String String) blocks: (List j/Json) -> Meter
  (if (listEmpty? blocks) m
    (let [(b (optionOr (listHead blocks) (j/jnull)))
          (tail (optionOr (listTail blocks) (list)))]
      (if (!= (stringValue (value b "type")) "tool_result")
        (resultBlocks! tokenizer m names tail)
        (let [(id (stringValue (value b "tool_use_id")))
              (name (optionOr (mapGet names id) "unknown"))
              (content (value b "content"))
              (parts (array content))
              (size (tokenCount! tokenizer (contentText content)))
              (nextM (nonTextBlocks (addTool m name size) parts))]
          (resultBlocks! tokenizer nextM names tail)))))

fn hasToolResult blocks: (List j/Json) -> Bool
  (if (listEmpty? blocks) false
    (let [(b (optionOr (listHead blocks) (j/jnull)))]
      (or (= (stringValue (value b "type")) "tool_result")
          (hasToolResult (optionOr (listTail blocks) (list))))))

fn usageContext usage: j/Json -> Int64
  (+ (+ (numberValue (value usage "input_tokens"))
        (numberValue (value usage "cache_creation_input_tokens")))
     (numberValue (value usage "cache_read_input_tokens")))

fn recordLine! tokenizer: tok/Tokenizer m: Meter names: (Map String String) line: String -> (Pair Meter (Map String String))
  (mt (j/jsonParse line)
    ((err _) (pair m names))
    ((ok rec)
      (let [(msg (value rec "message"))
            (content (value msg "content"))
            (blocks (array content))
            (type (stringValue (value rec "type")))]
        (if (= type "assistant")
          (let [(nextM (setPeak m (usageContext (value msg "usage"))))
                (next (assistantBlocks! tokenizer nextM names blocks))]
            (pair (pairFirst next) (pairSecond next)))
          (if (= type "user")
            (let [(withResults (if (hasToolResult blocks)
                                  (resultBlocks! tokenizer m names blocks)
                                  m))]
              (if (truthy (value rec "isMeta"))
                (pair withResults names)
                (let [(text (contentText content))]
                  (if (stringEmpty? text) (pair withResults names)
                    (pair (addBrief withResults (tokenCount! tokenizer text)) names)))))
            (pair m names))))))

fn records! tokenizer: tok/Tokenizer m: Meter names: (Map String String) lines: (List String) -> Meter
  (if (listEmpty? lines) m
    (let [(raw (optionOr (listHead lines) ""))
          (next (recordLine! tokenizer m names raw))]
      (records! tokenizer (pairFirst next) (pairSecond next) (optionOr (listTail lines) (list)))))

fn processFiles! tokenizer: tok/Tokenizer m: Meter files: (List String) -> (Result Meter String)
  (if (listEmpty? files) (ok m)
    (let [(path (optionOr (listHead files) ""))
          (tail (optionOr (listTail files) (list)))
          (r (fileReadString path))]
      (mt r
        ((err e) (err (str "read " path " failed: " e)))
        ((ok content)
          (processFiles! tokenizer (records! tokenizer m (mapEmpty) (stringLines content)) tail)))))

fn gatherDir! path: String -> (Result (List String) String)
  (mt (dirList path)
    ((err e) (err e))
    ((ok names)
      (gatherNames! path names (list))))

fn endsJsonl path: String -> Bool
  (stringEndsWith? path ".jsonl")

fn gatherNames! path: String names: (List String) acc: (List String) -> (Result (List String) String)
  (if (listEmpty? names) (ok acc)
    (let [(name (optionOr (listHead names) ""))
          (full (str path "/" name))
          (stat (fileStat full))]
      (mt stat
        ((err _) (gatherNames! path (optionOr (listTail names) (list)) acc))
        ((ok info)
          (if (stringStartsWith? name ".")
            (gatherNames! path (optionOr (listTail names) (list)) acc)
            (if info.isDir
              (mt (gatherDir! full)
                ((err e) (err e))
                ((ok nested) (gatherNames! path (optionOr (listTail names) (list)) (listAppend acc nested))))
              (gatherNames! path (optionOr (listTail names) (list))
                (if (and info.isFile (endsJsonl full)) (cons full acc) acc))))))))

fn uniqueSorted sorted: (List String) previous: String acc: (List String) -> (List String)
  (if (listEmpty? sorted) (listReverse acc)
    (let [(path (optionOr (listHead sorted) ""))]
      (uniqueSorted (optionOr (listTail sorted) (list)) path
                    (if (= path previous) acc (cons path acc)))))

fn gatherPaths! paths: (List String) acc: (List String) -> (Result (List String) String)
  (if (listEmpty? paths) (ok (uniqueSorted (listSort acc) "" (list)))
    (let [(path (optionOr (listHead paths) ""))]
      (mt (fileStat path)
        ((err _) (gatherPaths! (optionOr (listTail paths) (list)) acc))
        ((ok info)
          (if info.isDir
            (mt (gatherDir! path)
              ((err e) (err e))
              ((ok nested) (gatherPaths! (optionOr (listTail paths) (list)) (listAppend acc nested))))
            (gatherPaths! (optionOr (listTail paths) (list))
              (if info.isFile (cons path acc) acc)))))))

fn nonTextPairs pairs: (List (Pair String Int64)) -> String
  (if (listEmpty? pairs) ""
    (let [(p (optionOr (listHead pairs) (pair "" 0)))
          (kind (pairFirst p))
          (count (pairSecond p))]
      (str ":" (camel kind) " " (stringFromInt64 count)
           (if (listEmpty? (optionOr (listTail pairs) (list))) "" (str " " (nonTextPairs (optionOr (listTail pairs) (list))))))))

fn camelWord word: String -> String
  (if (stringEmpty? word) ""
    (str (stringUpper (optionOr (stringSlice word 0 1) ""))
         (stringLower (optionOr (stringSlice word 1 (stringLength word)) ""))))

fn camelRest words: (List String) -> String
  (if (listEmpty? words) ""
    (str (camelWord (optionOr (listHead words) ""))
         (camelRest (optionOr (listTail words) (list)))))

fn camel kind: String -> String
  (let [(words (stringSplit kind "_"))]
    (if (listEmpty? words) kind
      (str (optionOr (listHead words) "") (camelRest (optionOr (listTail words) (list))))))

fn toolForms pairs: (List (Pair String ToolCount)) -> String
  (if (listEmpty? pairs) ""
    (let [(p (optionOr (listHead pairs) (pair "" (ToolCount :n 0 :tok 0))))
          (name (pairFirst p))
          (value (pairSecond p))
          (form (str "(:tool \"" name "\" :n " (stringFromInt64 value.n)
                     " :tok " (stringFromInt64 value.tok) ")"))]
      (str form (if (listEmpty? (optionOr (listTail pairs) (list))) "" (str " " (toolForms (optionOr (listTail pairs) (list))))))))

fn render m: Meter -> String
  (let [(tools (toolForms (mapPairs m.byTool)))
        (nonText (str "(" (nonTextPairs (mapPairs m.nonText))
                      (if (= (mapSize m.nonText) 0) "" " ") ":tok :unmeasured)"))
        (resultRows (mapPairs m.byTool))
        (resultN (fold (fn [(acc Int64) (row (Pair String ToolCount))] -> Int64 (+ acc (pairSecond row).n)) 0 resultRows))
        (resultTok (fold (fn [(acc Int64) (row (Pair String ToolCount))] -> Int64 (+ acc (pairSecond row).tok)) 0 resultRows))]
    (str "(:contextSpend :v 1 :tokenizer o200kBase :files " (stringFromInt64 m.files)
         "\n  :replies " (summary m.replies)
         "\n  :replyKinds (:sendMessage " (stringFromInt64 m.sendMessages)
         " :subagentHandback " (stringFromInt64 m.handbacks) ")"
         "\n  :briefs " (summary m.briefs)
         "\n  :toolResults (:n " (stringFromInt64 resultN) " :tok " (stringFromInt64 resultTok)
         " :over2000 " (stringFromInt64 m.oversize) " :nonTextBlocks " nonText " :byTool (" tools "))"
         "\n  :peakContext " (stringFromInt64 m.peak) ")"))

fn withFiles! tokenizer: tok/Tokenizer files: (List String) -> (Result String String)
  (if (listEmpty? files)
    (err "(:contextSpend :status :error :code ERR_NO_TRANSCRIPTS)")
    (mt (processFiles! tokenizer (Meter :files (listLength files) :replies (list) :sendMessages 0
                     :handbacks 0 :briefs (list) :byTool (mapEmpty) :oversize 0 :nonText (mapEmpty) :peak 0) files)
      ((err e) (err e))
      ((ok m) (ok (render m)))))

fn runPaths! tokenizer: tok/Tokenizer paths: (List String) -> (Result String String)
  (mt (gatherPaths! paths (list))
    ((err e) (err e))
    ((ok files) (withFiles! tokenizer files)))

fn parentOf path: String -> String
  (let [(parts (stringSplit path "/"))]
    (if (<= (listLength parts) 2) "/" (stringJoin (listTake parts (- (listLength parts) 1)) "/")))

fn configRootFrom! dir: String found: (Option String) -> (Option String)
  (let [(hit (if (fileExists? (str (if (= dir "/") "" dir) "/.asl.config.asn")) (some dir) found))]
    (if (= dir "/") hit (configRootFrom! (parentOf dir) hit)))

fn entryScript! -> (Option String)
  (let [(res (processRun (str "ps -o args= -p " (stringFromInt64 (procSelf)))))
        (asl (filter (fn [(t String)] -> Bool (stringEndsWith? t ".asl")) (stringSplit (stringTrim res.stdout) " ")))]
    (if (= res.exitCode 0) (listHead asl) (none)))

fn workspaceRoot! -> (Result String String)
  (let [(envRoot (optionOr (envGet "ASL_ROOT") ""))
        (fromScript (mt (entryScript!)
                      ((none) (none))
                      ((some script) (mt (realPath script) ((ok real) (configRootFrom! (parentOf real) (none))) ((err _) (none))))))
        (fromCwd (mt (realPath ".") ((ok cwd) (configRootFrom! cwd (none))) ((err _) (none))))]
    (cond
      ((not (stringEmpty? envRoot)) (ok envRoot))
      ((some? fromScript) (ok (optionOr fromScript "")))
      ((some? fromCwd) (ok (optionOr fromCwd "")))
      (else (err "no .asl.config.asn above the script or the working directory; set ASL_ROOT"))))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (mt (workspaceRoot!) ((err e) (err e)) ((ok root) (tok/loadTokenizer! (str root "/data/tokenizers"))))
    ((err e) (err (str "contextSpend: " e)))
    ((ok tokenizer)
      (mt (runPaths! tokenizer args)
        ((err e) (if (stringStartsWith? e "(:contextSpend :status :error")
                    (do (fdWrite 1 (str (optionOr (stringSlice e 0 (- (stringLength e) 1)) e) " :paths (" (stringJoin (map (fn [(p String)] -> String (str "\"" p "\"")) args) " ") "))\n")) (ok 1))
                    (err e)))
        ((ok receipt) (do (fdWrite 1 (str receipt "\n")) (ok 0))))))
