(module asl-syntax/registry
  :x [languageOf!
      languageByExtension
      languageByShebang
      languageByMarkdownInfo
      languageByHtmlType
      languageByMime
      languageByMagic]
  :i [])

fn pathBasename p: String -> String
  (let [(parts (stringSplit p "/"))]
    (optionOr (listLast parts) p))

fn pathExtension path: String -> String
  (let [(base (pathBasename path))]
    (let [(rest (if (stringStartsWith? base ".")
                  (optionOr (stringSlice base 1 (stringLength base)) "")
                  base))
          (parts (stringSplit rest "."))]
      (if (<= (listLength parts) 1)
        ""
        (str "." (stringLower (optionOr (listLast parts) ""))))))

fn languageByExtension rawExt: String -> String
  (let [(ext (stringLower (if (stringStartsWith? rawExt ".")
                            rawExt
                            (str "." rawExt))))]
    (cond
      ((= ext ".asl") "asl")
      ((= ext ".asn") "asn")
      ((or (= ext ".py") (= ext ".pyw")) "python")
      ((or (= ext ".sh") (= ext ".bash") (= ext ".zsh")) "shell")
      ((or (= ext ".js") (= ext ".mjs") (= ext ".cjs") (= ext ".jsx")) "javascript")
      ((or (= ext ".ts") (= ext ".tsx") (= ext ".mts") (= ext ".cts")) "typescript")
      ((= ext ".rs") "rust")
      ((= ext ".go") "go")
      ((or (= ext ".c") (= ext ".h")) "c")
      ((or (= ext ".cpp") (= ext ".cc") (= ext ".hpp")) "cpp")
      ((= ext ".java") "java")
      ((= ext ".kt") "kotlin")
      ((= ext ".swift") "swift")
      ((= ext ".rb") "ruby")
      ((or (= ext ".m") (= ext ".mm")) "objc")
      ((= ext ".zig") "zig")
      ((= ext ".lua") "lua")
      ((= ext ".pl") "perl")
      ((= ext ".php") "php")
      ((= ext ".ps1") "powershell")
      ((= ext ".md") "markdown")
      ((= ext ".json") "json")
      ((or (= ext ".yaml") (= ext ".yml")) "yaml")
      ((= ext ".toml") "toml")
      (else "")))

fn languageByMagic bs: Bytes -> String
  (let [(len (bytesLength bs))]
    (cond
      ((< len 4) "")
      ((and (= (bytesGet bs 0) 207)
            (= (bytesGet bs 1) 250)
            (= (bytesGet bs 2) 237)
            (= (bytesGet bs 3) 254))
       "machO")
      ((and (= (bytesGet bs 0) 254)
            (= (bytesGet bs 1) 237)
            (= (bytesGet bs 2) 250)
            (= (bytesGet bs 3) 207))
       "machO")
      ((and (= (bytesGet bs 0) 202)
            (= (bytesGet bs 1) 254)
            (= (bytesGet bs 2) 186)
            (= (bytesGet bs 3) 190))
       "machOUniversal")
      ((and (= (bytesGet bs 0) 127)
            (= (bytesGet bs 1) 69)
            (= (bytesGet bs 2) 76)
            (= (bytesGet bs 3) 70))
       "elf")
      ((and (= (bytesGet bs 0) 0)
            (= (bytesGet bs 1) 97)
            (= (bytesGet bs 2) 115)
            (= (bytesGet bs 3) 109))
       "wasm")
      (else "")))

fn isDigitOrSep? c: String -> Bool
  (or (= c "0") (= c "1") (= c "2") (= c "3") (= c "4")
      (= c "5") (= c "6") (= c "7") (= c "8") (= c "9")
      (= c ".") (= c "-") (= c "_") (= c "v"))

fn matchInterpreterPrefix name: String prefix: String -> Bool
  (let [(pLen (stringLength prefix))
        (nLen (stringLength name))]
    (if (< nLen pLen)
      false
      (if (= name prefix)
        true
        (if (stringStartsWith? name prefix)
          (isDigitOrSep? (optionOr (stringSlice name pLen (+ pLen 1)) ""))
          false))))

