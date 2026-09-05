(module asl-mem/records
  :d "Architectural Decision Records (ADR), System Invariant Rules, and Shortcode Verification Ledger in asl-mem."
  :x [ShortcodeType
      Shortcode
      AdrRule
      RecordsLedger
      ScanResult
      make-shortcode
      make-rule
      make-ledger
      make-scan-result
      shortcode-type-to-string
      string-to-shortcode-type
      is-valid-shortcode?
      normalize-shortcode
      scan-shortcodes
      find-rule
      query-rule
      is-invariant-rule?
      check-invariants
      verify-module])

(dfe ShortcodeType
  (:c p-dec [] "Architectural Decision Record (e.g., d-xxxx)")
  (:c p-crit [] "Architecture Critic Rule (e.g., c-xxxx)")
  (:c p-law [] "System Invariant or Non-negotiable Law (e.g., l-xxxx)")
  (:c p-req [] "Functional or Architectural Requirement (e.g., r-xxxx)"))

(dfs Shortcode
  (:f kind ShortcodeType "Category of the architectural shortcode")
  (:f code Str "Unique shortcode identifier string (e.g., d-1eed, c-099a)"))

(dfs AdrRule
  (:f code Str "Shortcode identifier string")
  (:f title Str "Human-readable summary title of the architectural rule")
  (:f why Str "Architectural rationale or justification")
  (:f status Str "Lifecycle status: active, proposed, deprecated, retired"))

(dfs RecordsLedger
  (:f rules (List AdrRule) "List of declared architectural rules and decisions")
  (:f shortcodes (List Str) "List of registered valid shortcode identifiers"))

(dfs ScanResult
  (:f module Str "Target module name scanned")
  (:f referenced (List Str) "Architectural rules referenced by the module")
  (:f missing (List Str) "Required invariant rules missing from references"))

(df make-shortcode [(kind ShortcodeType) (code Str)] -> Shortcode
  :d "Constructs a Shortcode record."
  (Shortcode
    :kind kind
    :code code))

(df make-rule [(code Str) (title Str) (why Str) (status Str)] -> AdrRule
  :d "Constructs an AdrRule record."
  (AdrRule
    :code code
    :title title
    :why why
    :status status))

(df make-ledger [(rules (List AdrRule)) (shortcodes (List Str))] -> RecordsLedger
  :d "Constructs an architectural RecordsLedger record."
  (RecordsLedger
    :rules rules
    :shortcodes shortcodes))

(df make-scan-result [(mod-name Str) (referenced (List Str)) (missing (List Str))] -> ScanResult
  :d "Constructs a ScanResult record."
  (ScanResult
    :module mod-name
    :referenced referenced
    :missing missing))

(df shortcode-type-to-string [(st ShortcodeType)] -> Str
  :d "Converts ShortcodeType enum to string prefix."
  (mt st
    ((p-dec) "d")
    ((p-crit) "c")
    ((p-law) "l")
    ((p-req) "r")))

(df string-to-shortcode-type [(prefix Str)] -> (Option ShortcodeType)
  :d "Parses shortcode prefix string into ShortcodeType."
  (cond
    ((= prefix "d") (some (p-dec)))
    ((= prefix "c") (some (p-crit)))
    ((= prefix "l") (some (p-law)))
    ((= prefix "r") (some (p-req)))
    ((= prefix "p-dec") (some (p-dec)))
    ((= prefix "p-crit") (some (p-crit)))
    ((= prefix "p-law") (some (p-law)))
    ((= prefix "p-req") (some (p-req)))
    (:else (none))))

(df is-hex-digit? [(c Str)] -> Bool
  :d "Returns true if single-character string is a valid hex digit."
  (if (string-empty? c)
    false
    (if (> (string-length c) 1)
      false
      (string-contains? "0123456789abcdefABCDEF" c))))

(df check-hex-step [(ok Bool) (ch Str)] -> Bool
  :d "Accumulator step checking if character is hex digit."
  (if ok
    (is-hex-digit? ch)
    false))

(df is-valid-hex4? [(hex Str)] -> Bool
  :d "Checks whether a 4-character string consists of hexadecimal digits."
  (if (= (string-length hex) 4)
    (fold check-hex-step true (string-chars hex))
    false))

(df is-valid-shortcode? [(code Str)] -> Bool
  :d "Checks if a shortcode matches standard format (e.g. d-1eed, c-099a, l-a250, r-8d8e)."
  (if (= (string-length code) 6)
    (mt (string-slice code 0 1)
      ((none) false)
      ((some pre)
       (mt (string-slice code 1 2)
         ((none) false)
         ((some hyp)
          (mt (string-slice code 2 6)
            ((none) false)
            ((some hex-part)
             (and (string-contains? "dclr" pre)
                  (and (= hyp "-")
                       (is-valid-hex4? hex-part)))))))))
    false))

