(module asl-forms/bench/parenCensus
  :x [Rx Write Pend Sess Tot rxOf writesOf censusDir! main]
  :i [(asl-regex/regex :a rx) (asl-json/json :a js) (asl-forms/bench/parenBench :a pb)])

; (:m :ref PAREN-BENCH :do "port of scratchpad/paren/census2.py: over Claude Code session transcripts (*.jsonl under a directory) it attributes every tool result that names a delimiter balance error to the write path that last wrote the file the error names (native Write or Edit, heredoc, python, sed or perl, cp or patch, redirect, asl forms), counts (:repaired ...) receipts per path and runs of 3 or more errors on one file; the regexes are the python ones, run by asl-regex, which is byte-oriented and so counts month keys and window cuts in bytes")
(schema Rx
  (:f mark rx/Regex) (:f readCmd rx/Regex) (:f file rx/Regex) (:f forms rx/Regex) (:f aslWord rx/Regex)
  (:f heredoc rx/Regex) (:f redirect rx/Regex) (:f py rx/Regex) (:f pyWrite rx/Regex) (:f sedPerl rx/Regex) (:f copy rx/Regex))

(schema Write (:f kind String) (:f file String))

(schema Pend (:f ws (List Write)) (:f inBytes Int64) (:f isRead Bool) (:f month String))

(schema Sess
  (:f last (Map String String)) (:f pend (Map String Pend))
  (:f streak (Map String Int64)) (:f streakBytes (Map String Int64)) (:f had Bool))

(schema Tot
  (:f writeN (Map String Int64)) (:f errN (Map String Int64)) (:f errFiles (Map String Int64)) (:f repairN (Map String Int64))
  (:f markN (Map String Int64)) (:f loops (Map String Int64)) (:f loopBytes (Map String Int64)) (:f byMonth (Map String Int64))
  (:f sessions Int64) (:f withErr Int64) (:f errTotal Int64))

fn must pat: String -> rx/Regex
  (match (rx/regex-compile! pat)
    ((ok r) r)
    ((err e) (trap "ERR_CENSUS_REGEX" (str pat ": " e))))

fn rxOf -> Rx
  (Rx :mark (must "ERR_READ_UNBALANCED|ERR_UNBALANCED|unclosed delimiter|unmatched close|\\(:unbalanced |unclosed [(\\[{]|unexpected [)\\]}]|unexpected closing|extra closing|missing closing|[)\\]}] closes [(\\[{]|unbalanced (paren|delim|bracket)")
      :readCmd (must "^\\s*(cd [^;&]+(&&|;)\\s*)*(/usr/bin/)?(grep|rg|cat|head|tail|sed -n|less|git (show|log|diff|grep)|awk|wc|ls|find|diff|python3? -I? ?-c .*print)")
      :file (must "([\\w./~-]+\\.as[ln])\\b")
      :forms (must "\\(:(edit|write|txn|fix)\\b")
      :aslWord (must "\\basl\\b")
      :heredoc (must "<<-?\\s*['\"]?\\w+")
      :redirect (must ">>?\\s*\\S+\\.as[ln]")
      :py (must "python3?\\b")
      :pyWrite (must "open\\([^)]*['\"][wa]|write_text|\\.write\\(")
      :sedPerl (must "\\bsed\\b[^|;]*\\s-i|perl\\s+-[a-z]*p[a-z]*i|perl\\s+-[a-z]*i")
      :copy (must "\\b(cp|mv|tee|patch|git apply)\\b"))

fn base p: String -> String
  (optionOr (listHead (listReverse (stringSplit p "/"))) p)

fn bump m: (Map String Int64) k: String n: Int64 -> (Map String Int64)
  (mapSet m k (+ n (mapGetOr m k 0)))

fn jStr j: js/Json key: String -> String
  (match (js/jsonGet j key)
    ((some v) (match v ((js/jstr s) s) (_ "")))
    ((none) ""))

fn jObj j: js/Json key: String -> js/Json
  (match (js/jsonGet j key)
    ((some v) v)
    ((none) (js/jnull)))

fn jList j: js/Json -> (List js/Json)
  (match j ((js/jarr xs) xs) (_ (list)))

