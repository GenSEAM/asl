(module asl-pcp/scanner
  :d "AST and source text scanner for PCP shortcode patterns and anchors."
  :x [is-hex-digit?
      check-hex-step
      is-valid-hex4?
      is-valid-shortcode?
      normalize-shortcode
      parse-shortcode
      replace-delim-char
      sanitize-delimiters
      is-non-empty-tok?
      extract-token-shortcode
      scan-pcp-references
      scan-shortcodes]
  :i [(types :a t)])

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
  :d "Normalizes shortcode reference by stripping @pcp: or @ prefixes."
  (let [(trimmed (string-trim raw))]
    (if (string-starts-with? trimmed "@pcp:")
      (mt (string-slice trimmed 5 (string-length trimmed)) ((some s) s) ((none) ""))
      (if (string-starts-with? trimmed "@")
        (mt (string-slice trimmed 1 (string-length trimmed)) ((some s) s) ((none) ""))
        trimmed))))

(df parse-shortcode [(code Str)] -> (Option t/Shortcode)
  :d "Parses a shortcode string into a Shortcode record."
  (let [(norm (normalize-shortcode code))]
    (if (is-valid-shortcode? norm)
      (mt (string-slice norm 0 1)
        ((none) (none))
        ((some pre)
         (mt (t/string-to-shortcode-type pre)
           ((some k) (some (t/make-shortcode k norm)))
           ((none) (none)))))
      (none))))

(df replace-delim-char [(ch Str)] -> Str
  :d "Replaces syntax delimiter with a single space."
  (if (string-contains? " \t\r\n\"()[],;" ch)
    " "
    ch))

(df sanitize-delimiters [(text Str)] -> Str
  :d "Replaces syntax delimiters with whitespace for token scanning."
  (let [(chars (string-chars text))
        (replaced (map replace-delim-char chars))]
    (string-join replaced "")))

(df is-non-empty-tok? [(tok Str)] -> Bool
  :d "Returns true if token has non-whitespace characters."
  (> (string-length (string-trim tok)) 0))

(df extract-token-shortcode [(tok Str)] -> (Option Str)
  :d "Extracts a valid shortcode from a token candidate if valid."
  (let [(norm (normalize-shortcode (string-trim tok)))]
    (if (is-valid-shortcode? norm)
      (some norm)
      (none))))

(df scan-pcp-references [(text Str)] -> (List Str)
  :d "Scans source text for all PCP shortcode references (@pcp:... or bare shortcodes)."
  (let [(clean (sanitize-delimiters text))
        (tokens (string-split clean " "))
        (candidates (filter is-non-empty-tok? tokens))]
    (fold (fn [(acc (List Str)) (tok Str)] -> (List Str)
            (mt (extract-token-shortcode tok)
              ((some sc) (if (list-contains? acc sc) acc (list-cons sc acc)))
              ((none) acc)))
          (list)
          candidates)))

(df scan-shortcodes [(text Str)] -> (List t/Shortcode)
  :d "Scans source text and returns parsed Shortcode records."
  (let [(refs (scan-pcp-references text))]
    (fold (fn [(acc (List t/Shortcode)) (c Str)] -> (List t/Shortcode)
            (mt (parse-shortcode c)
              ((some sc) (list-cons sc acc))
              ((none) acc)))
          (list)
          refs)))
