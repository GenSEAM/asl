(module grammar/corpusTest
  :x [runTests])

schema Scan
  depth: Int64
  low: Int64
  inStr: Bool
  esc: Bool
  inComment: Bool

fn scanChar st: Scan c: String -> Scan
  (cond
    (st.inComment (if (= c "\n") (Scan :depth st.depth :low st.low :inStr false :esc false :inComment false) st))
    (st.esc (Scan :depth st.depth :low st.low :inStr true :esc false :inComment false))
    (st.inStr (Scan :depth st.depth :low st.low :inStr (not (= c "\"")) :esc (= c "\\") :inComment false))
    ((= c "\"") (Scan :depth st.depth :low st.low :inStr true :esc false :inComment false))
    ((= c ";") (Scan :depth st.depth :low st.low :inStr false :esc false :inComment true))
    ((or (= c "(") (or (= c "[") (= c "{"))) (Scan :depth (+ st.depth 1) :low st.low :inStr false :esc false :inComment false))
    ((or (= c ")") (or (= c "]") (= c "}")))
      (let [(d (- st.depth 1))]
        (Scan :depth d :low (if (< d st.low) d st.low) :inStr false :esc false :inComment false)))
    (else st))

fn balanced? text: String -> Bool
  (let [(end (fold (fn [st c] (scanChar st c)) (Scan :depth 0 :low 0 :inStr false :esc false :inComment false) (stringChars text)))]
    (and (= end.depth 0) (and (= end.low 0) (not end.inStr))))

fn ! fileBalanced? path: String want: Bool -> Bool
  (mt (fileRead path)
    ((ok text) (and (> (stringLength text) 0) (= (balanced? text) want)))
    ((err e) false))

fn ! runTests -> Bool
  (do
    (assert (balanced? "(a [b {c}] \"(\" ; )\n)") "a paren inside a string or comment does not count")
    (refute (balanced? "(a (b)") "an unclosed paren is caught")
    (refute (balanced? ")(") "a closer before its opener is caught")
    (assert (fileBalanced? "asl/grammar/corpus/valid/01-basics.asl" true) "valid/01-basics.asl is balanced")
    (assert (fileBalanced? "asl/grammar/corpus/valid/02-match.asl" true) "valid/02-match.asl is balanced")
    (assert (fileBalanced? "asl/grammar/corpus/invalid/unbalanced.asl" false) "invalid/unbalanced.asl is read and found unbalanced")
    true)
