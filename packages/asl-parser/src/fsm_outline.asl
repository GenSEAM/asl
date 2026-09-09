(module asl-parser/fsm-outline
  :d "Polyglot streaming finite state machine outline scanner in pure AgentScript"
  :x [OutlineItem
      scan-outline
      detect-lang
      format-outline]
  :i [])

(dfs OutlineItem
  (:f kind String "Classification of symbol")
  (:f name String "Symbol identifier")
  (:f line Int64 "1-indexed line number in source"))

(dfs ScanState
  (:f in-comment Bool "Inside multiline block comment")
  (:f in-quote String "Delimiter if inside multiline string")
  (:f brace-depth Int64 "Curly brace nesting depth")
  (:f paren-depth Int64 "Parenthesis nesting depth"))

(dfs FsmLoop
  (:f state ScanState "Current FSM state")
  (:f line-num Int64 "1-indexed line number")
  (:f acc (List OutlineItem) "Accumulator of parsed items"))

(df detect-lang [(path String)] -> String
  :d "Detects language family from file path extension"
  (cond
    ((or (string-ends-with? path ".asl") (string-ends-with? path ".asn")) "asl")
    ((string-ends-with? path ".py") "py")
    ((or (string-ends-with? path ".ts") (string-ends-with? path ".tsx")
         (string-ends-with? path ".js") (string-ends-with? path ".jsx")
         (string-ends-with? path ".mjs") (string-ends-with? path ".cjs")) "ts")
    ((string-ends-with? path ".go") "go")
    ((string-ends-with? path ".rs") "rs")
    (true "asl")))

(df char-at [(s String) (idx Int64)] -> String
  :d "Safe single character retrieval at index"
  (mt (string-slice s idx (+ idx 1))
    ((some c) c)
    ((none) "")))

(df skip-spaces [(s String) (idx Int64) (len Int64)] -> Int64
  :d "Advances index past whitespace"
  (if (>= idx len)
    len
    (let [(ch (char-at s idx))]
      (if (or (= ch " ") (= ch "\t"))
        (skip-spaces s (+ idx 1) len)
        idx))))

(df is-ident-char [(ch String) (is-asl Bool)] -> Bool
  :d "Checks if character is a valid identifier constituent"
  (if (or (and (>= ch "a") (<= ch "z"))
          (and (>= ch "A") (<= ch "Z"))
          (and (>= ch "0") (<= ch "9"))
          (= ch "_"))
    true
    (if is-asl
      (or (= ch "-") (or (= ch "/") (= ch ":")))
      false)))

(df find-ident-end [(s String) (idx Int64) (len Int64) (is-asl Bool)] -> Int64
  :d "Finds terminal index of current identifier"
  (if (>= idx len)
    len
    (let [(ch (char-at s idx))]
      (if (is-ident-char ch is-asl)
        (find-ident-end s (+ idx 1) len is-asl)
        idx))))

(df extract-ident [(s String) (start Int64) (len Int64) (is-asl Bool)] -> String
  :d "Extracts identifier substring starting at start"
  (let [(pos (skip-spaces s start len))]
    (if (>= pos len)
      ""
      (let [(end (find-ident-end s pos len is-asl))]
        (if (> end pos)
          (mt (string-slice s pos end)
            ((some id) id)
            ((none) ""))
          "")))))

(df find-closing-paren [(s String) (idx Int64) (len Int64)] -> Int64
  :d "Finds matching closing parenthesis index"
  (if (>= idx len)
    len
    (let [(ch (char-at s idx))]
      (if (= ch ")")
        (+ idx 1)
        (find-closing-paren s (+ idx 1) len)))))

(df skip-string-lit [(s String) (idx Int64) (len Int64) (delim String)] -> Int64
  :d "Advances index past single-line string literal with backslash escapes"
  (if (>= idx len)
    len
    (let [(c (char-at s idx))]
      (if (= c "\\")
        (skip-string-lit s (+ idx 2) len delim)
        (if (= c delim)
          (+ idx 1)
          (skip-string-lit s (+ idx 1) len delim))))))

(df extract-asl-item [(line String) (line-num Int64)] -> (Option OutlineItem)
  :d "Extracts top-level form declaration from ASL or ASN line"
  (let [(trimmed (string-trim line))
        (len (string-length trimmed))]
    (if (string-starts-with? trimmed "(")
      (let [(p1 (skip-spaces trimmed 1 len))
            (head (extract-ident trimmed p1 len true))]
        (cond
          ((or (= head "module") (or (= head "df") (or (= head "dfs") (or (= head "dfe")
           (or (= head "defun") (or (= head "struct") (= head "enum")))))))
           (let [(p2 (skip-spaces trimmed (+ p1 (string-length head)) len))
                 (name (extract-ident trimmed p2 len true))]
             (if (> (string-length name) 0)
               (some (OutlineItem :kind head :name name :line line-num))
               (none))))
          ((= head ":grammar")
           (if (string-contains? trimmed ":package")
             (let [(pkg-pos (+ (option-or (string-index-of trimmed ":package") 0) 8))
                   (name (extract-ident trimmed pkg-pos len true))]
               (if (> (string-length name) 0)
                 (some (OutlineItem :kind "grammar" :name name :line line-num))
                 (none)))
             (none)))
          (true (none))))
      (none))))

