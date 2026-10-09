(module asl-compiler/compactRewrite :x [CompactionRule makeCompactionRule rewriteAstTokens compactionTarget? defaultCompactionRules] :i [])

(schema CompactionRule (:f verbose Str) (:f compact Str) (:f savings I64))

fn makeCompactionRule verbose: Str compact: Str savings: I64 -> CompactionRule
  (CompactionRule :verbose verbose :compact compact :savings savings)

fn defaultCompactionRules -> (List CompactionRule)
  (list (makeCompactionRule "stringStartsWith?" "txt/starts?" 2) (makeCompactionRule "stringEndsWith?" "txt/ends?" 2) (makeCompactionRule "stringContains?" "txt/has?" 2) (makeCompactionRule "stringSplit" "txt/split" 1) (makeCompactionRule "stringLength" "txt/len" 1) (makeCompactionRule "stringTrim" "txt/trim" 1) (makeCompactionRule "normalize-path" "v/norm" 2) (makeCompactionRule "vfs-normalize-path" "v/norm" 3) (makeCompactionRule "vfs-read" "v/read" 1) (makeCompactionRule "vfs-write" "v/write" 1) (makeCompactionRule "vfs-resolve" "v/resolve" 1) (makeCompactionRule "path-resolve" "v/resolve" 2) (makeCompactionRule "task-claim" "task/claim" 1) (makeCompactionRule "task-complete" "task/settle" 2) (makeCompactionRule "task-state" "task/state" 1) (makeCompactionRule "supervise-step" "proc/status" 2) (makeCompactionRule "supervise-list" "proc/list" 2))

fn compactionTarget? sym: Str rules: (List CompactionRule) -> Bool
  (fold (fn [(acc Bool) (r CompactionRule)] -> Bool (if acc true (= r.verbose sym))) false rules)

fn findRule sym: Str rules: (List CompactionRule) -> (Option CompactionRule)
  (fold (fn [(acc (Option CompactionRule)) (r CompactionRule)] -> (Option CompactionRule) (mt acc ((some _) acc) ((none) (if (= r.verbose sym) (some r) (none))))) (none) rules)

fn isDelimOrWs ch: Str -> Bool
  (or (stringContains? "()[]{}" ch) (stringContains? " \t\n\r" ch))

(schema RewriteState (:f out (List Str)) (:f cur Str) (:f inStr Bool) (:f esc Bool) (:f inCmt Bool))

fn flushAtom out: (List Str) atom: Str rules: (List CompactionRule) -> (List Str)
  (if (stringEmpty? atom) out (mt (findRule atom rules) ((some r) (cons r.compact out)) ((none) (cons atom out))))

fn rewriteStep st: RewriteState ch: Str rules: (List CompactionRule) -> RewriteState
  (if st.inCmt (if (= ch "\n") (RewriteState :out (cons "\n" st.out) :cur "" :inStr false :esc false :inCmt false) (RewriteState :out (cons ch st.out) :cur "" :inStr false :esc false :inCmt true)) (if st.inStr (if st.esc (RewriteState :out (cons ch st.out) :cur "" :inStr true :esc false :inCmt false) (if (= ch "\\") (RewriteState :out (cons "\\" st.out) :cur "" :inStr true :esc true :inCmt false) (if (= ch "\"") (RewriteState :out (cons "\"" st.out) :cur "" :inStr false :esc false :inCmt false) (RewriteState :out (cons ch st.out) :cur "" :inStr true :esc false :inCmt false)))) (if (= ch "\"") (let [(flushed (flushAtom st.out st.cur rules))] (RewriteState :out (cons "\"" flushed) :cur "" :inStr true :esc false :inCmt false)) (if (= ch ";") (let [(flushed (flushAtom st.out st.cur rules))] (RewriteState :out (cons ";" flushed) :cur "" :inStr false :esc false :inCmt true)) (if (isDelimOrWs ch) (let [(flushed (flushAtom st.out st.cur rules))] (RewriteState :out (cons ch flushed) :cur "" :inStr false :esc false :inCmt false)) (with st :cur (str st.cur ch) :inStr false :esc false :inCmt false))))))

fn rewriteAstTokens src: Str rules: (List CompactionRule) -> Str
  (let [(chars (stringChars src)) (initSt (RewriteState :out (list) :cur "" :inStr false :esc false :inCmt false)) (finalSt (fold (fn [(st RewriteState) (ch Str)] -> RewriteState (rewriteStep st ch rules)) initSt chars)) (finalOut (flushAtom finalSt.out finalSt.cur rules))] (stringJoin (listReverse finalOut) ""))
