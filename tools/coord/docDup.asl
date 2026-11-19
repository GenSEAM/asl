(module asl-tools/coord/docDup
  :x [Dup symbolOf addedSymbols dupRows dupMessage dupCheckAt!]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref REVIEW-CRITERIA-DOCDUP :do "node2 2026-11-19: reviewers failed STD-DURATION and STD-UNIONFIND for two (:doc :symbol X ...) rows of one symbol in asl-utils/doc.asn (a card-derived copy next to a hand-written one); a gate finds that without a model: in every .asn file the unit changed, a symbol whose row the unit added and that now has two or more rows is a failure naming the symbol and the line of each row; a duplicate the base already had and the unit did not touch is not charged")
(schema Dup (:f symbol String) (:f lines (List Int64)))

fn rowHead -> String
  "(:doc :symbol \""

; (:m :do "the :symbol of a line that is a doc row, empty for any other line")
fn symbolOf line: String -> String
  (let [(t (stringTrim line))]
    (if (not (stringStartsWith? t (rowHead))) ""
      (optionOr (listHead (stringSplit (optionOr (stringSlice t (stringLength (rowHead)) (stringLength t)) "") "\"")) "")))

; (:m :do "the symbols of the doc rows a unified diff adds, distinct, in first-seen order")
fn addedSymbols diff: String -> (List String)
  (fold (fn [(acc (List String)) (l String)] -> (List String)
          (if (or (not (stringStartsWith? l "+")) (stringStartsWith? l "+++")) acc
            (let [(s (symbolOf (optionOr (stringSlice l 1 (stringLength l)) "")))]
              (if (or (stringEmpty? s) (listContains? acc s)) acc (listAppend acc (list s))))))
        (list) (stringLines diff))

fn linesOf text: String symbol: String -> (List Int64)
  (pairSecond (fold (fn [(acc (Pair Int64 (List Int64))) (l String)] -> (Pair Int64 (List Int64))
                      (pair (+ (pairFirst acc) 1)
                            (if (= (symbolOf l) symbol) (listAppend (pairSecond acc) (list (+ (pairFirst acc) 1))) (pairSecond acc))))
                    (pair 0 (list)) (stringLines text)))

; (:m :do "one Dup per symbol of added that has two or more rows in the text, with the 1-based line of every row")
fn dupRows text: String added: (List String) -> (List Dup)
  (filter (fn [(d Dup)] -> Bool (> (listLength d.lines) 1))
          (map (fn [(s String)] -> Dup (Dup :symbol s :lines (linesOf text s))) added))

fn dupMessage path: String dups: (List Dup) -> String
  (stringJoin (map (fn [(d Dup)] -> String
                     (str "duplicate doc rows in " path ": symbol \"" d.symbol "\" has " (stringFromInt64 (listLength d.lines)) " (:doc :symbol ...) rows, at lines " (stringJoin (map stringFromInt64 d.lines) " and ") "; a symbol has one contract row, keep one and delete the other"))
                   dups)
              "; ")

fn ! git wt: String argv: (List String) -> fr/Done
  (fr/runOne (fr/job (listAppend (list "git" "-C" wt) argv) wt (fr/childEnv (list))))

fn namesOf out: String -> (List String)
  (filter (fn [(p String)] -> Bool (stringEndsWith? p ".asn")) (map stringTrim (stringLines out)))

; (:m :do "the duplicate message of a worktree against a base ref, empty when there is none: tracked .asn files the unit changed since the merge-base are judged on the symbols its diff adds, an untracked .asn file on every row; a git call that fails charges nothing, the docRows check reports infrastructure itself")
fn ! dupCheckAt! wt: String base: String -> String
  (let [(mb (stringTrim (git wt (list "merge-base" "HEAD" base)).out))
        (names (git wt (list "diff" "--name-only" "--no-renames" mb)))
        (fresh (git wt (list "ls-files" "--others" "--exclude-standard")))]
    (if (or (stringEmpty? mb) (!= names.exit 0)) ""
      (let [(tracked (map (fn [(p String)] -> String
                            (let [(text (resultOr (fileReadString (str wt "/" p)) ""))]
                              (if (not (stringContains? text (rowHead))) ""
                                (dupMessage p (dupRows text (addedSymbols (git wt (list "diff" "-U0" "--no-renames" mb "--" p)).out))))))
                          (namesOf names.out)))
            (untracked (map (fn [(p String)] -> String
                              (let [(text (resultOr (fileReadString (str wt "/" p)) ""))]
                                (dupMessage p (dupRows text (addedSymbols (stringJoin (map (fn [(l String)] -> String (str "+" l)) (stringLines text)) "\n"))))))
                            (if (= fresh.exit 0) (namesOf fresh.out) (list))))]
        (stringJoin (filter (fn [(m String)] -> Bool (not (stringEmpty? m))) (listAppend tracked untracked)) "; "))))
