; The lexer, written in AgentScript. This is the self-hosting probe recorded in
; ROADMAP §7: about 15% of the compiler's volume and close to all of its risk,
; because it is where the language turns out to be missing something while
; rewriting is still cheap.
;
; No regular expressions and no integer string indexing: the source is taken
; apart with `string-chars` and consumed by structural recursion over the
; resulting list, which is the shape `04-longest-run.as` already uses.

(module compiler/lex
  :doc "Tokenise AgentScript source into a list of tokens."
  :export [lex render-kind token-text])

(defenum Kind
  (:case open-paren   [] "(")
  (:case close-paren  [] ")")
  (:case open-square  [] "[")
  (:case close-square [] "]")
  (:case open-brace   [] "{")
  (:case close-brace  [] "}")
  (:case arrow        [] "The -> of a signature")
  (:case wildcard     [] "_")
  (:case ident        [] "A kebab-case identifier")
  (:case qualified    [] "alias/member")
  (:case type-name    [] "A PascalCase type name")
  (:case keyword      [] "A :keyword")
  (:case field-ref    [] "A .-field accessor")
  (:case operator     [] "An arithmetic or comparison operator")
  (:case int-lit      [] "An integer literal")
  (:case float-lit    [] "A float literal")
  (:case string-lit   [] "A string literal, quotes included")
  (:case bool-lit     [] "true or false")
  (:case comment      [] "A ; comment, newline excluded"))

(defschema Token
  (:field kind Kind   "What class of token this is")
  (:field text String "The source text of the token, verbatim"))

; ---------- character classes ----------
;
; `string-contains?` over a literal alphabet stands in for a character class.
; The language has no character type, so a "character" here is a one-character
; string, which is what `string-chars` produces.

(defun digit? [(c String)] -> Bool
  :doc "True for 0-9."
  (string-contains? "0123456789" c))

(defun lower? [(c String)] -> Bool
  :doc "True for a-z."
  (string-contains? "abcdefghijklmnopqrstuvwxyz" c))

