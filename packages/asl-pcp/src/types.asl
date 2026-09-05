(module asl-pcp/types
  :d "PCP core data types: ShortcodeType, Shortcode, PcpRule, Ledger, and ScanResult."
  :x [ShortcodeType
      Shortcode
      PcpRule
      Ledger
      ScanResult
      make-shortcode
      make-rule
      make-ledger
      make-scan-result
      shortcode-type-to-string
      string-to-shortcode-type])

(dfe ShortcodeType
  (:c p-dec [] "Architectural Decision Record (e.g., d-xxxx)")
  (:c p-crit [] "Architecture Critic Rule (e.g., c-xxxx)")
  (:c p-law [] "System Invariant or Non-negotiable Law (e.g., l-xxxx)")
  (:c p-req [] "Functional or Architectural Requirement (e.g., r-xxxx)"))

(dfs Shortcode
  (:f kind ShortcodeType "Category of the constitutional shortcode")
  (:f code Str "Unique shortcode identifier string (e.g., d-1eed, c-099a)"))

(dfs PcpRule
  (:f code Str "Shortcode identifier string")
  (:f title Str "Human-readable summary title of the constitutional rule")
  (:f why Str "Architectural rationale or justification")
  (:f status Str "Lifecycle status: active, proposed, deprecated, retired"))

(dfs Ledger
  (:f rules (List PcpRule) "List of declared constitutional rules")
  (:f shortcodes (List Str) "List of registered valid shortcode identifiers"))

(dfs ScanResult
  (:f module Str "Target module name scanned")
  (:f referenced (List Str) "Constitutional rules referenced by the module")
  (:f missing (List Str) "Required or invariant rules missing from references"))

(df make-shortcode [(kind ShortcodeType) (code Str)] -> Shortcode
  :d "Constructs a Shortcode record."
  (Shortcode
    :kind kind
    :code code))

(df make-rule [(code Str) (title Str) (why Str) (status Str)] -> PcpRule
  :d "Constructs a PcpRule record."
  (PcpRule
    :code code
    :title title
    :why why
    :status status))

(df make-ledger [(rules (List PcpRule)) (shortcodes (List Str))] -> Ledger
  :d "Constructs a constitutional Ledger record."
  (Ledger
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
