(module asl-codec/asn
  :d "ASN reader and writer in pure AgentScript. Normative source: docs/ASN_SPEC.md.

  The token stream comes from packages/asl-parser's lexer rather than a second
  scanner: ASN's whole claim is that it shares AGENT_SPEC_CORE.md section 2's
  lexical structure, and two scanners would be two answers to what a token is.
  What is NOT reused is asl-parser's ast.asl reader, which normalises a Nano atom
  to its verbose spelling: right for a program, wrong for data, because an ASN key
  spelled :f is a field called f and must survive as one."
  :x [AsnValue AsnEntry AsnField
           asn-read asn-write value-ok? is-vec? is-kw? vec-items
           asn-int-value asn-float-value asn-string-value]
  :i [(lexer :a lx)])

(dfs AsnField
  (:f key String "Field key, including its leading colon")
  (:f val AsnValue "Field value"))

(dfs AsnEntry
  (:f key AsnValue "Entry key: a string, integer, boolean or keyword scalar")
  (:f val AsnValue "Entry value")
  (:f paren Bool "True when the source wrote the parenthesised entry form"))

(dfe AsnValue
  (:c asn-nil   []                "The nil sentinel `_`")
  (:c asn-bool  [(b Bool)]        "true or false")
  (:c asn-unit  []                "The unit literal `()`")
  (:c asn-int   [(lex String)]    "Integer literal, held as its source lexeme")
  (:c asn-float [(lex String)]    "Float literal, held as its source lexeme")
  (:c asn-str   [(lex String)]    "String literal, held as its source lexeme with quotes")
  (:c asn-kw    [(k String)]      "Keyword scalar, including its leading colon")
  (:c asn-sym   [(name String)]   "A bare name. Legal as a head, never as a value")
  (:c asn-vec   [(items (List AsnValue))] "A bracketed vector")
  (:c asn-map   [(entries (List AsnEntry))] "A brace map")
  (:c asn-rec   [(fields (List AsnField))] "An anonymous record `(:k v ...)`")
  (:c asn-ctor  [(name String) (fields (List AsnField))] "Named construction `(Name :k v ...)`")
  (:c asn-rows  [(name String) (rows (List AsnValue))] "Schema-grouped rows `(Name [..] ..)`")
  (:c asn-table [(cols (List AsnValue)) (rows (List AsnValue))] "Ad-hoc table `([:c ..] [[..]])`")
  (:c asn-case  [(name String) (args (List AsnValue))] "Union case value `(name v ..)`")
  (:c asn-pair  [(key AsnValue) (val AsnValue)] "A parenthesised map entry, legal only in a map"))

(df value-ok? [(v AsnValue)] -> Bool
  :d "False for the two forms that may appear during reading but never as a value:
      a bare name, which is only ever a head, and a parenthesised map entry,
      which is only ever a direct child of a brace map."
  (mt v
    ((asn-sym _)    false)
    ((asn-pair _ _) false)
    (_              true)))

(df asn-int-value [(v AsnValue)] -> (Option Int64)
  :d "The integer an `asn-int` denotes, or none for any other value."
  (mt v
    ((asn-int lex) (string-to-int64 lex))
    (_             (none))))

(df asn-float-value [(v AsnValue)] -> (Option Float64)
  :d "The float an `asn-float` denotes, or none for any other value."
  (mt v
    ((asn-float lex) (string-to-float64 lex))
    (_               (none))))

(df asn-string-value [(v AsnValue)] -> (Option String)
  :d "The characters an `asn-str` denotes, with quotes stripped and Core §2's
      five escapes decoded; none for any other value."
  (mt v
    ((asn-str lex) (some (unescape (strip-quotes lex))))
    (_             (none))))

(df strip-quotes [(lex String)] -> String
  :d "A string lexeme without its delimiting quotes."
  (mt (string-slice lex 1 (- (string-length lex) 1))
    ((some s) s)
    ((none)   "")))

(dfs UnState
  (:f out (List String) "Decoded characters, most recent first")
  (:f esc Bool "True when the previous character was a backslash"))