fn filesIn rx: Rx s: String -> (List String)
  (map (fn [(m rx/Match)] -> String (base m.text)) (rx/regex-find-all! rx.file s))

; (:m :ref PAREN-BENCH :do "the write a Bash command makes to .asl/.asn files, classified by the first matching shape in the same order as census2.py; Write, Edit and MultiEdit on those extensions are native writes")
fn writesOf rx: Rx name: String inp: js/Json -> (List Write)
  (if (listContains? (list "Write" "Edit" "MultiEdit") name)
    (let [(p (jStr inp "file_path"))]
      (if (or (stringEndsWith? p ".asl") (stringEndsWith? p ".asn")) (list (Write :kind (str "native" name) :file p)) (list)))
    (if (not (= name "Bash"))
      (list)
      (let [(c (jStr inp "command"))]
        (if (not (stringContains? c ".as"))
          (list)
          (let [(files (filesIn rx c))
                (kind (cond
                        ((and (some? (rx/regex-search! rx.forms c)) (some? (rx/regex-search! rx.aslWord c))) "aslForms")
                        ((and (some? (rx/regex-search! rx.heredoc c)) (some? (rx/regex-search! rx.redirect c))) "heredoc")
                        ((and (some? (rx/regex-search! rx.py c)) (some? (rx/regex-search! rx.pyWrite c))) "python")
                        ((some? (rx/regex-search! rx.sedPerl c)) "sedPerl")
                        ((and (some? (rx/regex-search! rx.copy c)) (not (listEmpty? files))) "copyPatch")
                        ((some? (rx/regex-search! rx.redirect c)) "redirect")
                        (else "")))]
            (if (stringEmpty? kind)
              (list)
              (if (listEmpty? files) (list (Write :kind kind :file "?")) (map (fn [(f String)] -> Write (Write :kind kind :file f)) files))))))))

fn markWords -> (List String)
  (list "ERR_READ_UNBALANCED" "ERR_UNBALANCED" "unclosed" "unmatched close" "(:unbalanced " "unexpected" "extra closing" "missing closing" " closes " "unbalanced")

; (:m :ref PAREN-BENCH :do "cheap literal gate before the Pike VM runs over a result: a text with none of these words cannot hold a marker")
fn maybeMarked? t: String -> Bool
  (fold (fn [(a Bool) (w String)] -> Bool (or a (stringContains? t w))) false (markWords))

fn resultText content: js/Json -> String
  (match content
    ((js/jstr s) s)
    ((js/jarr xs) (stringJoin (map (fn [(x js/Json)] -> String (jStr x "text")) (filter (fn [(x js/Json)] -> Bool (match x ((js/jobj _) true) (_ false))) xs)) " "))
    (_ ""))

; (:m :ref PAREN-BENCH :do "a name in file position is a census token when the character before it is not part of a path token and the one after is not a word character, which is what the python findall plus basename yields for a name without a slash")
fn namedIn? t: String fb: String -> Bool
  (namedFrom t fb 0)

fn namedFrom t: String fb: String from: Int64 -> Bool
  (match (stringIndexOf (optionOr (stringSlice t from (stringLength t)) "") fb)
    ((none) false)
    ((some i)
     (let [(at (+ from i))
           (end (+ at (stringLength fb)))
           (pre (if (= at 0) "" (optionOr (stringSlice t (- at 1) at) "")))
           (post (optionOr (stringSlice t end (+ end 1)) ""))
           (preOk (or (stringEmpty? pre) (or (= pre "/") (not (wordish? pre)))))
           (postOk (or (stringEmpty? post) (not (wordChar? post))))]
       (if (and preOk postOk) true (namedFrom t fb (+ at 1))))))

fn wordChar? c: String -> Bool
  (let [(b (bytesGet (stringToBytes c) 0))]
    (or (and (>= b 48) (<= b 57)) (or (and (>= b 65) (<= b 90)) (or (and (>= b 97) (<= b 122)) (= b 95)))))

fn wordish? c: String -> Bool
  (or (wordChar? c) (or (= c ".") (or (= c "~") (= c "-"))))

