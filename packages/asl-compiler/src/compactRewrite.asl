(module asl-compiler/compactRewrite
  :d "Automated token shrinking AST rewriter pass for 1-to-2 token modular aliases"
  :x [CompactionRule
      makeCompactionRule
      rewriteAstTokens
      compactionTarget?
      defaultCompactionRules]
  :i [])

(dfs CompactionRule
  (:f verbose Str "Verbose original symbol identifier")
  (:f compact Str "Compact modular alias replacement")
  (:f savings I64 "Estimated token savings count"))

(df makeCompactionRule [(verbose Str) (compact Str) (savings I64)] -> CompactionRule
  :d "Constructs a compaction rule with verbose symbol, compact alias, and estimated token savings."
  (CompactionRule :verbose verbose :compact compact :savings savings))

(df defaultCompactionRules [] -> (List CompactionRule)
  :d "Standard catalog of 17 canonical token shrinking compaction rules across core packages."
  (list
    (makeCompactionRule "string-starts-with?" "txt/starts?" 2)
    (makeCompactionRule "string-ends-with?" "txt/ends?" 2)
    (makeCompactionRule "string-contains?" "txt/has?" 2)
    (makeCompactionRule "string-split" "txt/split" 1)
    (makeCompactionRule "string-length" "txt/len" 1)
    (makeCompactionRule "string-trim" "txt/trim" 1)
    (makeCompactionRule "normalize-path" "v/norm" 2)
    (makeCompactionRule "vfs-normalize-path" "v/norm" 3)
    (makeCompactionRule "vfs-read" "v/read" 1)
    (makeCompactionRule "vfs-write" "v/write" 1)
    (makeCompactionRule "vfs-resolve" "v/resolve" 1)
    (makeCompactionRule "path-resolve" "v/resolve" 2)
    (makeCompactionRule "task-claim" "task/claim" 1)
    (makeCompactionRule "task-complete" "task/settle" 2)
    (makeCompactionRule "task-state" "task/state" 1)
    (makeCompactionRule "supervise-step" "proc/status" 2)
    (makeCompactionRule "supervise-list" "proc/list" 2)))

(df compactionTarget? [(sym Str) (rules (List CompactionRule))] -> Bool
  :d "Checks whether a symbol is a candidate for compaction rewrite."
  (fold (fn [(acc Bool) (r CompactionRule)] -> Bool
          (if acc true (= (.-verbose r) sym)))
        false
        rules))

(df findRule [(sym Str) (rules (List CompactionRule))] -> (Option CompactionRule)
  :d "Finds matching compaction rule for a symbol."
  (fold (fn [(acc (Option CompactionRule)) (r CompactionRule)] -> (Option CompactionRule)
          (mt acc
            ((some _) acc)
            ((none) (if (= (.-verbose r) sym) (some r) (none)))))
        (none)
        rules))

(df isDelimOrWs [(ch Str)] -> Bool
  :d "Returns true if character is a delimiter or whitespace."
  (or (string-contains? "()[]{}" ch)
      (string-contains? " \t\n\r" ch)))

(dfs RewriteState
  (:f out (List Str) "Reversed list of emitted text chunks")
  (:f cur Str "Accumulated token characters")
  (:f inStr Bool "Inside double-quoted string literal")
  (:f esc Bool "Previous character was backslash escape inside string")
  (:f inCmt Bool "Inside line comment"))

(df flushAtom [(out (List Str)) (atom Str) (rules (List CompactionRule))] -> (List Str)
  :d "Flushes an atom token, rewriting it if it matches a compaction rule."
  (if (string-empty? atom)
    out
    (mt (findRule atom rules)
      ((some r) (list-cons (.-compact r) out))
      ((none) (list-cons atom out)))))

(df rewriteStep [(st RewriteState) (ch Str) (rules (List CompactionRule))] -> RewriteState
  :d "Processes one character during AST token rewrite."
  (if (.-inCmt st)
    (if (= ch "\n")
      (RewriteState
        :out (list-cons "\n" (.-out st))
        :cur ""
        :inStr false
        :esc false
        :inCmt false)
      (RewriteState
        :out (list-cons ch (.-out st))
        :cur ""
        :inStr false
        :esc false
        :inCmt true))
    (if (.-inStr st)
      (if (.-esc st)
        (RewriteState
          :out (list-cons ch (.-out st))
          :cur ""
          :inStr true
          :esc false
          :inCmt false)
        (if (= ch "\\")
          (RewriteState
            :out (list-cons "\\" (.-out st))
            :cur ""
            :inStr true
            :esc true
            :inCmt false)
          (if (= ch "\"")
            (RewriteState
              :out (list-cons "\"" (.-out st))
              :cur ""
              :inStr false
              :esc false
              :inCmt false)
            (RewriteState
              :out (list-cons ch (.-out st))
              :cur ""
              :inStr true
              :esc false
              :inCmt false))))
      (if (= ch "\"")
        (let [(flushed (flushAtom (.-out st) (.-cur st) rules))]
          (RewriteState
            :out (list-cons "\"" flushed)
            :cur ""
            :inStr true
            :esc false
            :inCmt false))
        (if (= ch ";")
          (let [(flushed (flushAtom (.-out st) (.-cur st) rules))]
            (RewriteState
              :out (list-cons ";" flushed)
              :cur ""
              :inStr false
              :esc false
              :inCmt true))
          (if (isDelimOrWs ch)
            (let [(flushed (flushAtom (.-out st) (.-cur st) rules))]
              (RewriteState
                :out (list-cons ch flushed)
                :cur ""
                :inStr false
                :esc false
                :inCmt false))
            (RewriteState
              :out (.-out st)
              :cur (str (.-cur st) ch)
              :inStr false
              :esc false
              :inCmt false)))))))

(df rewriteAstTokens [(src Str) (rules (List CompactionRule))] -> Str
  :d "Traverses source code and rewrites AST tokens matching compaction rules."
  (let [(chars (string-chars src))
        (initSt (RewriteState :out (list) :cur "" :inStr false :esc false :inCmt false))
        (finalSt (fold (fn [(st RewriteState) (ch Str)] -> RewriteState
                          (rewriteStep st ch rules))
                        initSt
                        chars))
        (finalOut (flushAtom (.-out finalSt) (.-cur finalSt) rules))]
    (string-join (list-reverse finalOut) "")))
