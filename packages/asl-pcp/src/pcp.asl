(module asl-pcp/pcp
  :d "Project Constitution Protocol (PCP) native in-language engine facade."
  :x [verify-module
      check-invariants
      query-rule
      scan-pcp-references
      scan-shortcodes
      encode-ledger-asn
      parse-ledger-asn]
  :i [(types :a t) (scanner :a sc) (ledger :a lg) (verify :a v)])

(df verify-module [(ledger t/Ledger) (mod-name Str) (refs (List Str))] -> t/ScanResult
  :d "Verifies a module against a constitutional ledger."
  (v/verify-module ledger mod-name refs))

(df check-invariants [(ledger t/Ledger) (active (List Str))] -> (List Str)
  :d "Checks invariant rules and detects constitutional violations."
  (v/check-invariants ledger active))

(df query-rule [(ledger t/Ledger) (code Str)] -> (Option t/PcpRule)
  :d "Queries a constitutional rule from ledger by shortcode string."
  (v/query-rule ledger code))

(df scan-pcp-references [(text Str)] -> (List Str)
  :d "Scans source text for all PCP shortcode references."
  (sc/scan-pcp-references text))

(df scan-shortcodes [(text Str)] -> (List t/Shortcode)
  :d "Scans source text and returns parsed Shortcode records."
  (sc/scan-shortcodes text))

(df encode-ledger-asn [(ledger t/Ledger)] -> Str
  :d "Encodes a Ledger into an ASN tabular constitution document."
  (lg/encode-ledger-asn ledger))

(df parse-ledger-asn [(src Str)] -> (Option t/Ledger)
  :d "Parses an ASN tabular constitution document into a Ledger."
  (lg/parse-ledger-asn src))
