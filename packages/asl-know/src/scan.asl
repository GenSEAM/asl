(module asl-know/scan
  :x [Decl Module Package Builtin quoteEnd unescape fieldAfter compact docRows! moduleOf packagesOf! builtinsOf! builtinsFrom sourceFiles! returnType effectful?]
  :i [(asl-checker/types :a ty)])

; (:m :tags (know) :note "facts a knowledge card is rendered from: module headers, column-0 declarations, doc.asn rows, prelude.asn builtins; read as text, never evaluated")

(schema Decl (:f name String) (:f kind String) (:f sig String) (:f owner String))

(schema Module (:f path String) (:f name String) (:f exports (List String)) (:f decls (Map String Decl)))

(schema Package (:f name String) (:f description String) (:f entry String) (:f deps (List String)) (:f modules (List Module)) (:f docs (Map String String)))

(schema Builtin (:f name String) (:f sec String) (:f type String) (:f doc String))

fn quoteEnd b: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) -1)
    ((= (bytesGet b i) 92) (quoteEnd b n (+ i 2)))
    ((= (bytesGet b i) 34) i)
    (else (quoteEnd b n (+ i 1))))

fn unescape s: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s "\\\\" "\x01") "\\\"" "\"") "\\n" " ") "\\t" " ") "\x01" "\\")

fn fieldAfter line: String key: String -> (Option String)
  (match (stringIndexOf line (str key " \""))
    ((none) (none))
    ((some at)
      (let [(start (+ at (+ (stringLength key) 2)))
            (b (stringToBytes line))
            (e (quoteEnd b (bytesLength b) start))]
        (if (< e 0) (none) (optionMap unescape (stringSlice line start e))))))

fn squeeze s: String -> String
  (let [(t (stringReplace (stringReplace s "\t" " ") "  " " "))]
    (if (stringContains? t "  ") (squeeze t) t))

fn compact s: String -> String
  (stringTrim (squeeze (stringReplace (stringReplace s "\r" " ") "\n" " ")))

; (:m :do "a fact naming a retired path, or the module a retired asl/packages source declares (asl/grammar/retired.asn), stays out of every card: its doc row is dropped and such a description is left empty")
fn retiredModuleOf path: String -> (List String)
  (if (and (stringStartsWith? path "asl/packages/") (stringEndsWith? path ".asl"))
    (let [(rest (optionOr (stringSlice path 13 (- (stringLength path) 4)) ""))]
      (match (stringIndexOf rest "/src/")
        ((none) (list))
        ((some i) (list (str (optionOr (stringSlice rest 0 i) "") "/" (optionOr (stringSlice rest (+ i 5) (stringLength rest)) ""))))))
    (list))

fn ! retiredNames! root: String -> (List String)
  (match (fileReadString (str root "/asl/grammar/retired.asn"))
    ((err _) (list))
    ((ok text)
      (listFlatMap (fn [(line String)] -> (List String)
                     (if (stringContains? line "(:retired ")
                       (match (fieldAfter line ":path") ((none) (list)) ((some p) (cons p (retiredModuleOf p))))
                       (list)))
                   (stringLines text))))

fn mentionsRetired? text: String retired: (List String) -> Bool
  (listAny? (fn [(n String)] -> Bool (stringContains? text n)) retired)

fn ! docRows! path: String retired: (List String) -> (Map String String)
  (match (fileReadString path)
    ((err _) (mapEmpty))
    ((ok text)
      (fold (fn [(acc (Map String String)) (line String)] -> (Map String String)
              (match (fieldAfter line ":symbol")
                ((none) acc)
                ((some sym) (match (fieldAfter line ":text")
                              ((none) acc)
                              ((some t) (if (mentionsRetired? t retired) acc (mapSet acc sym t)))))))
            (mapEmpty) (stringLines text))))

fn parenDepth s: String -> Int64
  (- (stringCountChar s "(") (stringCountChar s ")"))

fn headerText lines: (List String) acc: String -> String
  (match (listHead lines)
    ((none) acc)
    ((some l)
      (let [(next (str acc " " l))]
        (if (<= (parenDepth next) 0) next (headerText (optionOr (listTail lines) (list)) next)))))

fn words s: String -> (List String)
  (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (compact s) " "))

