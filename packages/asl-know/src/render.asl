(module asl-know/render
  :x [Card q unquoteRow tokensOf brandWords indexPurpose camelId cardFile exampleText pitTags packageCard areaCards langCard indexText missingOf allCards!]
  :i [(asl-know/scan :a sc)])

; (:m :tags (know) :note "L0 index, L1 cards and L2 symbol rows as single-line ASN frames; token figures are bytes/4, labelled :tokensBy bytes36")

(schema Card (:f id String) (:f purpose String) (:f keys (List String)) (:f line String) (:f rows (List String)) (:f missing (List String)))

fn q s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\t" " ") "\"")

fn tokensOf s: String -> Int64
  (/ (+ (* (stringLength s) 5) 17) 18)

fn capWords s: String n: Int64 -> String
  (if (<= (stringLength s) n) s (str (optionOr (stringSliceUtf8 s 0 n) (optionOr (stringSlice s 0 n) "")) "..."))

fn lastSpaceBefore s: String i: Int64 -> Int64
  (cond
    ((<= i 0) 0)
    ((= (optionOr (stringSlice s i (+ i 1)) "") " ") i)
    (else (lastSpaceBefore s (- i 1))))

; (:m :ref KNOWCARDS-STALE :do "an index purpose cut at the last word boundary within n bytes, then ...; no mid-word cut; a first word longer than n falls back to the byte cut of capWords")
fn capAtWord s: String n: Int64 -> String
  (if (<= (stringLength s) n)
    s
    (let [(at (lastSpaceBefore s n))]
      (if (<= at 0) (capWords s n) (str (stringTrim (optionOr (stringSlice s 0 at) "")) "..."))))

; (:m :ref KNOWCARDS-STALE :do "index purpose length: 82 cards at the old 36-byte cut measured 2023 o200k tokens, over the 2000 budget; 24 bytes cut at a word boundary measures 1766 (28: 1824, 20: 1690), leaving 11.7% headroom")
fn indexPurposeBytes -> Int64
  24

; (:m :ref KNOW-INDEX-BRANDING :do "leading words that name the language or praise a package; the index drops them before the byte cut, so its 24 bytes show what the package does (21 of 82 lines were only these words, 2026-11-13)")
fn brandWords -> (List String)
  (list "100%" "Self-Hosted" "Self-Contained" "Pure" "AgentSlang" "ASL" "Aslany" "Native" "Standalone" "Sovereign" "Standard" "Universal" "Autonomous" "Unified")

fn dropBrand words: (List String) -> (List String)
  (match (listHead words)
    ((some w) (if (listContains? (brandWords) w) (dropBrand (optionOr (listTail words) (list))) words))
    ((none) words))

; (:m :ref KNOW-INDEX-BRANDING :do "the purpose an index line shows: the card purpose without its leading branding words, the whole purpose when nothing else is left, cut at a word within indexPurposeBytes")
fn indexPurpose purpose: String -> String
  (let [(rest (dropBrand (stringSplit purpose " ")))
        (shown (if (listEmpty? rest) purpose (stringJoin rest " ")))]
    (capAtWord shown (indexPurposeBytes)))

fn upperFirst w: String -> String
  (if (stringEmpty? w) w (str (stringUpper (optionOr (stringSlice w 0 1) "")) (optionOr (stringSlice w 1 (stringLength w)) "")))

fn camelId id: String -> String
  (let [(parts (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit (stringReplace id "/" "-") "-")))]
    (str (optionOr (listHead parts) "") (stringJoin (map upperFirst (optionOr (listTail parts) (list))) "")))

fn cardFile id: String -> String
  (str (stringReplace id "/" "-") ".asn")

fn exampleText src: String -> String
  (stringTrim (match (stringIndexOf src "\nfn ! selfTest")
                ((some i) (optionOr (stringSlice src 0 i) src))
                ((none) (match (stringIndexOf src "\nfn selfTest") ((some j) (optionOr (stringSlice src 0 j) src)) ((none) src)))))

fn pitTags d: sc/Decl -> (List String)
  (let [(ret (sc/returnType d.sig))]
    (filter (fn [(t String)] -> Bool (not (stringEmpty? t)))
      (list (if (stringStartsWith? ret "(Result") "result" "")
            (if (stringStartsWith? ret "(Option") "option" "")
            (if (sc/effectful? d) "effect" "")
            (if (= d.kind "ctor") "ctor" "")
            (if (and (= d.kind "type") (stringContains? d.sig "(:f ")) "record" ""))))