(df escape-char [(c String)] -> String
  :d "The character an escape letter denotes. Core §2 defines exactly five."
  (cond
    ((= c "n") "\n")
    ((= c "t") "\t")
    ((= c "r") "\r")
    ((= c "0") "\0")
    (:else     c)))

(df un-step [(st UnState) (c String)] -> UnState
  :d "One fold step of escape decoding."
  (if (.-esc st)
    (UnState :out (list-cons (escape-char c) (.-out st)) :esc false)
    (if (= c "\\")
      (UnState :out (.-out st) :esc true)
      (UnState :out (list-cons c (.-out st)) :esc false))))

(df unescape [(body String)] -> String
  :d "Core §2's five escapes decoded in one left-to-right pass. Repeated
      `string-replace` cannot do this: whatever sentinel it picked to stand for a
      decoded backslash could itself occur in the payload."
  (string-join
    (list-reverse (.-out (fold un-step (UnState :out (list) :esc false)
                               (string-chars body))))
    ""))

(dfs Frame
  (:f open String "The delimiter character that opened this frame")
  (:f line Int64 "Line of the opening delimiter")
  (:f col Int64 "Column of the opening delimiter")
  (:f items (List AsnValue) "Items closed so far, most recent first"))

(dfs ReadState
  (:f toks (List lx/Token) "Tokens not yet consumed")
  (:f stack (List Frame) "Open frames, innermost first")
  (:f done (List AsnValue) "Closed top-level values, most recent first")
  (:f code String "First error code, empty while the read is clean"))

(df rst [(toks (List lx/Token)) (stack (List Frame)) (done (List AsnValue))
            (code String)] -> ReadState
  :d "Constructs a ReadState."
  (ReadState :toks toks :stack stack :done done :code code))

(df tok-tail [(toks (List lx/Token))] -> (List lx/Token)
  :d "The token list without its head; empty when absent."
  (option-or (list-tail toks) (list)))

(df frame-tail [(fs (List Frame))] -> (List Frame)
  :d "The frame stack without its head; empty when absent."
  (option-or (list-tail fs) (list)))

(df item-tail [(items (List AsnValue))] -> (List AsnValue)
  :d "The value list without its head; empty when absent."
  (option-or (list-tail items) (list)))

(df fail [(st ReadState) (code String)] -> ReadState
  :d "Abandon the read, keeping the first code and draining the input so the
      driving loop terminates on the next tick."
  (rst (list) (list) (list) code))

(df is-open? [(raw String)] -> Bool
  :d "True for the three opening delimiters."
  (or (= raw "(") (or (= raw "[") (= raw "{"))))

(df is-close? [(raw String)] -> Bool
  :d "True for the three closing delimiters."
  (or (= raw ")") (or (= raw "]") (= raw "}"))))

(df opener [(close String)] -> String
  :d "The opening delimiter that a closing delimiter must match."
  (cond
    ((= close ")") "(")
    ((= close "]") "[")
    (:else         "{")))