fn bracketAfter text: String key: String -> String
  (let [(sq (stringIndexOf text (str key " [")))
        (pa (stringIndexOf text (str key " (")))
        (at (match sq ((some i) (some (pair i "]"))) ((none) (match pa ((some j) (some (pair j ")"))) ((none) (none))))))]
    (match at
      ((none) "")
      ((some p)
        (let [(start (+ (pairFirst p) (+ (stringLength key) 2)))
              (rest (optionOr (stringSlice text start (stringLength text)) ""))
              (close (optionOr (stringIndexOf rest (pairSecond p)) (stringLength rest)))]
          (optionOr (stringSlice rest 0 close) "")))))

fn moduleName header: String -> String
  (optionOr (listGet (words (stringReplace header "(" " ")) 1) "")

fn afterPrefix line: String prefix: String -> String
  (optionOr (stringSlice line (stringLength prefix) (stringLength line)) "")

fn firstWord s: String -> String
  (optionOr (listHead (words (stringReplace (stringReplace s "(" " ") ")" " "))) "")

fn indented? line: String -> Bool
  (or (stringStartsWith? line " ") (stringStartsWith? line "\t"))

fn blockLines lines: (List String) acc: (List String) -> (List String)
  (match (listHead lines)
    ((none) (listReverse acc))
    ((some l)
      (if (or (indented? l) (stringEmpty? (stringTrim l)))
        (blockLines (optionOr (listTail lines) (list)) (cons l acc))
        (listReverse acc))))

fn capText s: String n: Int64 -> String
  (if (<= (stringLength s) n) s (str (optionOr (stringSliceUtf8 s 0 n) (optionOr (stringSlice s 0 n) "")) " ..."))

fn ctorDecls owner: String block: (List String) -> (List Decl)
  (fold (fn [(acc (List Decl)) (l String)] -> (List Decl)
          (let [(t (stringTrim l))]
            (cond
              ((stringStartsWith? t "(:c ")
                (cons (Decl :name (firstWord (afterPrefix t "(:c ")) :kind "ctor" :sig (capText (compact t) 160) :owner owner) acc))
              ((and (stringStartsWith? t "(") (not (stringStartsWith? t "(:")))
                (cons (Decl :name (firstWord t) :kind "ctor" :sig (capText (compact t) 160) :owner owner) acc))
              (else acc))))
        (list) block)

fn inlineCtors owner: String text: String -> (List Decl)
  (map (fn [(part String)] -> Decl (Decl :name (firstWord part) :kind "ctor" :sig (capText (compact (str "(:c " part)) 160) :owner owner))
       (optionOr (listTail (stringSplit text "(:c ")) (list)))

fn declsAt lines: (List String) acc: (List Decl) -> (List Decl)
  (match (listHead lines)
    ((none) (listReverse acc))
    ((some line)
      (let [(rest (optionOr (listTail lines) (list)))]
        (cond
          ((stringStartsWith? line "fn ")
            (let [(head (afterPrefix line "fn "))
                  (bang (stringStartsWith? head "! "))
                  (sig (if bang (afterPrefix head "! ") head))
                  (name (firstWord sig))]
              (declsAt rest (cons (Decl :name name :kind (if bang "fn!" "fn") :sig (capText (compact sig) 240) :owner "") acc))))
          ((or (stringStartsWith? line "(schema ") (stringStartsWith? line "schema "))
            (let [(block (blockLines rest (list)))
                  (name (firstWord (afterPrefix (stringTrim line) (if (stringStartsWith? line "(") "(schema " "schema "))))
                  (text (compact (stringJoin (cons line block) " ")))]
              (declsAt rest (cons (Decl :name name :kind "type" :sig (capText text 300) :owner "") acc))))
          ((or (stringStartsWith? line "(enum ") (stringStartsWith? line "enum "))
            (let [(block (blockLines rest (list)))
                  (name (firstWord (afterPrefix (stringTrim line) (if (stringStartsWith? line "(") "(enum " "enum "))))
                  (text (compact (stringJoin (cons line block) " ")))
                  (ctors (if (stringStartsWith? line "(") (inlineCtors name text) (ctorDecls name block)))]
              (declsAt rest (listAppend (listReverse ctors) (cons (Decl :name name :kind "type" :sig (capText text 300) :owner "") acc)))))
          (else (declsAt rest acc))))))

fn moduleOf path: String text: String -> Module
  (let [(lines (stringLines text))
        (from (listDrop lines (optionOr (listIndexOf (map (fn [(l String)] -> Bool (stringStartsWith? l "(module")) lines) true) 0)))
        (header (headerText from ""))
        (decls (declsAt lines (list)))]
    (Module :path path :name (moduleName header) :exports (words (bracketAfter header ":x"))
            :decls (fold (fn [(m (Map String Decl)) (d Decl)] -> (Map String Decl) (if (mapHas? m d.name) m (mapSet m d.name d))) (mapEmpty) decls)))