fn tagList tags: (List String) -> String
  (if (listEmpty? tags) "" (str " :pit (" (stringJoin tags " ") ")"))

fn sigOf d: sc/Decl -> String
  (if (= d.kind "ctor") (str d.sig " of " d.owner) d.sig)

fn symRow card: String m: sc/Module docs: (Map String String) name: String -> String
  (let [(doc (mapGetOr docs (str m.path "#" name) ""))]
    (match (mapGet m.decls name)
      ((none) (str "(:sym " (q name) " :mod " (q m.name) " :sig none" (if (stringEmpty? doc) "" (str " :doc " (q doc))) ")"))
      ((some d) (str "(:sym " (q name) " :mod " (q m.name) (if (= d.kind "fn") "" (str " :kind " d.kind)) " :sig " (q (sigOf d))
                     (if (stringEmpty? doc) "" (str " :doc " (q (capWords doc 240)))) (tagList (pitTags d)) ")"))))

fn missingIn card: String m: sc/Module docs: (Map String String) name: String -> (List String)
  (cond
    ((not (mapHas? m.decls name)) (list (str card "#" m.name "/" name " nodecl")))
    ((not (mapHas? docs (str m.path "#" name))) (list (str card "#" m.name "/" name " nodoc")))
    (else (list)))

fn fitSigs sigs: (List String) room: Int64 acc: (List String) -> (Pair (List String) (List String))
  (match (listHead sigs)
    ((none) (pair (listReverse acc) (list)))
    ((some s)
      (if (> (+ (stringLength s) 3) room)
        (pair (listReverse acc) sigs)
        (fitSigs (optionOr (listTail sigs) (list)) (- room (+ (stringLength s) 3)) (cons s acc)))))

fn fitNames names: (List String) room: Int64 acc: (List String) -> (List String)
  (match (listHead names)
    ((none) (listReverse acc))
    ((some s) (if (> (+ (stringLength s) 1) room) (listReverse acc) (fitNames (optionOr (listTail names) (list)) (- room (+ (stringLength s) 1)) (cons s acc)))))

fn shortSig d: sc/Decl -> String
  (if (= d.kind "type") (capWords d.sig 140) (sigOf d))

fn plumbing? name: String -> Bool
  (listContains? (list "main" "runTests" "selfTest") name)

fn exampleField ex: String -> String
  (if (stringEmpty? ex) " :example none" (str " :example " (q ex)))

fn cardLine id: String purpose: String head: String sigs: (List String) names: (List String) effects: (List String) fails: (List String) ex: String -> String
  (let [(fit (fitSigs sigs 600 (list)))
        (shown (pairFirst fit))
        (restNames (map sigName (pairSecond fit)))
        (more (fitNames restNames 160 (list)))
        (left (- (listLength restNames) (listLength more)))]
    (str "(:card " (q id) " :purpose " (q purpose) head
         " :sigs (" (stringJoin (map q shown) " ") ")"
         (if (listEmpty? more) "" (str " :more (" (stringJoin more " ") ")"))
         (if (> left 0) (str " :moreCount " left) "")
         (if (listEmpty? effects) "" (str " :effects (" (stringJoin (listTake effects 8) " ") ")"))
         (if (listEmpty? fails) "" (str " :fails (" (stringJoin (listTake fails 8) " ") ")"))
         (exampleField ex) ")"))

fn modDecl m: sc/Module name: String -> (List sc/Decl)
  (match (mapGet m.decls name) ((some d) (list d)) ((none) (list)))

