(module asl-tools/remote/form
  :x [Node Parsed sym txt seq parseForm formGet formText formStrings formInt quoteText quoteAll safeToken? safeUnit? safePath? splitTokens]
  :i [])

enum Node
  (sym name: String)
  (txt text: String)
  (seq items: (List Node))

(schema Parsed
  (:f node Node)
  (:f rest (List String)))

; (:m :ref REMOTE-FORM :do "requests and config are flat ASN forms of atoms, strings and lists; this reader is that subset only, so a request cannot smuggle structure the dispatcher did not expect")
; (:m :ref PERF-PARSEFORM-LONGLINE :do "the reader walks the bytes of the line by index and cuts each atom and string with one stringSliceUtf8, so a 1 MB data line is parsed in one pass without building a character list or a string per character; the delimiters are ASCII, so a multi-byte character is never split")
(schema ParsedAt
  (:f node Node)
  (:f at Int64))

fn blankB? c: Int64 -> Bool
  (or (= c 32) (or (= c 10) (or (= c 9) (= c 13))))

fn delimB? c: Int64 -> Bool
  (or (blankB? c) (or (= c 40) (or (= c 41) (= c 34))))

fn skipBlankAt b: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (blankB? (bytesGet b i))) (skipBlankAt b (+ i 1) n) i)

fn scanAtom b: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (not (delimB? (bytesGet b i)))) (scanAtom b (+ i 1) n) i)

fn scanPlain b: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (and (!= (bytesGet b i) 34) (!= (bytesGet b i) 92))) (scanPlain b (+ i 1) n) i)

fn sliceB s: String i: Int64 j: Int64 -> String
  (optionOr (stringSliceUtf8 s i j) "")

fn takeTextAt s: String b: Bytes i: Int64 n: Int64 acc: (List String) -> (Result (Pair String Int64) String)
  (let [(j (scanPlain b i n))
        (acc1 (cons (sliceB s i j) acc))]
    (cond
      ((>= j n) (err "unterminated string"))
      ((= (bytesGet b j) 34) (ok (pair (stringJoin (listReverse acc1) "") (+ j 1))))
      ((>= (+ j 1) n) (err "dangling escape"))
      (else
        (let [(e (bytesGet b (+ j 1)))]
          (cond
            ((= e 110) (takeTextAt s b (+ j 2) n (cons "\n" acc1)))
            ((< e 128) (takeTextAt s b (+ j 2) n (cons (sliceB s (+ j 1) (+ j 2)) acc1)))
            (else (takeTextAt s b (+ j 1) n acc1)))))))

fn parseItemsAt s: String b: Bytes i: Int64 n: Int64 acc: (List Node) -> (Result ParsedAt String)
  (let [(i1 (skipBlankAt b i n))]
    (cond
      ((>= i1 n) (err "unbalanced ("))
      ((= (bytesGet b i1) 41) (ok (ParsedAt :node (seq (listReverse acc)) :at (+ i1 1))))
      (else
        (match (parseNodeAt s b i1 n)
          ((err e) (err e))
          ((ok p) (parseItemsAt s b p.at n (cons p.node acc)))))))

fn parseNodeAt s: String b: Bytes i: Int64 n: Int64 -> (Result ParsedAt String)
  (let [(i1 (skipBlankAt b i n))]
    (if (>= i1 n)
      (err "empty form")
      (let [(c (bytesGet b i1))]
        (cond
          ((= c 40) (parseItemsAt s b (+ i1 1) n (list)))
          ((= c 41) (err "unexpected )"))
          ((= c 34) (match (takeTextAt s b (+ i1 1) n (list))
                      ((err e) (err e))
                      ((ok t) (ok (ParsedAt :node (txt (pairFirst t)) :at (pairSecond t))))))
          (else (let [(j (scanAtom b i1 n))]
                  (ok (ParsedAt :node (sym (sliceB s i1 j)) :at j))))))))

fn parseForm text: String -> (Result Node String)
  (let [(b (stringToBytes text))
        (n (bytesLength b))]
    (match (parseNodeAt text b 0 n)
      ((err e) (err e))
      ((ok p) (if (< (skipBlankAt b p.at n) n) (err "trailing text after form") (ok p.node)))))

fn findKey items: (List Node) key: String -> (Option Node)
  (match (listHead items)
    ((none) (none))
    ((some n)
      (let [(rest (optionOr (listTail items) (list)))]
        (match n
          ((sym name) (if (= name key) (listHead rest) (findKey rest key)))
          ((txt _) (findKey rest key))
          ((seq _) (findKey rest key))))))

fn formGet node: Node key: String -> (Option Node)
  (match node
    ((seq items) (findKey items key))
    ((sym _) (none))
    ((txt _) (none)))

fn formText node: Node -> (Option String)
  (match node
    ((sym name) (some name))
    ((txt text) (some text))
    ((seq _) (none)))

fn formStrings node: Node -> (List String)
  (match node
    ((seq items) (fold (fn [(acc (List String)) (n Node)] -> (List String)
                         (match (formText n) ((some t) (listAppend acc (list t))) ((none) acc)))
                       (list) items))
    ((sym name) (list name))
    ((txt text) (list text)))

fn formInt node: Node -> (Option Int64)
  (match (formText node) ((some t) (stringToInt64 t)) ((none) (none)))

fn quoteText s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r") "\"")

fn quoteAll xs: (List String) -> String
  (str "(" (stringJoin (map quoteText xs) " ") ")")

; (:m :ref REMOTE-TOKEN :do "the allowlist of characters a dispatcher token may hold: no shell metacharacter, quote, space or $ ever passes, so nothing a token carries can mean more than itself")
fn safeChar? c: String -> Bool
  (let [(n (bytesGet (stringToBytes c) 0))]
    (and (= (stringLength c) 1)
         (or (and (>= n 48) (<= n 57))
             (or (and (>= n 65) (<= n 90))
                 (or (and (>= n 97) (<= n 122))
                     (or (= n 45) (or (= n 95) (or (= n 46) (or (= n 47) (or (= n 61) (or (= n 44) (= n 58))))))))))))

fn safeToken? s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? safeChar? (stringChars s)))

fn safeUnit? s: String -> Bool
  (and (not (stringEmpty? s))
       (listAll? (fn [(c String)] -> Bool
                   (let [(n (bytesGet (stringToBytes c) 0))]
                     (or (and (>= n 48) (<= n 57)) (or (and (>= n 65) (<= n 90)) (or (and (>= n 97) (<= n 122)) (= n 45))))))
                 (stringChars s)))

fn safePath? s: String -> Bool
  (and (safeToken? s)
       (and (not (stringStartsWith? s "/"))
            (listAll? (fn [(seg String)] -> Bool (and (not (stringEmpty? seg)) (and (not (stringStartsWith? seg ".")) (not (stringStartsWith? seg "-")))))
                      (stringSplit s "/"))))

fn splitTokens line: String -> (List String)
  (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit (stringTrim line) " "))