(df extract-py-item [(line String) (line-num Int64)] -> (Option OutlineItem)
  :d "Extracts def or class declaration from Python line"
  (let [(trimmed (string-trim line))
        (len (string-length trimmed))]
    (cond
      ((string-starts-with? trimmed "def ")
       (let [(name (extract-ident trimmed 4 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "fn" :name name :line line-num))
           (none))))
      ((string-starts-with? trimmed "async def ")
       (let [(name (extract-ident trimmed 10 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "fn" :name name :line line-num))
           (none))))
      ((string-starts-with? trimmed "class ")
       (let [(name (extract-ident trimmed 6 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "class" :name name :line line-num))
           (none))))
      (true (none)))))

(df strip-ts-modifiers [(s String)] -> String
  :d "Strips export, default, async, declare keywords from TypeScript line"
  (cond
    ((string-starts-with? s "export default ") (strip-ts-modifiers (string-trim (option-or (string-slice s 15 (string-length s)) ""))))
    ((string-starts-with? s "export ") (strip-ts-modifiers (string-trim (option-or (string-slice s 7 (string-length s)) ""))))
    ((string-starts-with? s "async ") (strip-ts-modifiers (string-trim (option-or (string-slice s 6 (string-length s)) ""))))
    ((string-starts-with? s "declare ") (strip-ts-modifiers (string-trim (option-or (string-slice s 8 (string-length s)) ""))))
    (true s)))

(df extract-ts-item [(line String) (line-num Int64)] -> (Option OutlineItem)
  :d "Extracts function, class, interface, type, or enum from TypeScript line"
  (let [(trimmed (string-trim line))
        (stripped (strip-ts-modifiers trimmed))
        (len (string-length stripped))]
    (cond
      ((string-starts-with? stripped "function* ")
       (let [(name (extract-ident stripped 10 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "fn" :name name :line line-num))
           (none))))
      ((string-starts-with? stripped "function ")
       (let [(name (extract-ident stripped 9 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "fn" :name name :line line-num))
           (none))))
      ((string-starts-with? stripped "class ")
       (let [(name (extract-ident stripped 6 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "class" :name name :line line-num))
           (none))))
      ((string-starts-with? stripped "interface ")
       (let [(name (extract-ident stripped 10 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "interface" :name name :line line-num))
           (none))))
      ((string-starts-with? stripped "type ")
       (let [(name (extract-ident stripped 5 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "type" :name name :line line-num))
           (none))))
      ((string-starts-with? stripped "enum ")
       (let [(name (extract-ident stripped 5 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "enum" :name name :line line-num))
           (none))))
      (true (none)))))

(df extract-go-item [(line String) (line-num Int64)] -> (Option OutlineItem)
  :d "Extracts package, func, or type declaration from Go line"
  (let [(trimmed (string-trim line))
        (len (string-length trimmed))]
    (cond
      ((string-starts-with? trimmed "package ")
       (let [(name (extract-ident trimmed 8 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "module" :name name :line line-num))
           (none))))
      ((string-starts-with? trimmed "func ")
       (let [(pos (skip-spaces trimmed 5 len))
             (first-c (char-at trimmed pos))]
         (if (= first-c "(")
           (let [(after-recv (find-closing-paren trimmed (+ pos 1) len))
                 (name (extract-ident trimmed after-recv len false))]
             (if (> (string-length name) 0)
               (some (OutlineItem :kind "fn" :name name :line line-num))
               (none)))
           (let [(name (extract-ident trimmed pos len false))]
             (if (> (string-length name) 0)
               (some (OutlineItem :kind "fn" :name name :line line-num))
               (none))))))
      ((string-starts-with? trimmed "type ")
       (let [(name (extract-ident trimmed 5 len false))]
         (if (> (string-length name) 0)
           (let [(kind (if (string-contains? trimmed "struct")
                         "struct"
                         (if (string-contains? trimmed "interface")
                           "interface"
                           "type")))]
             (some (OutlineItem :kind kind :name name :line line-num)))
           (none))))
      (true (none)))))