fn packageCard p: sc/Package ex: String -> Card
  (let [(live (filter (fn [(m sc/Module)] -> Bool (not (listEmpty? (filter (fn [(n String)] -> Bool (not (plumbing? n))) m.exports)))) p.modules))
        (mods (listAppend (filter (fn [(m sc/Module)] -> Bool (= m.path p.entry)) live) (filter (fn [(m sc/Module)] -> Bool (not (= m.path p.entry))) live)))
        (pubs (fn [(m sc/Module)] -> (List String) (filter (fn [(n String)] -> Bool (not (plumbing? n))) m.exports)))
        (decls (listFlatMap (fn [(m sc/Module)] -> (List sc/Decl) (listFlatMap (fn [(n String)] -> (List sc/Decl) (modDecl m n)) (pubs m))) mods))
        (modsText (stringJoin (map (fn [(m sc/Module)] -> String
                                     (let [(doc (mapGetOr p.docs (str m.path "#") ""))]
                                       (str "(:m " (q m.name) (if (stringEmpty? doc) "" (str " :doc " (q (capWords doc 56)))) ")")))
                                   (listTake mods 5)) " "))
        (head (str " :import " (q (str "(" (optionOr (listHead (map (fn [(m sc/Module)] -> String m.name) mods)) p.name) " :a x)"))
                   (if (listEmpty? p.deps) "" (str " :deps (" (stringJoin p.deps " ") ")"))
                   " :modules (" modsText ")" (if (> (listLength mods) 5) (str " :moduleCount " (listLength mods)) "")))
        (sigs (uniq (map shortSig (filter (fn [(d sc/Decl)] -> Bool (not (= d.kind "ctor"))) decls)) (list)))
        (effects (uniq (map (fn [(d sc/Decl)] -> String d.name) (filter sc/effectful? decls)) (list)))
        (fails (uniq (map (fn [(d sc/Decl)] -> String d.name) (filter (fn [(d sc/Decl)] -> Bool (stringStartsWith? (sc/returnType d.sig) "(Result")) decls)) (list)))
        (rows (listFlatMap (fn [(m sc/Module)] -> (List String) (map (fn [(n String)] -> String (symRow p.name m p.docs n)) (pubs m))) mods))
        (missing (listFlatMap (fn [(m sc/Module)] -> (List String) (listFlatMap (fn [(n String)] -> (List String) (missingIn p.name m p.docs n)) (pubs m))) mods))
        (keys (listTake (map (fn [(d sc/Decl)] -> String d.name) (filter (fn [(d sc/Decl)] -> Bool (= d.kind "fn")) decls)) 3))
        (purpose (capWords p.description 220))]
    (Card :id p.name :purpose purpose :keys keys
          :line (cardLine p.name purpose head sigs (list) effects fails ex)
          :rows rows :missing missing))

fn areaId sec: String -> String
  (str "core/" (stringLower (optionOr (listHead (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace (stringReplace sec "," " ") "/" "") " "))) sec)))

fn builtinPit b: sc/Builtin -> (List String)
  (let [(ret (sc/returnType b.type))]
    (filter (fn [(t String)] -> Bool (not (stringEmpty? t)))
      (list (if (stringStartsWith? ret "(Result") "result" "")
            (if (stringStartsWith? ret "(Option") "option" "")
            (if (stringContains? b.type "...") "variadic" ""))))

fn builtinRow id: String b: sc/Builtin -> String
  (str "(:sym " (q b.name) " :sig " (q (str b.name " : " b.type))
       (if (stringEmpty? b.doc) "" (str " :doc " (q (capWords b.doc 240)))) (tagList (builtinPit b)) ")")

fn sections bs: (List sc/Builtin) acc: (List String) -> (List String)
  (match (listHead bs)
    ((none) (listReverse acc))
    ((some b) (sections (optionOr (listTail bs) (list)) (if (or (stringEmpty? b.sec) (listContains? acc b.sec)) acc (cons b.sec acc)))))

fn areaCard sec: String bs: (List sc/Builtin) exOf: (fn [String] -> String) -> Card
  (let [(id (areaId sec))
        (mine (filter (fn [(b sc/Builtin)] -> Bool (= b.sec sec)) bs))
        (sigs (map (fn [(b sc/Builtin)] -> String (str b.name " : " b.type)) mine))
        (fails (map (fn [(b sc/Builtin)] -> String b.name) (filter (fn [(b sc/Builtin)] -> Bool (stringStartsWith? (sc/returnType b.type) "(Result")) mine)))
        (purpose (str sec " builtins, no import"))]
    (Card :id id :purpose purpose :keys (listTake (map (fn [(b sc/Builtin)] -> String b.name) (filter (fn [(b sc/Builtin)] -> Bool (not (stringStartsWith? b.type "()"))) mine)) 3)
          :line (cardLine id purpose "" sigs (list) (list) fails (exOf id))
          :rows (map (fn [(b sc/Builtin)] -> String (builtinRow id b)) mine)
          :missing (map (fn [(b sc/Builtin)] -> String (str id "#" b.name " nodoc")) (filter (fn [(b sc/Builtin)] -> Bool (stringEmpty? b.doc)) mine))))

fn areaCards bs: (List sc/Builtin) exOf: (fn [String] -> String) -> (List Card)
  (map (fn [(s String)] -> Card (areaCard s bs exOf)) (sections bs (list)))

