(module asl-parser/fsmOutline
  :d "Polyglot streaming finite state machine outline scanner in pure AgentScript"
  :x [OutlineItem
      scanOutline
      detectLang
      formatOutline]
  :i [(lexer :a lx)])

(dfs OutlineItem
  (:f kind String "Classification of symbol")
  (:f name String "Symbol identifier")
  (:f line Int64 "1-indexed line number in source"))

(dfs ScanState
  (:f inComment Bool "Inside multiline block comment")
  (:f inQuote String "Delimiter if inside multiline string")
  (:f braceDepth Int64 "Curly brace nesting depth")
  (:f parenDepth Int64 "Parenthesis nesting depth"))

(dfs FsmLoop
  (:f state ScanState "Current FSM state")
  (:f lineNum Int64 "1-indexed line number")
  (:f acc (List OutlineItem) "Accumulator of parsed items"))

(df detectLang [(path String)] -> String
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

(df skipSpaces [(s String) (idx Int64) (len Int64)] -> Int64
  :d "Advances index past whitespace"
  (if (>= idx len)
    len
    (let [(ch (lx/charAt s idx))]
      (if (or (= ch " ") (= ch "\t"))
        (skipSpaces s (+ idx 1) len)
        idx))))

(df isIdentChar [(ch String) (isAsl Bool)] -> Bool
  :d "Checks if character is a valid identifier constituent"
  (if (or (and (>= ch "a") (<= ch "z"))
          (and (>= ch "A") (<= ch "Z"))
          (and (>= ch "0") (<= ch "9"))
          (= ch "_"))
    true
    (if isAsl
      (or (= ch "-") (or (= ch "/") (= ch ":")))
      false)))

(df findIdentEnd [(s String) (idx Int64) (len Int64) (isAsl Bool)] -> Int64
  :d "Finds terminal index of current identifier"
  (if (>= idx len)
    len
    (let [(ch (lx/charAt s idx))]
      (if (isIdentChar ch isAsl)
        (findIdentEnd s (+ idx 1) len isAsl)
        idx))))

(df extractIdent [(s String) (start Int64) (len Int64) (isAsl Bool)] -> String
  :d "Extracts identifier substring starting at start"
  (let [(pos (skipSpaces s start len))]
    (if (>= pos len)
      ""
      (let [(end (findIdentEnd s pos len isAsl))]
        (if (> end pos)
          (mt (string-slice s pos end)
            ((some id) id)
            ((none) ""))
          "")))))

(df findClosingParen [(s String) (idx Int64) (len Int64)] -> Int64
  :d "Finds matching closing parenthesis index"
  (if (>= idx len)
    len
    (let [(ch (lx/charAt s idx))]
      (if (= ch ")")
        (+ idx 1)
        (findClosingParen s (+ idx 1) len)))))

(df skipStringLit [(s String) (idx Int64) (len Int64) (delim String)] -> Int64
  :d "Advances index past single-line string literal with backslash escapes"
  (if (>= idx len)
    len
    (let [(c (lx/charAt s idx))]
      (if (= c "\\")
        (skipStringLit s (+ idx 2) len delim)
        (if (= c delim)
          (+ idx 1)
          (skipStringLit s (+ idx 1) len delim))))))

(df extractAslItem [(line String) (lineNum Int64)] -> (Option OutlineItem)
  :d "Extracts top-level form declaration from ASL or ASN line"
  (let [(trimmed (string-trim line))
        (len (string-length trimmed))]
    (if (string-starts-with? trimmed "(")
      (let [(p1 (skipSpaces trimmed 1 len))
            (head (extractIdent trimmed p1 len true))]
        (cond
          ((or (= head "module") (or (= head "df") (or (= head "dfs") (or (= head "dfe")
           (or (= head "defun") (or (= head "struct") (= head "enum")))))))
           (let [(p2 (skipSpaces trimmed (+ p1 (string-length head)) len))
                 (name (extractIdent trimmed p2 len true))]
             (if (> (string-length name) 0)
               (some (OutlineItem :kind head :name name :line lineNum))
               (none))))
          ((= head ":grammar")
           (if (string-contains? trimmed ":package")
             (let [(pkgPos (+ (option-or (string-index-of trimmed ":package") 0) 8))
                   (name (extractIdent trimmed pkgPos len true))]
               (if (> (string-length name) 0)
                 (some (OutlineItem :kind "grammar" :name name :line lineNum))
                 (none)))
             (none)))
          (true (none))))
      (none))))

(df extractPyItem [(line String) (lineNum Int64)] -> (Option OutlineItem)
  :d "Extracts def or class declaration from Python line"
  (let [(trimmed (string-trim line))
        (len (string-length trimmed))]
    (cond
      ((string-starts-with? trimmed "def ")
       (let [(name (extractIdent trimmed 4 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "fn" :name name :line lineNum))
           (none))))
      ((string-starts-with? trimmed "async def ")
       (let [(name (extractIdent trimmed 10 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "fn" :name name :line lineNum))
           (none))))
      ((string-starts-with? trimmed "class ")
       (let [(name (extractIdent trimmed 6 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "class" :name name :line lineNum))
           (none))))
      (true (none)))))

(df stripTsModifiers [(s String)] -> String
  :d "Strips export, default, async, declare keywords from TypeScript line"
  (cond
    ((string-starts-with? s "export default ") (stripTsModifiers (string-trim (option-or (string-slice s 15 (string-length s)) ""))))
    ((string-starts-with? s "export ") (stripTsModifiers (string-trim (option-or (string-slice s 7 (string-length s)) ""))))
    ((string-starts-with? s "async ") (stripTsModifiers (string-trim (option-or (string-slice s 6 (string-length s)) ""))))
    ((string-starts-with? s "declare ") (stripTsModifiers (string-trim (option-or (string-slice s 8 (string-length s)) ""))))
    (true s)))

(df extractTsItem [(line String) (lineNum Int64)] -> (Option OutlineItem)
  :d "Extracts function, class, interface, type, or enum from TypeScript line"
  (let [(trimmed (string-trim line))
        (stripped (stripTsModifiers trimmed))
        (len (string-length stripped))]
    (cond
      ((string-starts-with? stripped "function* ")
       (let [(name (extractIdent stripped 10 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "fn" :name name :line lineNum))
           (none))))
      ((string-starts-with? stripped "function ")
       (let [(name (extractIdent stripped 9 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "fn" :name name :line lineNum))
           (none))))
      ((string-starts-with? stripped "class ")
       (let [(name (extractIdent stripped 6 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "class" :name name :line lineNum))
           (none))))
      ((string-starts-with? stripped "interface ")
       (let [(name (extractIdent stripped 10 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "interface" :name name :line lineNum))
           (none))))
      ((string-starts-with? stripped "type ")
       (let [(name (extractIdent stripped 5 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "type" :name name :line lineNum))
           (none))))
      ((string-starts-with? stripped "enum ")
       (let [(name (extractIdent stripped 5 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "enum" :name name :line lineNum))
           (none))))
      (true (none)))))

(df extractGoItem [(line String) (lineNum Int64)] -> (Option OutlineItem)
  :d "Extracts package, func, or type declaration from Go line"
  (let [(trimmed (string-trim line))
        (len (string-length trimmed))]
    (cond
      ((string-starts-with? trimmed "package ")
       (let [(name (extractIdent trimmed 8 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "module" :name name :line lineNum))
           (none))))
      ((string-starts-with? trimmed "func ")
       (let [(pos (skipSpaces trimmed 5 len))
             (firstC (lx/charAt trimmed pos))]
         (if (= firstC "(")
           (let [(afterRecv (findClosingParen trimmed (+ pos 1) len))
                 (name (extractIdent trimmed afterRecv len false))]
             (if (> (string-length name) 0)
               (some (OutlineItem :kind "fn" :name name :line lineNum))
               (none)))
           (let [(name (extractIdent trimmed pos len false))]
             (if (> (string-length name) 0)
               (some (OutlineItem :kind "fn" :name name :line lineNum))
               (none))))))
      ((string-starts-with? trimmed "type ")
       (let [(name (extractIdent trimmed 5 len false))]
         (if (> (string-length name) 0)
           (let [(kind (if (string-contains? trimmed "struct")
                         "struct"
                         (if (string-contains? trimmed "interface")
                           "interface"
                           "type")))]
             (some (OutlineItem :kind kind :name name :line lineNum)))
           (none))))
      (true (none)))))

(df stripRsModifiers [(s String)] -> String
  :d "Strips pub, async, unsafe, extern modifiers from Rust line"
  (cond
    ((string-starts-with? s "pub(crate) ") (stripRsModifiers (string-trim (option-or (string-slice s 11 (string-length s)) ""))))
    ((string-starts-with? s "pub(super) ") (stripRsModifiers (string-trim (option-or (string-slice s 11 (string-length s)) ""))))
    ((string-starts-with? s "pub ") (stripRsModifiers (string-trim (option-or (string-slice s 4 (string-length s)) ""))))
    ((string-starts-with? s "async ") (stripRsModifiers (string-trim (option-or (string-slice s 6 (string-length s)) ""))))
    ((string-starts-with? s "unsafe ") (stripRsModifiers (string-trim (option-or (string-slice s 7 (string-length s)) ""))))
    ((string-starts-with? s "extern \"C\" ") (stripRsModifiers (string-trim (option-or (string-slice s 11 (string-length s)) ""))))
    ((string-starts-with? s "extern ") (stripRsModifiers (string-trim (option-or (string-slice s 7 (string-length s)) ""))))
    (true s)))

(df extractRsItem [(line String) (lineNum Int64)] -> (Option OutlineItem)
  :d "Extracts fn, struct, enum, trait, type, or mod from Rust line"
  (let [(trimmed (string-trim line))
        (stripped (stripRsModifiers trimmed))
        (len (string-length stripped))]
    (cond
      ((string-starts-with? stripped "fn ")
       (let [(name (extractIdent stripped 3 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "fn" :name name :line lineNum))
           (none))))
      ((string-starts-with? stripped "struct ")
       (let [(name (extractIdent stripped 7 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "struct" :name name :line lineNum))
           (none))))
      ((string-starts-with? stripped "enum ")
       (let [(name (extractIdent stripped 5 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "enum" :name name :line lineNum))
           (none))))
      ((string-starts-with? stripped "trait ")
       (let [(name (extractIdent stripped 6 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "interface" :name name :line lineNum))
           (none))))
      ((string-starts-with? stripped "type ")
       (let [(name (extractIdent stripped 5 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "type" :name name :line lineNum))
           (none))))
      ((string-starts-with? stripped "mod ")
       (let [(name (extractIdent stripped 4 len false))]
         (if (> (string-length name) 0)
           (some (OutlineItem :kind "module" :name name :line lineNum))
           (none))))
      (true (none)))))

(df extractLineItem [(line String) (lineNum Int64) (st ScanState) (lang String)] -> (Option OutlineItem)
  :d "Extracts outline declaration item if state allows top-level form"
  (if (or (.-inComment st) (> (string-length (.-inQuote st)) 0))
    (none)
    (cond
      ((= lang "asl")
       (if (= (.-parenDepth st) 0)
         (extractAslItem line lineNum)
         (none)))
      ((= lang "py")
       (extractPyItem line lineNum))
      ((= lang "ts")
       (if (= (.-braceDepth st) 0)
         (extractTsItem line lineNum)
         (none)))
      ((= lang "go")
       (if (= (.-braceDepth st) 0)
         (extractGoItem line lineNum)
         (none)))
      ((= lang "rs")
       (if (= (.-braceDepth st) 0)
         (extractRsItem line lineNum)
         (none)))
      (true
       (if (= (.-parenDepth st) 0)
         (extractAslItem line lineNum)
         (none))))))

(df stepChars [(line String) (idx Int64) (len Int64) (st ScanState) (lang String)] -> ScanState
  :d "Performs streaming character transitions across a single line"
  (if (>= idx len)
    st
    (let [(c1 (lx/charAt line idx))
          (c2 (lx/charAt line (+ idx 1)))
          (c3 (lx/charAt line (+ idx 2)))]
      (if (.-inComment st)
        (if (and (= c1 "*") (= c2 "/"))
          (stepChars line (+ idx 2) len (ScanState :inComment false :inQuote (.-inQuote st) :braceDepth (.-braceDepth st) :parenDepth (.-parenDepth st)) lang)
          (stepChars line (+ idx 1) len st lang))
        (let [(q (.-inQuote st))]
          (if (> (string-length q) 0)
            (cond
              ((= q "\"\"\"")
               (if (and (= c1 "\"") (and (= c2 "\"") (= c3 "\"")))
                 (stepChars line (+ idx 3) len (ScanState :inComment false :inQuote "" :braceDepth (.-braceDepth st) :parenDepth (.-parenDepth st)) lang)
                 (stepChars line (+ idx 1) len st lang)))
              ((= q "'''")
               (if (and (= c1 "'") (and (= c2 "'") (= c3 "'")))
                 (stepChars line (+ idx 3) len (ScanState :inComment false :inQuote "" :braceDepth (.-braceDepth st) :parenDepth (.-parenDepth st)) lang)
                 (stepChars line (+ idx 1) len st lang)))
              ((= q "`")
               (if (= c1 "`")
                 (stepChars line (+ idx 1) len (ScanState :inComment false :inQuote "" :braceDepth (.-braceDepth st) :parenDepth (.-parenDepth st)) lang)
                 (stepChars line (+ idx 1) len st lang)))
              (true
               (stepChars line (+ idx 1) len st lang)))
            (cond
              ((and (= lang "asl") (= c1 ";"))
               st)
              ((and (= lang "py") (= c1 "#"))
               st)
              ((and (not (= lang "asl")) (and (not (= lang "py")) (and (= c1 "/") (= c2 "/"))))
               st)
              ((and (not (= lang "asl")) (and (not (= lang "py")) (and (= c1 "/") (= c2 "*"))))
               (stepChars line (+ idx 2) len (ScanState :inComment true :inQuote "" :braceDepth (.-braceDepth st) :parenDepth (.-parenDepth st)) lang))
              ((and (= lang "py") (and (= c1 "\"") (and (= c2 "\"") (= c3 "\""))))
               (stepChars line (+ idx 3) len (ScanState :inComment false :inQuote "\"\"\"" :braceDepth (.-braceDepth st) :parenDepth (.-parenDepth st)) lang))
              ((and (= lang "py") (and (= c1 "'") (and (= c2 "'") (= c3 "'"))))
               (stepChars line (+ idx 3) len (ScanState :inComment false :inQuote "'''" :braceDepth (.-braceDepth st) :parenDepth (.-parenDepth st)) lang))
              ((and (or (= lang "ts") (= lang "go")) (= c1 "`"))
               (stepChars line (+ idx 1) len (ScanState :inComment false :inQuote "`" :braceDepth (.-braceDepth st) :parenDepth (.-parenDepth st)) lang))
              ((= c1 "\"")
               (let [(nextIdx (skipStringLit line (+ idx 1) len "\""))]
                 (stepChars line nextIdx len st lang)))
              ((and (not (= lang "asl")) (= c1 "'"))
               (let [(nextIdx (skipStringLit line (+ idx 1) len "'"))]
                 (stepChars line nextIdx len st lang)))
              ((= c1 "{")
               (stepChars line (+ idx 1) len (ScanState :inComment false :inQuote "" :braceDepth (+ (.-braceDepth st) 1) :parenDepth (.-parenDepth st)) lang))
              ((= c1 "}")
               (let [(nb (if (> (.-braceDepth st) 0) (- (.-braceDepth st) 1) 0))]
                 (stepChars line (+ idx 1) len (ScanState :inComment false :inQuote "" :braceDepth nb :parenDepth (.-parenDepth st)) lang)))
              ((= c1 "(")
               (stepChars line (+ idx 1) len (ScanState :inComment false :inQuote "" :braceDepth (.-braceDepth st) :parenDepth (+ (.-parenDepth st) 1)) lang))
              ((= c1 ")")
               (let [(np (if (> (.-parenDepth st) 0) (- (.-parenDepth st) 1) 0))]
                 (stepChars line (+ idx 1) len (ScanState :inComment false :inQuote "" :braceDepth (.-braceDepth st) :parenDepth np) lang)))
              (true
               (stepChars line (+ idx 1) len st lang)))))))))

(df scanOutline [(src String) (lang String)] -> (List OutlineItem)
  :d "Extracts top-level declarations across polyglot source code using streaming FSM"
  (let [(lines (string-split src "\n"))
        (initSt (ScanState :inComment false :inQuote "" :braceDepth 0 :parenDepth 0))
        (initLoop (FsmLoop :state initSt :lineNum 1 :acc (list)))
        (finalLoop (fold (fn [(loop FsmLoop) (line String)] -> FsmLoop
                            (let [(st (.-state loop))
                                  (ln (.-lineNum loop))
                                  (acc (.-acc loop))
                                  (itemOpt (extractLineItem line ln st lang))
                                  (newAcc (mt itemOpt
                                             ((some it) (cons it acc))
                                             ((none) acc)))
                                  (nextSt (stepChars line 0 (string-length line) st lang))]
                              (FsmLoop :state nextSt :lineNum (+ ln 1) :acc newAcc)))
                          initLoop
                          lines))]
    (list-reverse (.-acc finalLoop))))

(df formatOutline [(items (List OutlineItem))] -> String
  :d "Formats outline items into canonical S-expression string"
  (str "(:outline [\n"
       (string-join
         (map (fn [(it OutlineItem)] -> String
                (str "  (:item :kind \"" (.-kind it) "\" :name \"" (.-name it) "\" :line " (string-from-int64 (.-line it)) ")"))
              items)
         "\n")
       "\n])"))