fn resetStreaks tot: Tot sess: Sess t: String -> (Pair Tot Sess)
  (fold (fn [(a (Pair Tot Sess)) (kv (Pair String Int64))] -> (Pair Tot Sess)
          (let [(tt (pairFirst a)) (ss (pairSecond a)) (fb (pairFirst kv)) (n (pairSecond kv))]
            (if (and (> n 0) (namedIn? t fb))
              (let [(lastK (mapGetOr ss.last fb "unknown"))
                    (t2 (if (>= n 3)
                          (Tot :writeN tt.writeN :errN tt.errN :errFiles tt.errFiles :repairN tt.repairN :markN tt.markN
                               :loops (bump tt.loops lastK 1) :loopBytes (bump tt.loopBytes lastK (mapGetOr ss.streakBytes fb 0))
                               :byMonth tt.byMonth :sessions tt.sessions :withErr tt.withErr :errTotal tt.errTotal)
                          tt))]
                (pair t2 (Sess :last ss.last :pend ss.pend :streak (mapSet ss.streak fb 0) :streakBytes (mapSet ss.streakBytes fb 0) :had ss.had)))
              a)))
        (pair tot sess) (mapPairs sess.streak))

fn firstWrite ws: (List Write) -> String
  (match (listHead ws) ((some w) w.kind) ((none) ""))

fn hasPositive? sess: Sess -> Bool
  (fold (fn [(a Bool) (v Int64)] -> Bool (or a (> v 0))) false (mapValues sess.streak))

fn withTot tot: Tot f: (fn [Tot] -> Tot) -> Tot
  (f tot)

fn onResult rx: Rx tot: Tot sess: Sess id: String t: String -> (Pair Tot Sess)
  (let [(pd (mapGetOr sess.pend id (Pend :ws (list) :inBytes 0 :isRead true :month "")))
        (sess1 (Sess :last sess.last :pend (mapRemove sess.pend id) :streak sess.streak :streakBytes sess.streakBytes :had sess.had))]
    (if pd.isRead
      (pair tot sess1)
      (let [(repairs (if (stringContains? t "(:repaired ") (bump tot.repairN (let [(k (firstWrite pd.ws))] (if (stringEmpty? k) "?" k)) 1) tot.repairN))
            (hit (if (maybeMarked? t) (rx/regex-search! rx.mark t) (none)))
            (tot1 (Tot :writeN tot.writeN :errN tot.errN :errFiles tot.errFiles :repairN repairs :markN tot.markN :loops tot.loops
                       :loopBytes tot.loopBytes :byMonth tot.byMonth :sessions tot.sessions :withErr tot.withErr :errTotal tot.errTotal))]
        (match hit
          ((none) (if (hasPositive? sess1) (resetStreaks tot1 sess1 t) (pair tot1 sess1)))
          ((some h)
           (let [(lo (max 0 (- h.start 400)))
                 (win (optionOr (stringSlice t lo (min (stringLength t) (+ h.end 400))) ""))
                 (names (filesIn rx win))
                 (fb (optionOr (listHead names) ""))
                 (k (if (stringEmpty? fb)
                      (let [(w (firstWrite pd.ws))] (if (stringEmpty? w) "unattributed" w))
                      (mapGetOr sess1.last fb "unattributed")))
                 (mk (optionOr (stringSlice h.text 0 24) h.text))]
             (pair (Tot :writeN tot1.writeN :errN (bump tot1.errN k 1)
                        :errFiles (if (stringEmpty? fb) tot1.errFiles (bump tot1.errFiles fb 1))
                        :repairN tot1.repairN :markN (bump tot1.markN mk 1) :loops tot1.loops :loopBytes tot1.loopBytes
                        :byMonth (bump tot1.byMonth pd.month 1) :sessions tot1.sessions :withErr tot1.withErr :errTotal (+ tot1.errTotal 1))
                   (Sess :last sess1.last :pend sess1.pend
                         :streak (if (stringEmpty? fb) sess1.streak (bump sess1.streak fb 1))
                         :streakBytes (if (stringEmpty? fb) sess1.streakBytes (bump sess1.streakBytes fb (+ pd.inBytes (stringLength t))))
                         :had true))))))))

