(module asl-pcp/verify
  :d "Constitutional verification, invariant checking, and rule query engine."
  :x [tail-rules
      head-rule-or-default
      find-rule
      query-rule
      is-invariant-rule?
      check-active-code
      find-missing-invariants
      find-unregistered-refs
      check-invariants
      verify-module]
  :i [(types :a t) (scanner :a sc)])

(df tail-rules [(rules (List t/PcpRule))] -> (List t/PcpRule)
  :d "Returns safe tail of rules list."
  (mt (list-tail rules)
    ((some tl) tl)
    ((none) (list))))

(df head-rule-or-default [(rules (List t/PcpRule))] -> t/PcpRule
  :d "Safe head of rules list."
  (mt (list-head rules)
    ((some h) h)
    ((none) (t/make-rule "" "" "" ""))))

(df find-rule [(rules (List t/PcpRule)) (target Str)] -> (Option t/PcpRule)
  :d "Finds a rule matching target shortcode string in a list of rules."
  (if (list-empty? rules)
    (none)
    (let [(r (head-rule-or-default rules))]
      (if (= (.-code r) target)
        (some r)
        (find-rule (tail-rules rules) target)))))

(df query-rule [(ledger t/Ledger) (code Str)] -> (Option t/PcpRule)
  :d "Queries a constitutional rule from ledger by shortcode string."
  (let [(norm (sc/normalize-shortcode code))]
    (find-rule (.-rules ledger) norm)))

(df is-invariant-rule? [(r t/PcpRule)] -> Bool
  :d "Returns true if rule is an active system invariant law."
  (and (= (.-status r) "active")
       (string-starts-with? (.-code r) "l-")))

(df check-active-code [(ledger t/Ledger) (code Str)] -> (Option Str)
  :d "Checks a single active code for status violations."
  (mt (query-rule ledger code)
    ((none) (some (str "unknown:" code)))
    ((some r)
     (cond
       ((= (.-status r) "retired") (some (str "retired:" code)))
       ((= (.-status r) "deprecated") (some (str "deprecated:" code)))
       (:else (none))))))

(df find-missing-invariants [(rules (List t/PcpRule)) (active (List Str))] -> (List Str)
  :d "Collects all active invariant laws missing from the active list."
  (fold (fn [(acc (List Str)) (r t/PcpRule)] -> (List Str)
          (if (is-invariant-rule? r)
            (let [(c (.-code r))]
              (if (list-contains? active c)
                acc
                (list-cons (str "missing-invariant:" c) acc)))
            acc))
        (list)
        rules))

(df find-unregistered-refs [(ledger t/Ledger) (refs (List Str))] -> (List Str)
  :d "Finds referenced shortcodes not present in ledger."
  (fold (fn [(acc (List Str)) (c Str)] -> (List Str)
          (if (list-contains? (.-shortcodes ledger) c)
            acc
            (list-cons (str "unregistered:" c) acc)))
        (list)
        refs))

(df check-invariants [(ledger t/Ledger) (active (List Str))] -> (List Str)
  :d "Detects constitutional violations: retired, deprecated, unknown, or missing invariant rules."
  (let [(norm-active (map sc/normalize-shortcode active))
        (code-violations (fold (fn [(acc (List Str)) (c Str)] -> (List Str)
                                 (mt (check-active-code ledger c)
                                   ((some v) (list-cons v acc))
                                   ((none) acc)))
                               (list)
                               norm-active))
        (missing-invs (find-missing-invariants (.-rules ledger) norm-active))]
    (list-append code-violations missing-invs)))

(df verify-module [(ledger t/Ledger) (mod-name Str) (refs (List Str))] -> t/ScanResult
  :d "Verifies a module references valid rules and complies with constitutional invariants."
  (let [(norm-refs (map sc/normalize-shortcode refs))
        (unregistered (find-unregistered-refs ledger norm-refs))
        (missing-invs (find-missing-invariants (.-rules ledger) norm-refs))
        (all-missing (list-append unregistered missing-invs))]
    (t/make-scan-result mod-name norm-refs all-missing)))