(df normalize-shortcode [(raw Str)] -> Str
  :d "Normalizes shortcode reference by stripping @adr:, @rule:, @pcp: or @ prefixes."
  (let [(trimmed (string-trim raw))]
    (if (string-starts-with? trimmed "@adr:")
      (option-or (string-slice trimmed 5 (string-length trimmed)) "")
      (if (string-starts-with? trimmed "@rule:")
        (option-or (string-slice trimmed 6 (string-length trimmed)) "")
        (if (string-starts-with? trimmed "@pcp:")
          (option-or (string-slice trimmed 5 (string-length trimmed)) "")
          (if (string-starts-with? trimmed "@")
            (option-or (string-slice trimmed 1 (string-length trimmed)) "")
            trimmed))))))

(df replace-delim-char [(ch Str)] -> Str
  :d "Maps punctuation delimiters to whitespace."
  (if (string-contains? " \t\n\r,;:()[]{}\"'" ch)
    " "
    ch))

(df sanitize-delimiters [(raw Str)] -> Str
  :d "Replaces punctuation with spaces for token splitting."
  (string-join (map replace-delim-char (string-chars raw)) ""))

(df is-non-empty-tok? [(t Str)] -> Bool
  :d "Filter predicate rejecting empty token strings."
  (not (string-empty? (string-trim t))))

(df extract-token-shortcode [(tok Str)] -> (Option Str)
  :d "Extracts valid shortcode string from a whitespace-separated token."
  (let [(norm (normalize-shortcode tok))]
    (if (is-valid-shortcode? norm)
      (some norm)
      (none))))

(df scan-shortcodes [(text Str)] -> (List Str)
  :d "Extracts all valid architectural shortcode references found in text."
  (let [(sanitized (sanitize-delimiters text))
        (tokens (filter is-non-empty-tok? (string-split sanitized " ")))]
    (fold (fn [(acc (List Str)) (tok Str)] -> (List Str)
            (mt (extract-token-shortcode tok)
              ((some sc)
               (if (list-contains? acc sc)
                 acc
                 (list-append acc (list sc))))
              ((none) acc)))
          (list)
          tokens)))

(df tail-rules [(rules (List AdrRule))] -> (List AdrRule)
  :d "Returns safe tail of rules list."
  (mt (list-tail rules)
    ((some tl) tl)
    ((none) (list))))

(df head-rule-or-default [(rules (List AdrRule))] -> AdrRule
  :d "Safe head of rules list."
  (mt (list-head rules)
    ((some h) h)
    ((none) (make-rule "" "" "" ""))))

(df find-rule [(rules (List AdrRule)) (target Str)] -> (Option AdrRule)
  :d "Finds a rule matching target shortcode string in a list of rules."
  (if (list-empty? rules)
    (none)
    (let [(r (head-rule-or-default rules))]
      (if (= (.-code r) target)
        (some r)
        (find-rule (tail-rules rules) target)))))

(df query-rule [(ledger RecordsLedger) (code Str)] -> (Option AdrRule)
  :d "Queries an architectural rule from ledger by shortcode string."
  (let [(norm (normalize-shortcode code))]
    (find-rule (.-rules ledger) norm)))

(df is-invariant-rule? [(r AdrRule)] -> Bool
  :d "Returns true if rule is an active system invariant law."
  (and (= (.-status r) "active")
       (string-starts-with? (.-code r) "l-")))

(df find-missing-invariants [(rules (List AdrRule)) (active (List Str))] -> (List Str)
  :d "Collects all active invariant laws missing from the active list."
  (fold (fn [(acc (List Str)) (r AdrRule)] -> (List Str)
          (if (is-invariant-rule? r)
            (let [(c (.-code r))]
              (if (list-contains? active c)
                acc
                (list-append acc (list c))))
            acc))
        (list)
        rules))

(df find-unregistered-refs [(ledger RecordsLedger) (refs (List Str))] -> (List Str)
  :d "Finds referenced shortcodes not present in ledger shortcodes list."
  (fold (fn [(acc (List Str)) (code Str)] -> (List Str)
          (if (list-contains? (.-shortcodes ledger) code)
            acc
            (if (list-contains? acc code)
              acc
              (list-append acc (list code)))))
        (list)
        refs))

(df check-invariants [(ledger RecordsLedger) (active (List Str))] -> (List Str)
  :d "Validates that all declared active invariant laws are present in active list."
  (find-missing-invariants (.-rules ledger) active))

(df verify-module [(ledger RecordsLedger) (mod-name Str) (source-text Str)] -> ScanResult
  :d "Performs complete verification scan over module source against architectural ledger."
  (let [(refs (scan-shortcodes source-text))
        (missing (find-missing-invariants (.-rules ledger) refs))
        (unreg (find-unregistered-refs ledger refs))
        (all-missing (fold (fn [(acc (List Str)) (u Str)] -> (List Str)
                             (if (list-contains? acc u) acc (list-append acc (list u))))
                           missing
                           unreg))]
    (make-scan-result mod-name refs all-missing)))