fn onUse rx: Rx tot: Tot sess: Sess b: js/Json month: String -> (Pair Tot Sess)
  (let [(name (jStr b "name"))
        (inp (jObj b "input"))
        (ws (writesOf rx name inp))
        (cmd (jStr inp "command"))
        (isRead (or (and (not (= name "Bash")) (listEmpty? ws)) (some? (rx/regex-search! rx.readCmd cmd))))
        (last1 (fold (fn [(m (Map String String)) (w Write)] -> (Map String String) (mapSet m (base w.file) w.kind)) sess.last ws))
        (wn (fold (fn [(m (Map String Int64)) (w Write)] -> (Map String Int64) (bump m w.kind 1)) tot.writeN ws))]
    (pair (Tot :writeN wn :errN tot.errN :errFiles tot.errFiles :repairN tot.repairN :markN tot.markN :loops tot.loops :loopBytes tot.loopBytes
               :byMonth tot.byMonth :sessions tot.sessions :withErr tot.withErr :errTotal tot.errTotal)
          (Sess :last last1 :pend (mapSet sess.pend (jStr b "id") (Pend :ws ws :inBytes (stringLength (js/jsonEmit inp)) :isRead isRead :month month))
                :streak sess.streak :streakBytes sess.streakBytes :had sess.had)))

fn onBlock rx: Rx month: String a: (Pair Tot Sess) b: js/Json -> (Pair Tot Sess)
  (let [(ty (jStr b "type"))]
    (cond
      ((= ty "tool_use") (onUse rx (pairFirst a) (pairSecond a) b month))
      ((= ty "tool_result") (onResult rx (pairFirst a) (pairSecond a) (jStr b "tool_use_id") (resultText (jObj b "content"))))
      (else a)))

fn onLine rx: Rx a: (Pair Tot Sess) line: String -> (Pair Tot Sess)
  (if (not (or (stringContains? line "\"tool_use\"") (stringContains? line "\"tool_result\"")))
    a
    (match (js/jsonParse line)
      ((err _) a)
      ((ok d)
       (let [(month (optionOr (stringSlice (jStr d "timestamp") 0 7) ""))
             (content (jObj (jObj d "message") "content"))]
         (fold (fn [(acc (Pair Tot Sess)) (b js/Json)] -> (Pair Tot Sess) (onBlock rx month acc b)) a (jList content))))))

fn emptyTot -> Tot
  (Tot :writeN (mapEmpty) :errN (mapEmpty) :errFiles (mapEmpty) :repairN (mapEmpty) :markN (mapEmpty) :loops (mapEmpty) :loopBytes (mapEmpty) :byMonth (mapEmpty)
       :sessions 0 :withErr 0 :errTotal 0)

fn emptySess -> Sess
  (Sess :last (mapEmpty) :pend (mapEmpty) :streak (mapEmpty) :streakBytes (mapEmpty) :had false)

; (:m :ref PAREN-BENCH :do "end of a session closes the runs still open on it; a session with any error result counts once")
fn endSession tot: Tot sess: Sess -> Tot
  (let [(closed (fold (fn [(t Tot) (kv (Pair String Int64))] -> Tot
                        (if (>= (pairSecond kv) 3)
                          (let [(k (mapGetOr sess.last (pairFirst kv) "unknown"))]
                            (Tot :writeN t.writeN :errN t.errN :errFiles t.errFiles :repairN t.repairN :markN t.markN
                                 :loops (bump t.loops k 1) :loopBytes (bump t.loopBytes k (mapGetOr sess.streakBytes (pairFirst kv) 0))
                                 :byMonth t.byMonth :sessions t.sessions :withErr t.withErr :errTotal t.errTotal))
                          t))
                      tot (mapPairs sess.streak)))]
    (Tot :writeN closed.writeN :errN closed.errN :errFiles closed.errFiles :repairN closed.repairN :markN closed.markN :loops closed.loops
         :loopBytes closed.loopBytes :byMonth closed.byMonth :sessions (+ closed.sessions 1) :withErr (+ closed.withErr (if sess.had 1 0)) :errTotal closed.errTotal))