fn ! isDir? path: String -> Bool
  (match (fileStat path) ((ok st) st.isDir) ((err _) false))

fn ! sourceFiles! dir: String -> (List String)
  (match (dirList dir)
    ((err _) (list))
    ((ok names)
      (listFlatMap (fn [(n String)] -> (List String)
                     (let [(p (str dir "/" n))]
                       (cond
                         ((isDir? p) (sourceFiles! p))
                         ((stringEndsWith? n ".asl") (list p))
                         (else (list)))))
                   (listSort names))))

fn relTo root: String p: String -> String
  (if (stringStartsWith? p (str root "/")) (afterPrefix p (str root "/")) p)

fn ! packageOf! root: String retired: (List String) name: String -> (Option Package)
  (let [(dir (str root "/asl/packages/" name))]
    (match (fileReadString (str dir "/manifest.asn"))
      ((err _) (none))
      ((ok manifest)
        (let [(files (sourceFiles! (str dir "/src")))
              (mods (filter (fn [(m Module)] -> Bool (not (stringEmpty? m.name)))
                            (map (fn [(f String)] -> Module (moduleOf (relTo root f) (resultOr (fileReadString f) ""))) files)))
              (description (compact (optionOr (fieldAfter manifest ":description") "")))]
          (some (Package :name name :description (if (mentionsRetired? description retired) "" description) :entry (str "asl/packages/" name "/" (optionOr (fieldAfter manifest ":entry") ""))
                         :deps (map (fn [(w String)] -> String (stringReplace w "\"" "")) (words (bracketAfter manifest ":dependencies")))
                         :modules mods :docs (docRows! (str dir "/doc.asn") retired)))))))

fn ! packagesOf! root: String -> (List Package)
  (let [(retired (retiredNames! root))]
    (match (dirList (str root "/asl/packages"))
      ((err _) (list))
      ((ok names) (listFlatMap (fn [(n String)] -> (List Package) (match (packageOf! root retired n) ((some p) (list p)) ((none) (list)))) (listSort names)))))

fn checkerType name: String fallback: String -> String
  (match (ty/builtinSig name)
    ((none) fallback)
    ((some sig)
      (let [(params (pairFirst sig)) (variadic (pairFirst (pairSecond sig))) (ret (pairSecond (pairSecond sig)))
            (shown (if (and variadic (not (listEmpty? params)))
                     (listAppend (listTake params (- (listLength params) 1)) (list (str (optionOr (listLast params) "") "...")))
                     params))]
        (str (if (listEmpty? shown) "()" (stringJoin shown " ")) " -> " ret))))

fn absentOf text: String -> (List String)
  (match (stringIndexOf text ":absent (")
    ((none) (list))
    ((some a)
      (let [(rest (optionOr (stringSlice text a (stringLength text)) ""))]
        (map (fn [(w String)] -> String (stringReplace w "\"" "")) (words (bracketAfter rest ":names"))))))

fn builtinRows lines: (List String) acc: (List Builtin) -> (List Builtin)
  (match (listHead lines)
    ((none) (listReverse acc))
    ((some line)
      (let [(rest (optionOr (listTail lines) (list)))
            (next (optionOr (listHead rest) ""))]
        (if (stringStartsWith? (stringTrim line) "(:name \"")
          (let [(name (optionOr (fieldAfter line "(:name") ""))
                (doc (optionOr (fieldAfter (if (stringContains? line ":doc \"") line next) ":doc") ""))
                (b (Builtin :name name :sec (optionOr (fieldAfter line ":sec") "") :type (checkerType name (optionOr (fieldAfter line ":type") "")) :doc doc))]
            (builtinRows rest (cons b acc)))
          (builtinRows rest acc)))))

fn builtinsFrom text: String -> (List Builtin)
  (let [(absent (absentOf text))]
    (filter (fn [(b Builtin)] -> Bool (and (not (stringEmpty? b.name)) (not (listContains? absent b.name)))) (builtinRows (stringLines text) (list))))

fn ! builtinsOf! root: String -> (List Builtin)
  (builtinsFrom (resultOr (fileReadString (str root "/asl/prelude/prelude.asn")) ""))

fn returnType sig: String -> String
  (match (stringIndexOf sig " -> ")
    ((none) "")
    ((some i) (stringTrim (optionOr (stringSlice sig (+ i 4) (stringLength sig)) ""))))

fn effectful? d: Decl -> Bool
  (or (= d.kind "fn!") (stringEndsWith? d.name "!"))