fn quotedStrings s: String -> (List String)
  (let [(b (stringToBytes s)) (n (bytesLength b))]
    (quotedFrom s b n 0 (list)))

fn quotedFrom s: String b: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (match (stringIndexOf (optionOr (stringSlice s i n) "") "\"")
    ((none) (listReverse acc))
    ((some k)
      (let [(start (+ i (+ k 1))) (e (sc/quoteEnd b n start))]
        (if (< e 0) (listReverse acc) (quotedFrom s b n (+ e 1) (cons (sc/unescape (optionOr (stringSlice s start e) "")) acc))))))

fn between s: String a: String z: String -> String
  (match (stringIndexOf s a)
    ((none) "")
    ((some i)
      (let [(rest (optionOr (stringSlice s (+ i (stringLength a)) (stringLength s)) ""))]
        (match (stringIndexOf rest z) ((some j) (optionOr (stringSlice rest 0 j) rest)) ((none) rest)))))

fn langCard spec: String ex: String -> Card
  (let [(rules (quotedStrings (between spec ":rules (" ":pit (")))
        (pits (filter (fn [(l String)] -> Bool (stringContains? l "(:tag ")) (stringLines spec)))
        (pitText (stringJoin (map (fn [(l String)] -> String
                                    (str "(:" (between l "(:tag " " :do") " " (q (optionOr (sc/fieldAfter l ":do") "")) ")")) pits) " "))
        (line (str "(:card \"core/lang\" :purpose \"how to write ASL: syntax, effects, matching, records\" :rules ("
                   (stringJoin (map q rules) " ") ") :pit (" pitText ") :heal \"asl heal FILE repairs common slips in place\""
                   (exampleField ex) ")"))]
    (Card :id "core/lang" :purpose "how to write ASL: syntax, effects, matching, records" :keys (list "module" "fn" "match" "let") :line line :rows (list) :missing (list)))

fn indexText cards: (List Card) -> String
  (let [(lines (map (fn [(c Card)] -> String (str "(:c " (q c.id) " " (q (indexPurpose c.purpose)) " (" (stringJoin (listTake c.keys 2) " ") "))")) cards))
        (body (stringJoin lines "\n"))]
    (str "(:know :tier L0 :cards " (listLength cards) " :tokensBy bytes36 :use \"(:know :q intent-or-name :budget N) or asl know; a card id or exact symbol returns its card\")\n" body "\n"))

fn missingOf cards: (List Card) -> (List String)
  (listSort (listFlatMap (fn [(c Card)] -> (List String) c.missing) cards))

fn ! exampleOf! root: String id: String -> String
  (match (fileReadString (str root "/asl/packages/asl-know/src/examples/" (camelId id) ".asl"))
    ((ok src) (exampleText src))
    ((err _) ""))

fn ! allCards! root: String -> (List Card)
  (let [(pkgs (sc/packagesOf! root))
        (bs (sc/builtinsOf! root))
        (spec (resultOr (fileReadString (str root "/asl/packages/asl-know/lang.asn")) ""))
        (exs (mapFromPairs (map (fn [(id String)] -> (Pair String String) (pair id (exampleOf! root id)))
                                (listAppend (list "core/lang") (listAppend (map (fn [(s String)] -> String (areaId s)) (sections bs (list))) (map (fn [(p sc/Package)] -> String p.name) pkgs))))))
        (exOf (fn [(id String)] -> String (mapGetOr exs id "")))]
    (listAppend (list (langCard spec (exOf "core/lang")))
      (listAppend (areaCards bs exOf)
        (map (fn [(p sc/Package)] -> Card (packageCard p (exOf p.name))) pkgs))))

fn unquoteRow l: String -> (Option String)
  (let [(t (stringTrim l))]
    (if (and (stringStartsWith? t "\"") (stringEndsWith? t "\"") (> (stringLength t) 1))
      (optionMap sc/unescape (stringSlice t 1 (- (stringLength t) 1)))
      (none)))

fn uniq xs: (List String) acc: (List String) -> (List String)
  (match (listHead xs)
    ((none) (listReverse acc))
    ((some x) (uniq (optionOr (listTail xs) (list)) (if (listContains? acc x) acc (cons x acc)))))

fn sigName s: String -> String
  (let [(bare (stringTrim (stringReplace (stringReplace s "(" " ") ")" " ")))
        (ws (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit bare " ")))
        (lead (optionOr (listHead ws) ""))]
    (if (or (= lead "schema") (= lead "enum")) (optionOr (listGet ws 1) lead) lead))
