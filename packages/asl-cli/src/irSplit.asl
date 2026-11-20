(module asl-cli/irSplit
  :x [Body Split split splitWith inlineLimit declOf externOf]
  :i [])

(schema Body
  (:f head String)
  (:f text String)
  (:f size Int64))

(schema Split
  (:f shared (List String))
  (:f owned (List String))
  (:f bodies (List Body)))

fn paramType p: String -> String
  (let [(words (stringSplit p " "))]
    (if (< (listLength words) 2) p (stringJoin (listTake words (- (listLength words) 1)) " ")))

fn declOf head: String -> (Option String)
  (let [(rest (stringReplace (stringReplace (optionOr (stringSlice head 7 (stringLength head)) "") "internal " "") "weak " ""))]
    (match (stringIndexOf rest "(")
      ((none) (none))
      ((some open) (match (stringIndexOf rest ")")
        ((none) (none))
        ((some close) (let [(params (optionOr (stringSlice rest (+ open 1) close) ""))]
                        (some (str "declare " (optionOr (stringSlice rest 0 open) "") "("
                                   (if (stringEmpty? params) "" (stringJoin (map paramType (stringSplit params ", ")) ", ")) ")"))))))))

fn externOf line: String -> (Option String)
  (match (stringIndexOf line " global ")
    ((none) (none))
    ((some at) (let [(name (optionOr (stringSlice line 0 (optionOr (stringIndexOf line " = ") 0)) ""))
                     (init (optionOr (stringSlice line (+ at 8) (stringLength line)) ""))
                     (typed (optionOr (listHead (stringSplit init ", align ")) init))
                     (words (stringSplit typed " "))
                     (ty (stringJoin (listTake words (max 0 (- (listLength words) 1))) " "))]
                 (cond
                   ((or (stringEmpty? name) (stringEmpty? ty)) (none))
                   ((stringStartsWith? (definition line) "weak global ") (some (str name " = external global " ty)))
                   (else (some (str name " = external hidden global " ty)))))))

fn definition line: String -> String
  (match (stringIndexOf line " = ") ((none) "") ((some i) (optionOr (stringSlice line (+ i 3) (stringLength line)) "")))

fn owned? line: String -> Bool
  (and (stringStartsWith? line "@") (or (stringStartsWith? (definition line) "internal global ") (stringStartsWith? (definition line) "weak global ")))

fn bodyOf piece: String -> (Result (Pair Body String) String)
  (let [(whole (str piece "\n"))]
    (match (stringIndexOf whole "\n}\n")
      ((none) (err "a define has no closing brace line"))
      ((some end) (let [(text (str "define " (optionOr (stringSlice whole 0 (+ end 3)) "")))
                        (head (optionOr (stringSlice text 0 (optionOr (stringIndexOf text "\n") (stringLength text))) ""))]
                    (ok (pair (Body :head head :text text :size (stringLength text)) (optionOr (stringSlice whole (+ end 3) (stringLength whole)) "")))))))

fn bodiesOf pieces: (List String) bodies: (List Body) tails: (List String) -> (Result (Pair (List Body) (List String)) String)
  (match (listHead pieces)
    ((none) (ok (pair (listReverse bodies) tails)))
    ((some p) (match (bodyOf p)
      ((err e) (err e))
      ((ok u) (bodiesOf (optionOr (listTail pieces) (list)) (cons (pairFirst u) bodies) (cons (pairSecond u) tails))))))

fn parse text: String -> (Result Split String)
  (let [(pieces (stringSplit text "\ndefine "))]
    (match (bodiesOf (optionOr (listTail pieces) (list)) (list) (list))
      ((err e) (err e))
      ((ok found) (let [(lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l)))
                                       (stringLines (stringJoin (cons (str (optionOr (listHead pieces) "") "\n") (pairSecond found)) "\n"))))]
                    (ok (Split :shared (filter (fn [(l String)] -> Bool (not (owned? l))) lines)
                               :owned (filter owned? lines)
                               :bodies (pairFirst found)))))))

fn assign bodies: (List Body) n: Int64 -> (List Int64)
  (let [(total (fold (fn [(acc Int64) (u Body)] -> Int64 (+ acc u.size)) 0 bodies))
        (per (max 1 (/ (+ total (- n 1)) n)))]
    (listReverse (pairSecond (fold (fn [(acc (Pair Int64 (List Int64))) (u Body)] -> (Pair Int64 (List Int64))
                                     (let [(before (pairFirst acc))]
                                       (pair (+ before u.size) (cons (min (- n 1) (/ before per)) (pairSecond acc)))))
                                   (pair 0 (list)) bodies))))