(df is-upper? [(c String)] -> Bool
  :d "True for an ASCII capital, which is what makes a head a type name."
  (string-contains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" c))

(df is-lower? [(c String)] -> Bool
  :d "True for an ASCII lower-case letter, which is what makes a head a case name."
  (string-contains? "abcdefghijklmnopqrstuvwxyz" c))

(dfe HeadKind
  (:c head-type [] "A PascalCase head: named construction or row groups")
  (:c head-case [] "A kebab-case head: a union case value")
  (:c head-bad  [] "Not a head shape Core §2 can produce"))

(df all-chars-in? [(s String) (allowed String)] -> Bool
  :d "True when every character of a non-empty string is in the allowed set."
  (and (not (string-empty? s))
       (list-empty? (filter (fn [(c String)] -> Bool (not (string-contains? allowed c)))
                            (string-chars s)))))

(df kebab-ok? [(s String)] -> Bool
  :d "Core §2's `[a-z][a-z0-9]*(-[a-z0-9]+)*`, without the `?!` suffix.

  Stated as four conditions rather than a regex, which the language has none of:
  a lower-case letter first, only lower-case letters, digits and hyphens after,
  no doubled hyphen and no trailing one. That is exactly the set the pattern
  generates."
  (and (not (string-empty? s))
       (and (is-lower? (first-char s))
            (and (not (string-contains? s "--"))
                 (and (not (string-ends-with? s "-"))
                      (all-chars-in? s "abcdefghijklmnopqrstuvwxyz0123456789-"))))))

(df strip-ident-suffix [(s String)] -> String
  :d "One trailing `?` or `!`, removed. Core §2 admits at most one."
  (if (or (string-ends-with? s "?") (string-ends-with? s "!"))
    (option-or (string-slice s 0 (- (string-length s) 1)) "")
    s))

(df ident-ok? [(s String)] -> Bool
  :d "Core §2's `ident`: a kebab-case name with an optional `?` or `!`."
  (kebab-ok? (strip-ident-suffix s)))

(df type-name-ok? [(s String)] -> Bool
  :d "Core §2's `type-name`: `[A-Z][A-Za-z0-9]*`."
  (and (not (string-empty? s))
       (and (is-upper? (first-char s))
            (all-chars-in? s
              "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"))))

(df bare-head-kind [(s String)] -> HeadKind
  :d "The kind of an unqualified head."
  (cond
    ((type-name-ok? s) (head-type))
    ((ident-ok? s)     (head-case))
    (:else             (head-bad))))

(df part-at [(parts (List String)) (i Int64)] -> String
  :d "The i-th slash-separated part, or the empty string."
  (mt (list-get parts i) ((some p) p) ((none) "")))

(df head-kind [(name String)] -> HeadKind
  :d "The kind of a head, validated as a whole rather than by its first letter.

  Checking only the member let `S/x` and `a/b/c` through: Core §2 gives an alias
  exactly one slash and a lower-case kebab spelling, and a reader looser than
  the grammar is a reader that accepts payloads no other implementation will."
  (let [(parts (string-split name "/"))]
    (cond
      ((= (list-length parts) 1) (bare-head-kind name))
      ((= (list-length parts) 2)
       (if (kebab-ok? (part-at parts 0)) (bare-head-kind (part-at parts 1)) (head-bad)))
      (:else (head-bad)))))

(df first-char [(s String)] -> String
  :d "The leading character, or the empty string."
  (mt (string-slice s 0 1) ((some c) c) ((none) "")))

(df sym-value [(s String)] -> AsnValue
  :d "The value a bare atom denotes. `true`, `false` and `_` are literals; every
      other bare atom is a head and is rejected wherever a value is required."
  (cond
    ((= s "true")  (asn-bool true))
    ((= s "false") (asn-bool false))
    ((= s "_")     (asn-nil))
    (:else         (asn-sym s))))

(df atom-value [(t lx/Token)] -> (Result AsnValue String)
  :d "The value one non-delimiter token denotes. A lexical error becomes the
      `parse` code rather than its own message, so every failure a decoder can
      report is one docs/ASN_SPEC.md §11 names."
  (mt (.-kind t)
    ((lx/tok-int _)     (ok (asn-int (.-raw-text t))))
    ((lx/tok-float _)   (ok (asn-float (.-raw-text t))))
    ((lx/tok-string _)  (ok (asn-str (.-raw-text t))))
    ((lx/tok-keyword _) (ok (asn-kw (.-raw-text t))))
    ((lx/tok-symbol s)  (ok (sym-value s)))
    ((lx/tok-error _)   (err "parse"))
    ((lx/tok-eof)       (err "parse"))
    ((lx/tok-lparen)    (err "parse"))
    ((lx/tok-rparen)    (err "parse"))
    ((lx/tok-lbracket)  (err "parse"))
    ((lx/tok-rbracket)  (err "parse"))))

(df all-values? [(items (List AsnValue))] -> Bool
  :d "True when every element may stand as a value."
  (list-empty? (filter (fn [(v AsnValue)] -> Bool (not (value-ok? v))) items)))

(df all-vectors? [(items (List AsnValue))] -> Bool
  :d "True when every element is a bracketed vector."
  (list-empty? (filter (fn [(v AsnValue)] -> Bool (not (is-vec? v))) items)))

(df is-vec? [(v AsnValue)] -> Bool
  :d "True for a bracketed vector."
  (mt v ((asn-vec _) true) (_ false)))

(df all-keywords? [(items (List AsnValue))] -> Bool
  :d "True when every element is a keyword scalar."
  (list-empty? (filter (fn [(v AsnValue)] -> Bool (not (is-kw? v))) items)))

(df is-kw? [(v AsnValue)] -> Bool
  :d "True for a keyword scalar."
  (mt v ((asn-kw _) true) (_ false)))

(df vec-items [(v AsnValue)] -> (List AsnValue)
  :d "The elements of a vector; empty for anything else."
  (mt v ((asn-vec items) items) (_ (list))))

(df fields-of [(items (List AsnValue)) (acc (List AsnField))]
    -> (Result (List AsnField) String)
  :d "Pair a flat item list into keyword/value fields, failing on an odd length,
      a non-keyword in key position, or a value that cannot stand alone."
  (mt (list-head items)
    ((none) (ok (list-reverse acc)))
    ((some k)
     (mt k
       ((asn-kw key)
        (mt (list-head (item-tail items))
          ((some v)
           (if (value-ok? v)
             (fields-of (item-tail (item-tail items))
                        (list-cons (AsnField :key key :val v) acc))
             (err "parse")))
          ((none) (err "parse"))))
       (_ (err "parse"))))))

(df build-record [(items (List AsnValue))] -> (Result AsnValue String)
  :d "A parenthesised form whose head is a keyword: an anonymous record."
  (mt (fields-of items (list))
    ((ok fs)  (if (list-empty? fs) (err "parse") (ok (asn-rec fs))))
    ((err c)  (err c))))

(df build-named [(name String) (rest (List AsnValue))] -> (Result AsnValue String)
  :d "A parenthesised form whose head is a name: a schema head or a union case."
  (mt (head-kind name)
    ((head-type) (build-schema-head name rest))
    ((head-case) (if (all-values? rest) (ok (asn-case name rest)) (err "parse")))
    ((head-bad)  (err "parse"))))

(df build-schema-head [(name String) (rest (List AsnValue))] -> (Result AsnValue String)
  :d "The one place ASN needs a second token of context: after a type name, a
      keyword opens named construction and a vector opens row groups. Mixing
      them has no reading, so it is a parse failure rather than a warning."
  (mt (list-head rest)
    ((none) (ok (asn-ctor name (list))))
    ((some h)
     (mt h
       ((asn-vec _) (if (all-vectors? rest)
                      (ok (asn-rows name rest))
                      (err "parse")))
       ((asn-kw _)  (mt (fields-of rest (list))
                      ((ok fs)  (ok (asn-ctor name fs)))
                      ((err c)  (err c))))
       (_ (err "parse"))))))

(df build-table [(items (List AsnValue))] -> (Result AsnValue String)
  :d "A parenthesised form whose head is a vector: the ad-hoc table, which is
      exactly a header vector and a vector of row vectors."
  (if (= (list-length items) 2)
    (let [(cols (vec-items (nth-value items 0)))
          (rows (vec-items (nth-value items 1)))]
      (if (and (is-vec? (nth-value items 1))
               (and (all-keywords? cols) (all-vectors? rows)))
        (ok (asn-table cols rows))
        (err "parse")))
    (err "parse")))

(df nth-value [(items (List AsnValue)) (i Int64)] -> AsnValue
  :d "The i-th element, or nil when absent."
  (mt (list-get items i) ((some v) v) ((none) (asn-nil))))

(df build-pair [(items (List AsnValue))] -> (Result AsnValue String)
  :d "A parenthesised map entry `(key value)`. Legal only as a direct child of a
      brace map, which `value-ok?` enforces everywhere else."
  (if (= (list-length items) 2)
    (let [(v (nth-value items 1))]
      (if (value-ok? v)
        (ok (asn-pair (nth-value items 0) v))
        (err "parse")))
    (err "parse")))

(df build-paren [(fr Frame) (items (List AsnValue)) (t lx/Token)]
    -> (Result AsnValue String)
  :d "Dispatch a closed `( ... )` on its first item alone, in one token of
      lookahead. An empty form is unit only when the two delimiters are
      adjacent: Core §2 spells unit `()` as one lexeme, so `( )` is not one."
  (mt (list-head items)
    ((none) (if (and (= (.-line fr) (.-line t)) (= (+ (.-col fr) 1) (.-col t)))
              (ok (asn-unit))
              (err "parse")))
    ((some h)
     (mt h
       ((asn-kw _)    (build-record items))
       ((asn-sym s)   (build-named s (item-tail items)))
       ((asn-vec _)   (build-table items))
       ((asn-str _)   (build-pair items))
       ((asn-int _)   (build-pair items))
       ((asn-bool _)  (build-pair items))
       (_             (err "parse"))))))

(df entries-of [(items (List AsnValue)) (acc (List AsnEntry))]
    -> (Result (List AsnEntry) String)
  :d "Read a brace map's items into entries. A keyword takes the next item as its
      value; a parenthesised entry stands alone; a one-field record is the
      parenthesised entry spelled with a keyword key."
  (mt (list-head items)
    ((none) (ok (list-reverse acc)))
    ((some h)
     (mt h
       ((asn-kw key)
        (mt (list-head (item-tail items))
          ((some v)
           (if (value-ok? v)
             (entries-of (item-tail (item-tail items))
                         (list-cons (AsnEntry :key (asn-kw key) :val v :paren false) acc))
             (err "parse")))
          ((none) (err "parse"))))
       ((asn-pair k v)
        (entries-of (item-tail items)
                    (list-cons (AsnEntry :key k :val v :paren true) acc)))
       ((asn-rec fs)
        (if (= (list-length fs) 1)
          (entries-of (item-tail items)
                      (list-cons (AsnEntry :key (asn-kw (field-key fs))
                                           :val (field-val fs) :paren true) acc))
          (err "parse")))
       (_ (err "parse"))))))

(df field-key [(fs (List AsnField))] -> String
  :d "The single field's key, or the empty string."
  (mt (list-head fs) ((some f) (.-key f)) ((none) "")))

(df field-val [(fs (List AsnField))] -> AsnValue
  :d "The single field's value, or nil."
  (mt (list-head fs) ((some f) (.-val f)) ((none) (asn-nil))))

(df build-map [(items (List AsnValue))] -> (Result AsnValue String)
  :d "A closed `{ ... }`."
  (mt (entries-of items (list))
    ((ok es)  (ok (asn-map es)))
    ((err c)  (err c))))

(df build-form [(fr Frame) (t lx/Token)] -> (Result AsnValue String)
  :d "The value a closed frame denotes."
  (let [(items (list-reverse (.-items fr)))]
    (cond
      ((= (.-open fr) "[") (if (all-values? items) (ok (asn-vec items)) (err "parse")))
      ((= (.-open fr) "{") (build-map items))
      (:else               (build-paren fr items t)))))

(df emit [(st ReadState) (v AsnValue)] -> ReadState
  :d "Place a closed value into the innermost open frame, or at top level."
  (mt (list-head (.-stack st))
    ((some fr)
     (rst (.-toks st)
          (list-cons (Frame :open (.-open fr) :line (.-line fr) :col (.-col fr)
                            :items (list-cons v (.-items fr)))
                     (frame-tail (.-stack st)))
          (.-done st) (.-code st)))
    ((none) (rst (.-toks st) (.-stack st) (list-cons v (.-done st)) (.-code st)))))

(df push-frame [(st ReadState) (raw String) (t lx/Token)] -> ReadState
  :d "Open a frame at a delimiter, remembering where it opened."
  (rst (.-toks st)
       (list-cons (Frame :open raw :line (.-line t) :col (.-col t) :items (list))
                  (.-stack st))
       (.-done st) (.-code st)))

(df close-frame [(st ReadState) (raw String) (t lx/Token)] -> ReadState
  :d "Close the innermost frame, building the value it denotes."
  (mt (list-head (.-stack st))
    ((some fr)
     (if (= (.-open fr) (opener raw))
       (mt (build-form fr t)
         ((ok v)  (emit (rst (.-toks st) (frame-tail (.-stack st))
                             (.-done st) (.-code st)) v))
         ((err c) (fail st c)))
       (fail st "parse")))
    ((none) (fail st "parse"))))

(df read-token [(st ReadState) (t lx/Token)] -> ReadState
  :d "One token consumed. Delimiters are recognised by their text because the
      lexer hands `{` and `}` back as ordinary symbols — they are the type-binder
      braces there, and the map delimiters here."
  (let [(raw (.-raw-text t))
        (advanced (rst (tok-tail (.-toks st)) (.-stack st) (.-done st) (.-code st)))]
    (cond
      ((string-empty? raw) (rst (list) (.-stack st) (.-done st) (.-code st)))
      ((is-open? raw)      (push-frame advanced raw t))
      ((is-close? raw)     (close-frame advanced raw t))
      (:else (mt (atom-value t)
               ((ok v)  (emit advanced v))
               ((err c) (fail st c)))))))

(df read-tick [(st ReadState) (tick Int64)] -> ReadState
  :d "One fold step: consume the next token, or stand still once the input is
      drained or a code has been recorded."
  (if (string-empty? (.-code st))
    (mt (list-head (.-toks st))
      ((some t) (read-token st t))
      ((none)   st))
    st))

(df read-run [(st ReadState) (budget Int64)] -> ReadState
  :d "Run ticks in doubling batches until the token list drains.

  `fold` needs its step count up front and the token count is not known without
  walking it, so the batch doubles: recursion is O(log n) in the token count
  rather than O(n), which is the shape that overflowed the host stack when the
  scanner was written the other way."
  (let [(next (fold read-tick st (range 0 budget)))]
    (if (list-empty? (.-toks next))
      next
      (read-run next (* budget 2)))))

(df asn-read [(src String)] -> (Result AsnValue String)
  :d "Read one ASN document. A document is exactly one balanced value: framing a
      sequence of them belongs to docs/AGENTIC_PROTOCOL.md, not here."
  (finish (read-run (rst (lx/tokenize src) (list) (list) "") 64)))

(df finish [(st ReadState)] -> (Result AsnValue String)
  :d "The document a finished read denotes, or the code it failed under."
  (cond
    ((not (string-empty? (.-code st))) (err (.-code st)))
    ((not (list-empty? (.-stack st)))  (err "parse"))
    ((not (= (list-length (.-done st)) 1)) (err "parse"))
    (:else (mt (list-head (.-done st))
             ((some v) (if (value-ok? v) (ok v) (err "parse")))
             ((none)   (err "parse"))))))

(dfe WItem
  (:c w-text [(t String)] "Literal output text, already final")
  (:c w-val  [(v AsnValue)] "A value still to expand"))

(dfs WState
  (:f work (List WItem) "Pending items, head first")
  (:f out (List String) "Emitted pieces, reversed"))

(df w-tail [(items (List WItem))] -> (List WItem)
  :d "The work list without its head; empty when absent."
  (option-or (list-tail items) (list)))

(df w-atom? [(v AsnValue)] -> Bool
  :d "True for a value that renders without delimiters of its own."
  (mt v
    ((asn-nil)     true)
    ((asn-bool _)  true)
    ((asn-unit)    true)
    ((asn-int _)   true)
    ((asn-float _) true)
    ((asn-str _)   true)
    ((asn-kw _)    true)
    ((asn-sym _)   true)
    (_             false)))

(df w-atom [(v AsnValue)] -> String
  :d "The text a scalar renders to: its source lexeme, unchanged."
  (mt v
    ((asn-nil)       "_")
    ((asn-bool b)    (if b "true" "false"))
    ((asn-unit)      "()")
    ((asn-int lex)   lex)
    ((asn-float lex) lex)
    ((asn-str lex)   lex)
    ((asn-kw k)      k)
    ((asn-sym s)     s)
    (_               "")))

(df w-open [(v AsnValue)] -> String
  :d "The opening delimiter a compound value renders with."
  (mt v
    ((asn-vec _)     "[")
    ((asn-map _)     "{")
    (_               "(")))

(df w-close [(v AsnValue)] -> String
  :d "The closing delimiter a compound value renders with."
  (mt v
    ((asn-vec _)     "]")
    ((asn-map _)     "}")
    (_               ")")))

(df w-fields [(fs (List AsnField))] -> (List WItem)
  :d "A field list flattened to alternating key and value work items."
  (fold (fn [(acc (List WItem)) (f AsnField)] -> (List WItem)
          (list-append acc (list (w-text (.-key f)) (w-val (.-val f)))))
        (list) fs))

(df w-entries [(es (List AsnEntry))] -> (List WItem)
  :d "A map's entries flattened. The parenthesised form is rebuilt as it was
      written, because which spelling the source used is part of the document."
  (fold (fn [(acc (List WItem)) (e AsnEntry)] -> (List WItem)
          (list-append acc
            (if (.-paren e)
              (list (w-val (asn-pair (.-key e) (.-val e))))
              (list (w-val (.-key e)) (w-val (.-val e))))))
        (list) es))

(df w-vals [(vs (List AsnValue))] -> (List WItem)
  :d "A value list as work items."
  (map (fn [(v AsnValue)] -> WItem (w-val v)) vs))

(df w-children [(v AsnValue)] -> (List WItem)
  :d "The work items a compound value's inside renders from, before separators."
  (mt v
    ((asn-vec items)    (w-vals items))
    ((asn-map es)       (w-entries es))
    ((asn-rec fs)       (w-fields fs))
    ((asn-ctor n fs)    (list-cons (w-text n) (w-fields fs)))
    ((asn-rows n rows)  (list-cons (w-text n) (w-vals rows)))
    ((asn-table cs rs)  (list (w-val (asn-vec cs)) (w-val (asn-vec rs))))
    ((asn-case n args)  (list-cons (w-text n) (w-vals args)))
    ((asn-pair k val)   (list (w-val k) (w-val val)))
    (_                  (list))))

(df w-separated [(items (List WItem))] -> (List WItem)
  :d "One space between neighbours, and none against either delimiter."
  (mt (list-head items)
    ((some h)
     (list-cons h
                (list-reverse
                  (fold (fn [(acc (List WItem)) (x WItem)] -> (List WItem)
                          (list-cons x (list-cons (w-text " ") acc)))
                        (list)
                        (w-tail items)))))
    ((none) (list))))

(df w-wrap [(v AsnValue)] -> (List WItem)
  :d "One compound value pushed onto the work list, outermost piece first."
  (list-cons (w-text (w-open v))
             (list-append (w-separated (w-children v))
                          (list (w-text (w-close v))))))

(df w-tick [(st WState) (tick Int64)] -> WState
  :d "One work-list step: emit a piece, or expand one value in place."
  (mt (list-head (.-work st))
    ((some it)
     (let [(rest (w-tail (.-work st)))]
       (mt it
         ((w-text t) (WState :work rest :out (list-cons t (.-out st))))
         ((w-val v)
          (if (w-atom? v)
            (WState :work rest :out (list-cons (w-atom v) (.-out st)))
            (WState :work (list-append (w-wrap v) rest) :out (.-out st)))))))
    ((none) st)))

(df w-run [(st WState) (budget Int64)] -> WState
  :d "Run work-list steps in doubling batches until the work list drains, for the
      reason `read-run` gives."
  (let [(limit budget)
        (next (fold w-tick st (range 0 limit)))]
    (cond
      ((list-empty? (.-work next)) next)
      (:else (w-run next (+ budget budget))))))

(df asn-write [(v AsnValue)] -> String
  :d "The canonical text of a value: one space between siblings, none against a
      delimiter, no comments, no line breaks, every scalar as its source lexeme.
      For canonical text t, `(asn-write (asn-read t))` is t byte for byte."
  (string-join (list-reverse (.-out (w-run (WState :work (list (w-val v)) :out (list)) 64)))
               ""))