(df strip-rs-modifiers [(s String)] -> String
  :d "Strips pub, async, unsafe, extern modifiers from Rust line"
  (cond
    ((string-starts-with? s "pub(crate) ") (strip-rs-modifiers (string-trim (option-or (string-slice s 11 (string-length s)) ""))))
    ((string-starts-with? s "pub(super) ") (strip-rs-modifiers (string-trim (option-or (string-slice s 11 (string-length s)) ""))))
    ((string-starts-with? s "pub ") (strip-rs-modifiers (string-trim (option-or (string-slice s 4 (string-length s)) ""))))
    ((string-starts-with? s "async ") (strip-rs-modifiers (string-trim (option-or (string-slice s 6 (string-length s)) ""))))
    ((string-starts-with? s "unsafe ") (strip-rs-modifiers (string-trim (option-or (string-slice s 7 (string-length s)) ""))))
    ((string-starts-with? s "extern \"C\" ") (strip-rs-modifiers (string-trim (option-or (string-slice s 11 (string-length s)) ""))))
    ((string-starts-with? s "extern ") (strip-rs-modifiers (string-trim (option-or (string-slice s 7 (string-length s)) ""))))
    (true s)))

(df extract-rs-item [(line String) (line-num Int64)] -> (Option OutlineItem)
  :d "Extracts fn, struct, enum, trait, type, or mod from Rust line"
  (let [(trimmed (string-trim line))
        (stripped (strip-rs-modifiers trimmed))
        (len (string-length stripped))]
    (cond
      ((string-starts-with? stripped "fn ")
       (let [(name (extract-ident stripped 3 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "fn" :name name :line line-num))
           (none))))
      ((string-starts-with? stripped "struct ")
       (let [(name (extract-ident stripped 7 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "struct" :name name :line line-num))
           (none))))
      ((string-starts-with? stripped "enum ")
       (let [(name (extract-ident stripped 5 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "enum" :name name :line line-num))
           (none))))
      ((string-starts-with? stripped "trait ")
       (let [(name (extract-ident stripped 6 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "interface" :name name :line line-num))
           (none))))
      ((string-starts-with? stripped "type ")
       (let [(name (extract-ident stripped 5 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "type" :name name :line line-num))
           (none))))
      ((string-starts-with? stripped "mod ")
       (let [(name (extract-ident stripped 4 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "module" :name name :line line-num))
           (none))))
      (true (none)))))

(df extract-line-item [(line String) (line-num Int64) (st ScanState) (lang String)] -> (Option OutlineItem)
  :d "Extracts outline declaration item if state allows top-level form"
  (if (or (.-in-comment st) (> (string-length (.-in-quote st)) 0))
    (none)
    (cond
      ((= lang "asl")
       (if (= (.-paren-depth st) 0)
         (extract-asl-item line line-num)
         (none)))
      ((= lang "py")
       (extract-py-item line line-num))
      ((= lang "ts")
       (if (= (.-brace-depth st) 0)
         (extract-ts-item line line-num)
         (none)))
      ((= lang "go")
       (if (= (.-brace-depth st) 0)
         (extract-go-item line line-num)
         (none)))
      ((= lang "rs")
       (if (= (.-brace-depth st) 0)
         (extract-rs-item line line-num)
         (none)))
      (true
       (if (= (.-paren-depth st) 0)
         (extract-asl-item line line-num)
         (none))))))