fn sanitizeAlphaNum s: String -> String
  (let [(chars (stringChars s))]
    (stringJoin
      (listReverse
        (fold (fn [(acc (List String)) (c String)] -> (List String)
                (let [(code (charCode c))]
                  (if (or (and (>= code 48) (<= code 57))
                          (and (>= code 65) (<= code 90))
                          (and (>= code 97) (<= code 122)))
                    (cons c acc)
                    acc)))
              (list)
              chars))
      ""))

fn splitWhitespace s: String -> (List String)
  (let [(lines (stringSplit s " "))]
    (listReverse
      (fold (fn [(acc (List String)) (part String)] -> (List String)
              (let [(sub (stringSplit part "\t"))]
                (fold (fn [(inner (List String)) (tok String)] -> (List String)
                        (let [(trimmed (stringTrim tok))]
                          (if (stringEmpty? trimmed)
                            inner
                            (cons trimmed inner))))
                      acc
                      sub)))
            (list)
            lines)))

fn classifyInterpreter name: String -> String
  (cond
    ((matchInterpreterPrefix name "python") "python")
    ((matchInterpreterPrefix name "node") "javascript")
    ((matchInterpreterPrefix name "perl") "perl")
    ((matchInterpreterPrefix name "ruby") "ruby")
    ((or (matchInterpreterPrefix name "bash")
         (matchInterpreterPrefix name "sh")
         (matchInterpreterPrefix name "zsh")
         (matchInterpreterPrefix name "dash")
         (matchInterpreterPrefix name "ksh")) "shell")
    (else
     (let [(clean (sanitizeAlphaNum name))]
       (if (stringEmpty? clean)
         "shebang.empty"
         (str "shebang." clean)))))

fn languageByShebang line: String -> String
  (if (not (stringStartsWith? line "#!"))
    ""
    (let [(rest (stringTrim (optionOr (stringSlice line 2 (stringLength line)) "")))]
      (let [(words (splitWhitespace rest))]
        (mt (listHead words)
          ((none) "")
          ((some firstWord)
           (let [(interp (if (= (pathBasename firstWord) "env")
                           (let [(filtered (fold (fn [(acc (List String)) (w String)] -> (List String)
                                                   (if (stringStartsWith? w "-")
                                                     acc
                                                     (cons w acc)))
                                                 (list)
                                                 (optionOr (listTail words) (list))))]
                             (optionOr (listLast filtered) ""))
                           firstWord))]
             (if (stringEmpty? interp)
               ""
               (classifyInterpreter (stringLower (pathBasename interp))))))))))

fn firstMarkdownTag s: String -> String
  (let [(trimmed (stringTrim s))]
    (let [(sp (optionOr (stringIndexOf trimmed " ") -1))
          (tab (optionOr (stringIndexOf trimmed "\t") -1))
          (brace (optionOr (stringIndexOf trimmed "{") -1))
          (len (stringLength trimmed))]
      (let [(cut1 (if (and (>= sp 0) (< sp len)) sp len))
            (cut2 (if (and (>= tab 0) (< tab cut1)) tab cut1))
            (cut3 (if (and (>= brace 0) (< brace cut2)) brace cut2))]
        (stringLower (optionOr (stringSlice trimmed 0 cut3) "")))))

