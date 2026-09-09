(module asl-compiler/compact-rewrite
  :d "Automated token shrinking AST rewriter pass for 1-to-2 token modular aliases"
  :x [CompactionRule
      make-compaction-rule
      rewrite-ast-tokens
      is-compaction-target?
      default-compaction-rules]
  :i [])

(dfs CompactionRule
  (:f verbose Str "Verbose original symbol identifier")
  (:f compact Str "Compact modular alias replacement")
  (:f savings I64 "Estimated token savings count"))

(df make-compaction-rule [(verbose Str) (compact Str) (savings I64)] -> CompactionRule
  :d "Constructs a compaction rule with verbose symbol, compact alias, and estimated token savings."
  (CompactionRule :verbose verbose :compact compact :savings savings))

(df default-compaction-rules [] -> (List CompactionRule)
  :d "Standard catalog of 17 canonical token shrinking compaction rules across core packages."
  (list
    (make-compaction-rule "string-starts-with?" "txt/starts?" 2)
    (make-compaction-rule "string-ends-with?" "txt/ends?" 2)
    (make-compaction-rule "string-contains?" "txt/has?" 2)
    (make-compaction-rule "string-split" "txt/split" 1)
    (make-compaction-rule "string-length" "txt/len" 1)
    (make-compaction-rule "string-trim" "txt/trim" 1)
    (make-compaction-rule "normalize-path" "v/norm" 2)
    (make-compaction-rule "vfs-normalize-path" "v/norm" 3)
    (make-compaction-rule "vfs-read" "v/read" 1)
    (make-compaction-rule "vfs-write" "v/write" 1)
    (make-compaction-rule "vfs-resolve" "v/resolve" 1)
    (make-compaction-rule "path-resolve" "v/resolve" 2)
    (make-compaction-rule "task-claim" "task/claim" 1)
    (make-compaction-rule "task-complete" "task/settle" 2)
    (make-compaction-rule "task-state" "task/state" 1)
    (make-compaction-rule "supervise-step" "proc/status" 2)
    (make-compaction-rule "supervise-list" "proc/list" 2)))

(df is-compaction-target? [(sym Str) (rules (List CompactionRule))] -> Bool
  :d "Checks whether a symbol is a candidate for compaction rewrite."
  (fold (fn [(acc Bool) (r CompactionRule)] -> Bool
          (if acc true (= (.-verbose r) sym)))
        false
        rules))

(df find-rule [(sym Str) (rules (List CompactionRule))] -> (Option CompactionRule)
  :d "Finds matching compaction rule for a symbol."
  (fold (fn [(acc (Option CompactionRule)) (r CompactionRule)] -> (Option CompactionRule)
          (mt acc
            ((some _) acc)
            ((none) (if (= (.-verbose r) sym) (some r) (none)))))
        (none)
        rules))

(df is-delim-or-ws [(ch Str)] -> Bool
  :d "Returns true if character is a delimiter or whitespace."
  (or (string-contains? "()[]{}" ch)
      (string-contains? " \t\n\r" ch)))

(dfs RewriteState
  (:f out (List Str) "Reversed list of emitted text chunks")
  (:f cur Str "Accumulated token characters")
  (:f in-str Bool "Inside double-quoted string literal")
  (:f esc Bool "Previous character was backslash escape inside string")
  (:f in-cmt Bool "Inside line comment"))

(df flush-atom [(out (List Str)) (atom Str) (rules (List CompactionRule))] -> (List Str)
  :d "Flushes an atom token, rewriting it if it matches a compaction rule."
  (if (string-empty? atom)
    out
    (mt (find-rule atom rules)
      ((some r) (list-cons (.-compact r) out))
      ((none) (list-cons atom out)))))

(df rewrite-step [(st RewriteState) (ch Str) (rules (List CompactionRule))] -> RewriteState
  :d "Processes one character during AST token rewrite."
  (if (.-in-cmt st)
    (if (= ch "\n")
      (RewriteState
        :out (list-cons "\n" (.-out st))
        :cur ""
        :in-str false
        :esc false
        :in-cmt false)
      (RewriteState
        :out (list-cons ch (.-out st))
        :cur ""
        :in-str false
        :esc false
        :in-cmt true))
    (if (.-in-str st)
      (if (.-esc st)
        (RewriteState
          :out (list-cons ch (.-out st))
          :cur ""
          :in-str true
          :esc false
          :in-cmt false)
        (if (= ch "\\")
          (RewriteState
            :out (list-cons "\\" (.-out st))
            :cur ""
            :in-str true
            :esc true
            :in-cmt false)
          (if (= ch "\"")
            (RewriteState
              :out (list-cons "\"" (.-out st))
              :cur ""
              :in-str false
              :esc false
              :in-cmt false)
            (RewriteState
              :out (list-cons ch (.-out st))
              :cur ""
              :in-str true
              :esc false
              :in-cmt false))))
      (if (= ch "\"")
        (let [(flushed (flush-atom (.-out st) (.-cur st) rules))]
          (RewriteState
            :out (list-cons "\"" flushed)
            :cur ""
            :in-str true
            :esc false
            :in-cmt false))
        (if (= ch ";")
          (let [(flushed (flush-atom (.-out st) (.-cur st) rules))]
            (RewriteState
              :out (list-cons ";" flushed)
              :cur ""
              :in-str false
              :esc false
              :in-cmt true))
          (if (is-delim-or-ws ch)
            (let [(flushed (flush-atom (.-out st) (.-cur st) rules))]
              (RewriteState
                :out (list-cons ch flushed)
                :cur ""
                :in-str false
                :esc false
                :in-cmt false))
            (RewriteState
              :out (.-out st)
              :cur (str (.-cur st) ch)
              :in-str false
              :esc false
              :in-cmt false)))))))

(df rewrite-ast-tokens [(src Str) (rules (List CompactionRule))] -> Str
  :d "Traverses source code and rewrites AST tokens matching compaction rules."
  (let [(chars (string-chars src))
        (init-st (RewriteState :out (list) :cur "" :in-str false :esc false :in-cmt false))
        (final-st (fold (fn [(st RewriteState) (ch Str)] -> RewriteState
                          (rewrite-step st ch rules))
                        init-st
                        chars))
        (final-out (flush-atom (.-out final-st) (.-cur final-st) rules))]
    (string-join (list-reverse final-out) "")))