fn ! censusFile rx: Rx tot: Tot path: String -> Tot
  (match (fileReadString path)
    ((err _) tot)
    ((ok text)
     (let [(r (fold (fn [(a (Pair Tot Sess)) (l String)] -> (Pair Tot Sess) (onLine rx a l)) (pair tot (emptySess)) (stringLines text)))]
       (endSession (pairFirst r) (pairSecond r)))))

fn ! censusDir! dir: String limit: Int64 -> Tot
  (let [(rx (rxOf))
        (paths (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringLines (processRun (str "find '" dir "' -name '*.jsonl' | sort")).stdout)))
        (use (if (> limit 0) (listTake paths limit) paths))]
    (fold (fn [(t Tot) (p String)] -> Tot (censusFile rx t p)) (emptyTot) use))

fn rowOf m: (Map String Int64) -> String
  (stringJoin (map (fn [(p (Pair String Int64))] -> String (str "(:k " (pairFirst p) " :n " (pairSecond p) ")"))
                   (listTake (listSortBy (fn [(p (Pair String Int64))] -> Int64 (- 0 (pairSecond p))) (mapPairs m)) 20)) " ")

fn ! main args: (List String) -> (Result Int64 String)
  (match (listHead args)
    ((none) (err "usage: parenCensus.asl DIR [--limit N]  (DIR holds Claude Code *.jsonl transcripts)"))
    ((some dir)
     (let [(limit (optionOr (stringToInt64 (optionOr (listGet args 2) "")) 0))
           (t (censusDir! dir limit))]
       (do
         (println (str "(:sessions " t.sessions " :withParenErr " t.withErr " :parenErrResults " t.errTotal ")"))
         (println (str "(:writes " (rowOf t.writeN) " )"))
         (println (str "(:parenErrByLastWriter " (rowOf t.errN) " )"))
         (println (str "(:repairedReceipts " (rowOf t.repairN) " )"))
         (println (str "(:markers " (rowOf t.markN) " )"))
         (println (str "(:loops3plus " (rowOf t.loops) " )"))
         (println (str "(:loopBytes " (rowOf t.loopBytes) " )"))
         (println (str "(:topFiles " (rowOf t.errFiles) " )"))
         (println (str "(:byMonth " (rowOf t.byMonth) " )"))
         (match (pb/optValue args "--lock")
           ((none) ())
           ((some p)
            (let [(prior (match (fileReadString p) ((ok x) x) ((err _) "")))
                  (rows (list (str "(:sessions " t.sessions " :withParenErr " t.withErr " :parenErrResults " t.errTotal ")")
                              (str "(:writes " (rowOf t.writeN) " )") (str "(:parenErrByLastWriter " (rowOf t.errN) " )")
                              (str "(:repairedReceipts " (rowOf t.repairN) " )") (str "(:markers " (rowOf t.markN) " )")
                              (str "(:loops3plus " (rowOf t.loops) " )") (str "(:loopBytes " (rowOf t.loopBytes) " )")
                              (str "(:topFiles " (rowOf t.errFiles) " )") (str "(:byMonth " (rowOf t.byMonth) " )")))]
              (match (fileWrite p (str prior "(:benchLock :id parenCensus :label \"" (pb/esc (optionOr (pb/optValue args "--label") "")) "\" :date \"" (pb/civilDate (nowNs))
                                       "\" :method \"asl-forms/bench/parenCensus: every tool_result that is not a read command and names a delimiter balance error (ERR_READ_UNBALANCED, ERR_UNBALANCED, (:unbalanced, unclosed, unmatched, extra or missing closing) is attributed to the write path that last wrote the .asl/.asn file the error names; loops are 3 or more errors on one file in one session; loopBytes counts tool input JSON plus result bytes\" :scope \"" (pb/esc dir) ", " (if (> limit 0) (str "first " limit " transcripts by path") "all transcripts") ", Claude Code *.jsonl of this workspace\")\n"
                                       (stringJoin rows "\n") "\n"))
                ((ok _) ())
                ((err e) (eprintln (str "cannot write " p ": " e)))))))
         (ok 0)))))