fn languageByMarkdownInfo info: String -> String
  (let [(tag (firstMarkdownTag info))]
    (cond
      ((or (= tag "python") (= tag "py") (= tag "py3")) "python")
      ((or (= tag "javascript") (= tag "js") (= tag "jsx")) "javascript")
      ((or (= tag "typescript") (= tag "ts") (= tag "tsx")) "typescript")
      ((= tag "asl") "asl")
      ((= tag "asn") "asn")
      ((or (= tag "shell") (= tag "sh") (= tag "bash") (= tag "zsh")) "shell")
      ((= tag "c") "c")
      ((or (= tag "cpp") (= tag "c++")) "cpp")
      ((or (= tag "rust") (= tag "rs")) "rust")
      ((or (= tag "go") (= tag "golang")) "go")
      ((= tag "json") "json")
      ((or (= tag "yaml") (= tag "yml")) "yaml")
      ((= tag "toml") "toml")
      ((= tag "html") "html")
      ((= tag "css") "css")
      ((= tag "sql") "sql")
      ((= tag "swift") "swift")
      ((= tag "ruby") "ruby")
      ((= tag "zig") "zig")
      ((= tag "java") "java")
      ((or (= tag "kotlin") (= tag "kt")) "kotlin")
      ((= tag "lua") "lua")
      ((or (= tag "perl") (= tag "pl")) "perl")
      ((= tag "php") "php")
      ((or (= tag "powershell") (= tag "ps1")) "powershell")
      ((= tag "wasm") "wasm")
      ((or (= tag "markdown") (= tag "md")) "markdown")
      (else "")))

fn languageByHtmlType htmlType: String -> String
  (let [(t (stringLower (stringTrim htmlType)))]
    (cond
      ((or (= t "text/javascript") (= t "application/javascript") (= t "javascript") (= t "module"))
       "javascript")
      ((or (= t "text/typescript") (= t "application/typescript") (= t "typescript"))
       "typescript")
      ((or (= t "text/css") (= t "css"))
       "css")
      ((or (= t "application/json") (= t "text/json") (= t "json") (= t "importmap"))
       "json")
      ((or (= t "text/html") (= t "html"))
       "html")
      (else "")))

fn languageByMime mime: String -> String
  (let [(m (stringLower (stringTrim mime)))]
    (cond
      ((or (= m "application/javascript") (= m "text/javascript")) "javascript")
      ((or (= m "application/typescript") (= m "text/typescript")) "typescript")
      ((or (= m "text/x-python") (= m "application/x-python-code") (= m "text/python")) "python")
      ((or (= m "text/x-shellscript") (= m "application/x-sh") (= m "text/x-sh")) "shell")
      ((= m "text/x-c") "c")
      ((or (= m "text/x-c++") (= m "text/x-cpp")) "cpp")
      ((= m "text/x-rust") "rust")
      ((= m "text/x-go") "go")
      ((or (= m "application/json") (= m "text/json")) "json")
      ((or (= m "text/yaml") (= m "application/yaml") (= m "text/x-yaml") (= m "application/x-yaml")) "yaml")
      ((or (= m "application/toml") (= m "text/toml")) "toml")
      ((or (= m "text/markdown") (= m "text/x-markdown")) "markdown")
      ((= m "text/html") "html")
      ((= m "text/css") "css")
      ((or (= m "application/xml") (= m "text/xml")) "xml")
      ((= m "application/wasm") "wasm")
      ((= m "text/x-asl") "asl")
      ((= m "text/x-asn") "asn")
      ((= m "text/x-java") "java")
      ((= m "text/x-sql") "sql")
      (else "")))

fn languageOf! path: String -> String
  (let [(ext (pathExtension path))]
    (if (!= ext "")
      (let [(lang (languageByExtension ext))]
        (if (!= lang "")
          lang
          "text"))
      (mt (fileReadBytes path)
        ((ok bs)
         (let [(magic (languageByMagic bs))]
           (if (!= magic "")
             magic
             (let [(len (bytesLength bs))]
               (if (and (>= len 2)
                        (= (bytesGet bs 0) 35)
                        (= (bytesGet bs 1) 33))
                 (mt (fileReadString path)
                   ((ok content)
                    (let [(firstLine (optionOr (listHead (stringLines content)) ""))]
                      (let [(shLang (languageByShebang firstLine))]
                        (if (!= shLang "")
                          shLang
                          "text"))))
                   ((err e) "text"))
                 "text")))))
        ((err e) "text"))))
