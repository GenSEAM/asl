(module asl-help/situations
  :x [knownSituations isKnownSituation situationQuestion situationInvariants situationRecommendedTools formatSituationalGuidance]
  :i [(toolDescriptor :a td)])

fn knownSituations -> (List Str)
  (list "orient" "find" "read" "understand" "plan" "change" "verify" "recover" "handoff" "observe")

fn isKnownSituation sit: Str -> Bool
  (let [(known (knownSituations))]
    (fold (fn [(acc Bool) (s Str)] -> Bool (or acc (= s sit))) false known))

fn situationQuestion sit: Str -> Str
  (if (= sit "orient") "Where am I and what is the current step?"
    (if (= sit "find") "Where is this symbol, file or text?"
      (if (= sit "read") "What does this file or section contain?"
        (if (= sit "understand") "What depends on this, and what breaks if I change it?"
          (if (= sit "plan") "Is this plan sound before I start?"
            (if (= sit "change") "How do I modify a file safely?"
              (if (= sit "verify") "Did it actually work?"
                (if (= sit "recover") "Something failed or I am off-plan."
                  (if (= sit "handoff") "My context is filling or I am handing over."
                    (if (= sit "observe") "What actually happened in this session?"
                      "Unknown situation: consult AGENTS.md"))))))))))

fn situationInvariants sit: Str -> (List Str)
  (if (= sit "orient") (list "teleology" "ledger" "syntax" "output")
    (if (= sit "find") (list "context" "names")
      (if (= sit "read") (list "context" "output")
        (if (= sit "understand") (list "capabilities" "architecture")
          (if (= sit "plan") (list "triMap" "gates" "txn")
            (if (= sit "change") (list "txn" "output" "syntax")
              (if (= sit "verify") (list "semantics" "gates" "grading" "numbers")
                (if (= sit "recover") (list "limitCycle" "edge" "teleology")
                  (if (= sit "handoff") (list "ledger" "context")
                    (if (= sit "observe") (list "teleology" "capabilities" "numbers")
                      (list "teleology")))))))))))

fn situationRecommendedTools sit: Str -> (List Str)
  (if (= sit "orient") (list "where" "query" "read" "tree")
    (if (= sit "find") (list "query" "read" "tree")
      (if (= sit "read") (list "read" "doc")
        (if (= sit "understand") (list "query" "read" "check")
          (if (= sit "plan") (list "gate" "consilium" "lens" "where")
            (if (= sit "change") (list "edit" "diff" "flush" "discard")
              (if (= sit "verify") (list "check" "test" "gate" "doctor" "lens")
                (if (= sit "recover") (list "discard" "where" "doctor")
                  (if (= sit "handoff") (list "note" "where")
                    (if (= sit "observe") (list "doctor" "note")
                      (list "where" "tools")))))))))))

fn formatList items: (List Str) -> Str
  (if (listEmpty? items)
    "()"
    (str "(" (stringJoin (map (fn [(s Str)] -> Str (str "\"" s "\"")) items) " ") ")"))

fn formatSituationalGuidance sit: Str -> Str
  (if (not (isKnownSituation sit))
    "(:guidance :status \"error\" :code \":ERR_UNKNOWN_SITUATION\" :message \"Unknown situation requested\")"
    (str "(:guidance :situation \"" sit "\" :question \"" (situationQuestion sit) "\" :invariants " (formatList (situationInvariants sit)) " :recommendedTools " (formatList (situationRecommendedTools sit)) ")"))