(defun upper? [(c String)] -> Bool
  :doc "True for A-Z."
  (string-contains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" c))

(defun space? [(c String)] -> Bool
  :doc "True for whitespace, which is insignificant except as a separator."
  (or (= c " ") (or (= c "\n") (or (= c "\t") (= c "\r")))))

(defun ident-char? [(c String)] -> Bool
  :doc "True for a character that may continue an identifier."
  (or (lower? c) (or (digit? c) (or (= c "-") (or (= c "?") (= c "!"))))))

(defun type-char? [(c String)] -> Bool
  :doc "True for a character that may continue a PascalCase type name."
  (or (lower? c) (or (upper? c) (digit? c))))

; ---------- span helpers ----------
;
; These would be one `take-while` taking a predicate. They are four, because a
; function-typed parameter cannot be declared: the type grammar admits
; `TypeName` and `(TypeName type+)` and has no function form, so `map`, `filter`
; and `fold` can take a function only because they are builtins. The duplication
; below is the cost of that gap, and it is the first thing this probe found.

(defun take-ident [(cs (List String)) (acc String)] -> (Pair String (List String))
  :doc "The longest identifier-character prefix, and the rest."
  (match cs
    ((list)     (pair acc cs))
    ((cons h t) (if (ident-char? h)
                  (take-ident t (str acc h))
                  (pair acc cs)))))

(defun take-type [(cs (List String)) (acc String)] -> (Pair String (List String))
  :doc "The longest type-name-character prefix, and the rest."
  (match cs
    ((list)     (pair acc cs))
    ((cons h t) (if (type-char? h)
                  (take-type t (str acc h))
                  (pair acc cs)))))

(defun take-digits [(cs (List String)) (acc String)] -> (Pair String (List String))
  :doc "The longest run of digits, and the rest."
  (match cs
    ((list)     (pair acc cs))
    ((cons h t) (if (digit? h)
                  (take-digits t (str acc h))
                  (pair acc cs)))))

(defun take-until [(cs (List String)) (stop String) (acc String)]
    -> (Pair String (List String))
  :doc "Everything up to but excluding a stop character, and the rest."
  (match cs
    ((list)     (pair acc cs))
    ((cons h t) (if (= h stop)
                  (pair acc cs)
                  (take-until t stop (str acc h))))))

(defun take-string [(cs (List String)) (acc String)] -> (Result (Pair String (List String)) String)
  :doc "A string literal's body up to the closing quote, honouring backslash escapes."
  (match cs
    ((list) (err "unterminated string literal"))
    ((cons h t)
     (cond
       ((= h "\"") (ok (pair (str acc h) t)))
       ((= h "\\")
        (match t
          ((list)      (err "unterminated escape in string literal"))
          ((cons e r)  (take-string r (str acc (str h e))))))
       (:else (take-string t (str acc h)))))))

; ---------- one token ----------

(defun one-char [(k Kind) (c String) (rest (List String))] -> (Pair Token (List String))
  :doc "A token that is exactly one character."
  (pair (Token :kind k :text c) rest))

(defun number-token [(cs (List String)) (lead String)] -> (Pair Token (List String))
  :doc "An integer, or a float when a dot with digits follows."
  (let [(whole (take-digits cs lead))
        (digits (.-first whole))
        (rest (.-second whole))]
    (match rest
      ((list) (pair (Token :kind (int-lit) :text digits) rest))
      ((cons h t)
       (if (= h ".")
         (let [(frac (take-digits t (str digits ".")))]
           (if (= (.-first frac) (str digits "."))
             (pair (Token :kind (int-lit) :text digits) rest)
             (pair (Token :kind (float-lit) :text (.-first frac)) (.-second frac))))
         (pair (Token :kind (int-lit) :text digits) rest))))))

(defun word-token [(cs (List String)) (lead String)] -> (Pair Token (List String))
  :doc "An identifier, a qualified name, or a boolean literal."
  (let [(taken (take-ident cs lead))
        (word (.-first taken))
        (rest (.-second taken))]
    (cond
      ((or (= word "true") (= word "false"))
       (pair (Token :kind (bool-lit) :text word) rest))
      (:else
       (match rest
         ((list) (pair (Token :kind (ident) :text word) rest))
         ((cons h t)
          (if (= h "/")
            (let [(after (take-ident t ""))]
              (pair (Token :kind (qualified)
                           :text (str word (str "/" (.-first after))))
                    (.-second after)))
            (pair (Token :kind (ident) :text word) rest))))))))

(defun next-token [(cs (List String))] -> (Result (Option (Pair Token (List String))) String)
  :doc "The next token and what follows it, or none once the input is spent."
  (match cs
    ((list) (ok (none)))
    ((cons h t)
     (cond
       ((space? h)   (next-token t))
       ((= h "(")    (ok (some (one-char (open-paren) h t))))
       ((= h ")")    (ok (some (one-char (close-paren) h t))))
       ((= h "[")    (ok (some (one-char (open-square) h t))))
       ((= h "]")    (ok (some (one-char (close-square) h t))))
       ((= h "{")    (ok (some (one-char (open-brace) h t))))
       ((= h "}")    (ok (some (one-char (close-brace) h t))))
       ((= h "_")    (ok (some (one-char (wildcard) h t))))
       ((= h ";")
        (let [(taken (take-until t "\n" ";"))]
          (ok (some (pair (Token :kind (comment) :text (.-first taken))
                          (.-second taken))))))
       ((= h "\"")
        (match (take-string t "\"")
          ((err e) (err e))
          ((ok got) (ok (some (pair (Token :kind (string-lit) :text (.-first got))
                                    (.-second got)))))))
       ((= h ":")
        (let [(taken (take-ident t ":"))]
          (ok (some (pair (Token :kind (keyword) :text (.-first taken))
                          (.-second taken))))))
       ((= h ".")
        (match t
          ((list) (err "a lone dot is not a token"))
          ((cons d r)
           (if (= d "-")
             (let [(taken (take-ident r ".-"))]
               (ok (some (pair (Token :kind (field-ref) :text (.-first taken))
                               (.-second taken)))))
             (err "expected .-field after a dot")))))
       ((digit? h)   (ok (some (number-token t h))))
       ((= h "-")
        (match t
          ((list) (ok (some (one-char (operator) h t))))
          ((cons d r)
           (cond
             ((= d ">") (ok (some (pair (Token :kind (arrow) :text "->") r))))
             ((digit? d) (ok (some (number-token r (str h d)))))
             (:else (ok (some (one-char (operator) h t))))))))
       ((string-contains? "+*/=<>!" h)
        (match t
          ((list) (ok (some (one-char (operator) h t))))
          ((cons d r)
           (if (= d "=")
             (ok (some (pair (Token :kind (operator) :text (str h d)) r)))
             (ok (some (one-char (operator) h t)))))))
       ((lower? h)   (ok (some (word-token t h))))
       ((upper? h)
        (let [(taken (take-type t h))]
          (ok (some (pair (Token :kind (type-name) :text (.-first taken))
                          (.-second taken))))))
       (:else (err (str "unexpected character " h)))))))

(defun lex-from [(cs (List String)) (acc (List Token))] -> (Result (List Token) String)
  :doc "Tokenise the rest of the input onto a REVERSED accumulator.

  `list-cons` prepends in constant time; `list-append` copies the accumulator on
  every token, which made this quadratic and took the Rust build past ten
  minutes on twenty thousand tokens. The list is reversed once at the end."
  (match (next-token cs)
    ((err e) (err e))
    ((ok maybe)
     (match maybe
       ((none) (ok acc))
       ((some step)
        (lex-from (.-second step) (list-cons (.-first step) acc)))))))

(defun lex [(src String)] -> (Result (List Token) String)
  :doc "Tokenise a whole source file."
  (match (lex-from (string-chars src) (list))
    ((err e)     (err e))
    ((ok backward) (ok (list-reverse backward)))))

(defun render-kind [(k Kind)] -> String
  :doc "A token kind's name, for tests and error messages."
  (match k
    ((open-paren)   "open-paren")
    ((close-paren)  "close-paren")
    ((open-square)  "open-square")
    ((close-square) "close-square")
    ((open-brace)   "open-brace")
    ((close-brace)  "close-brace")
    ((arrow)        "arrow")
    ((wildcard)     "wildcard")
    ((ident)        "ident")
    ((qualified)    "qualified")
    ((type-name)    "type-name")
    ((keyword)      "keyword")
    ((field-ref)    "field-ref")
    ((operator)     "operator")
    ((int-lit)      "int")
    ((float-lit)    "float")
    ((string-lit)   "string")
    ((bool-lit)     "bool")
    ((comment)      "comment")))

(defun token-text [(t Token)] -> String
  :doc "The verbatim source text of a token."
  (.-text t))