(df step-chars [(line String) (idx Int64) (len Int64) (st ScanState) (lang String)] -> ScanState
  :d "Performs streaming character transitions across a single line"
  (if (>= idx len)
    st
    (let [(c1 (char-at line idx))
          (c2 (char-at line (+ idx 1)))
          (c3 (char-at line (+ idx 2)))]
      (if (.-in-comment st)
        (if (and (= c1 "*") (= c2 "/"))
          (step-chars line (+ idx 2) len (ScanState :in-comment false :in-quote (.-in-quote st) :brace-depth (.-brace-depth st) :paren-depth (.-paren-depth st)) lang)
          (step-chars line (+ idx 1) len st lang))
        (let [(q (.-in-quote st))]
          (if (> (string-length q) 0)
            (cond
              ((= q "\"\"\"")
               (if (and (= c1 "\"") (and (= c2 "\"") (= c3 "\"")))
                 (step-chars line (+ idx 3) len (ScanState :in-comment false :in-quote "" :brace-depth (.-brace-depth st) :paren-depth (.-paren-depth st)) lang)
                 (step-chars line (+ idx 1) len st lang)))
              ((= q "'''")
               (if (and (= c1 "'") (and (= c2 "'") (= c3 "'")))
                 (step-chars line (+ idx 3) len (ScanState :in-comment false :in-quote "" :brace-depth (.-brace-depth st) :paren-depth (.-paren-depth st)) lang)
                 (step-chars line (+ idx 1) len st lang)))
              ((= q "`")
               (if (= c1 "`")
                 (step-chars line (+ idx 1) len (ScanState :in-comment false :in-quote "" :brace-depth (.-brace-depth st) :paren-depth (.-paren-depth st)) lang)
                 (step-chars line (+ idx 1) len st lang)))
              (true
               (step-chars line (+ idx 1) len st lang)))
            (cond
              ((and (= lang "asl") (= c1 ";"))
               st)
              ((and (= lang "py") (= c1 "#"))
               st)
              ((and (not (= lang "asl")) (and (not (= lang "py")) (and (= c1 "/") (= c2 "/"))))
               st)
              ((and (not (= lang "asl")) (and (not (= lang "py")) (and (= c1 "/") (= c2 "*"))))
               (step-chars line (+ idx 2) len (ScanState :in-comment true :in-quote "" :brace-depth (.-brace-depth st) :paren-depth (.-paren-depth st)) lang))
              ((and (= lang "py") (and (= c1 "\"") (and (= c2 "\"") (= c3 "\""))))
               (step-chars line (+ idx 3) len (ScanState :in-comment false :in-quote "\"\"\"" :brace-depth (.-brace-depth st) :paren-depth (.-paren-depth st)) lang))
              ((and (= lang "py") (and (= c1 "'") (and (= c2 "'") (= c3 "'"))))
               (step-chars line (+ idx 3) len (ScanState :in-comment false :in-quote "'''" :brace-depth (.-brace-depth st) :paren-depth (.-paren-depth st)) lang))
              ((and (or (= lang "ts") (= lang "go")) (= c1 "`"))
               (step-chars line (+ idx 1) len (ScanState :in-comment false :in-quote "`" :brace-depth (.-brace-depth st) :paren-depth (.-paren-depth st)) lang))
              ((= c1 "\"")
               (let [(next-idx (skip-string-lit line (+ idx 1) len "\""))]
                 (step-chars line next-idx len st lang)))
              ((and (not (= lang "asl")) (= c1 "'"))
               (let [(next-idx (skip-string-lit line (+ idx 1) len "'"))]
                 (step-chars line next-idx len st lang)))
              ((= c1 "{")
               (step-chars line (+ idx 1) len (ScanState :in-comment false :in-quote "" :brace-depth (+ (.-brace-depth st) 1) :paren-depth (.-paren-depth st)) lang))
              ((= c1 "}")
               (let [(nb (if (> (.-brace-depth st) 0) (- (.-brace-depth st) 1) 0))]
                 (step-chars line (+ idx 1) len (ScanState :in-comment false :in-quote "" :brace-depth nb :paren-depth (.-paren-depth st)) lang)))
              ((= c1 "(")
               (step-chars line (+ idx 1) len (ScanState :in-comment false :in-quote "" :brace-depth (.-brace-depth st) :paren-depth (+ (.-paren-depth st) 1)) lang))
              ((= c1 ")")
               (let [(np (if (> (.-paren-depth st) 0) (- (.-paren-depth st) 1) 0))]
                 (step-chars line (+ idx 1) len (ScanState :in-comment false :in-quote "" :brace-depth (.-brace-depth st) :paren-depth np) lang)))
              (true
               (step-chars line (+ idx 1) len st lang)))))))))

(df scan-outline [(src String) (lang String)] -> (List OutlineItem)
  :d "Extracts top-level declarations across polyglot source code using streaming FSM"
  (let [(lines (string-split src "\n"))
        (init-st (ScanState :in-comment false :in-quote "" :brace-depth 0 :paren-depth 0))
        (init-loop (FsmLoop :state init-st :line-num 1 :acc (list)))
        (final-loop (fold (fn [(loop FsmLoop) (line String)] -> FsmLoop
                            (let [(st (.-state loop))
                                  (ln (.-line-num loop))
                                  (acc (.-acc loop))
                                  (item-opt (extract-line-item line ln st lang))
                                  (new-acc (mt item-opt
                                             ((some it) (cons it acc))
                                             ((none) acc)))
                                  (next-st (step-chars line 0 (string-length line) st lang))]
                              (FsmLoop :state next-st :line-num (+ ln 1) :acc new-acc)))
                          init-loop
                          lines))]
    (list-reverse (.-acc final-loop))))

(df format-outline [(items (List OutlineItem))] -> String
  :d "Formats outline items into canonical S-expression string"
  (str "(:outline [\n"
       (string-join
         (map (fn [(it OutlineItem)] -> String
                (str "  (:item :kind \"" (.-kind it) "\" :name \"" (.-name it) "\" :line " (string-from-int64 (.-line it)) ")"))
              items)
         "\n")
       "\n])"))