fn ownText u: Body -> String
  (if (stringStartsWith? u.head "define internal ") (str "define hidden " (optionOr (stringSlice u.text 16 (stringLength u.text)) "")) u.text)

; (:m :ref BUILDPAR :do "a body at most limit bytes long (2000: on asl1.asl split 8 ways, fixedNt +4.0% with no copies, +3.3% at 800, +0.79% at 1500, +0.16% at 2000, 2026-10-25) is also given to every other part as available_externally, so a small helper (a closure code wrapper, a prelude accessor) still inlines across a part boundary as it does in the whole module; only internal bodies and bodies with default linkage qualify, never main, a weak or a linkonce body")
fn inlineLimit -> Int64
  2000

fn linkageWord? w: String -> Bool
  (listContains? (list "weak" "weak_odr" "linkonce" "linkonce_odr" "private" "hidden" "protected" "available_externally" "external" "extern_weak" "common" "appending" "dllexport") w)

fn plainDefine? head: String -> Bool
  (not (linkageWord? (optionOr (listHead (stringSplit (optionOr (stringSlice head 7 (stringLength head)) "") " ")) "")))

fn copyText u: Body limit: Int64 -> (Option String)
  (cond
    ((or (> u.size limit) (stringContains? u.head " @main(")) (none))
    ((stringStartsWith? u.head "define internal ") (some (str "define available_externally " (optionOr (stringSlice u.text 16 (stringLength u.text)) ""))))
    ((plainDefine? u.head) (some (str "define available_externally " (optionOr (stringSlice u.text 7 (stringLength u.text)) ""))))
    (else (none)))

fn otherText u: Body limit: Int64 -> (Result String String)
  (cond
    ((stringStartsWith? u.head "define linkonce_odr ") (ok u.text))
    ((some? (copyText u limit)) (ok (optionOr (copyText u limit) "")))
    ((and (stringStartsWith? u.head "define internal ") (stringEndsWith? u.head " alwaysinline {"))
      (ok (str "define available_externally " (optionOr (stringSlice u.text 16 (stringLength u.text)) ""))))
    (else (match (declOf u.head)
            ((none) (err (str "cannot declare " u.head)))
            ((some d) (ok (if (stringStartsWith? u.head "define internal ") (str "declare hidden " (optionOr (stringSlice d 8 (stringLength d)) "")) d))))))

fn ownedText k: Int64 line: String -> (Result String String)
  (if (= k 0)
    (let [(rhs (definition line))]
      (ok (if (stringStartsWith? rhs "internal global ")
            (str (optionOr (stringSlice line 0 (- (stringLength line) (stringLength rhs))) "") "hidden global " (optionOr (stringSlice rhs 16 (stringLength rhs)) ""))
            line)))
    (match (externOf line) ((none) (err (str "cannot declare " line))) ((some d) (ok d))))

fn collect xs: (List (Result String String)) acc: (List String) -> (Result (List String) String)
  (match (listHead xs)
    ((none) (ok (listReverse acc)))
    ((some r) (match r ((err e) (err e)) ((ok s) (collect (optionOr (listTail xs) (list)) (cons s acc))))))

fn part s: Split owners: (List Int64) k: Int64 limit: Int64 -> (Result String String)
  (match (collect (map (fn [(l String)] -> (Result String String) (ownedText k l)) s.owned) (list))
    ((err e) (err e))
    ((ok globals) (match (collect (map (fn [(p (Pair Int64 Body))] -> (Result String String)
                                       (if (= (pairFirst p) k) (ok (ownText (pairSecond p))) (otherText (pairSecond p) limit)))
                                     (zip owners s.bodies)) (list))
      ((err e) (err e))
      ((ok bodies) (ok (str (stringJoin s.shared "\n") "\n" (stringJoin globals "\n") "\n" (stringJoin bodies "\n") "\n"))))))

fn split text: String n: Int64 -> (Result (List String) String)
  (splitWith text n (inlineLimit))

fn splitWith text: String n: Int64 limit: Int64 -> (Result (List String) String)
  (match (parse text)
    ((err e) (err e))
    ((ok s) (let [(parts (max 1 (min n (listLength s.bodies))))
                  (owners (assign s.bodies parts))]
              (collect (map (fn [(k Int64)] -> (Result String String) (part s owners k limit)) (range 0 parts)) (list)))))
