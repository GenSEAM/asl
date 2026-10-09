(module asl-forms/extract
  :x [ExtractSymbol braceBlockEnd pythonBlockEnd aslSymbols shellSymbols extractSymbols findSymbol outlineReceipt languageOf]
  :i [(asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/core/source :a src)
      (asl-syntax/asl/symbols :a aslsym)
      (asl-syntax/ts/symbols :a ts)
      (asl-syntax/js/symbols :a js)])

(schema ExtractSymbol
  (:f name String)
  (:f kind String)
  (:f start Int64)
  (:f end Int64)
  (:f depth Int64)
  (:f container String))

fn fromDef d: sym/SymbolDef -> ExtractSymbol
  (ExtractSymbol :name (sym/symbolName d) :kind (sym/symbolKind d)
    :start (sym/symbolStart d) :end (sym/symbolEnd d)
    :depth (sym/symbolDepth d) :container (sym/symbolContainer d))

fn aslSymbols text: String -> (List ExtractSymbol)
  (map fromDef (aslsym/aslSymbols text))

fn lineStartScan b: Bytes i: Int64 -> Int64
  (if (<= i 0) 0
    (if (= (bytesGet b (- i 1)) 10) i
      (lineStartScan b (- i 1))))

fn lineStart text: String offset: Int64 -> Int64
  (lineStartScan (stringToBytes text) (min offset (stringLength text)))

fn lineEnd text: String offset: Int64 -> Int64
  (let [(n (stringLength text))
        (tail (optionOr (stringSlice text offset n) ""))
        (idx (stringIndexOf tail "\n"))]
    (mt idx ((none) n) ((some i) (+ offset i))))

fn isSpace b: Int64 -> Bool
  (or (= b 32) (or (= b 9) (or (= b 10) (= b 13))))

fn skipSpace b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (isSpace (bytesGet b i))) (skipSpace b n (+ i 1)) i)

fn wordByte? b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90))
    (or (and (>= b 97) (<= b 122))
      (or (and (>= b 48) (<= b 57)) (or (= b 95) (= b 36)))))

fn wordEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (wordByte? (bytesGet b i))) (wordEnd b n (+ i 1)) i)

fn nextSignificant b: Bytes n: Int64 i: Int64 -> Int64
  (if (>= i n) n
    (if (or (= (bytesGet b i) 32) (= (bytesGet b i) 9) (= (bytesGet b i) 10) (= (bytesGet b i) 13))
      (nextSignificant b n (+ i 1)) i))

fn rustChar? b: Bytes n: Int64 i: Int64 -> Bool
  (or (and (< (+ i 2) n) (= (bytesGet b (+ i 2)) 39))
      (and (< (+ i 3) n) (= (bytesGet b (+ i 1)) 92) (= (bytesGet b (+ i 3)) 39)))

fn continuedLast c: Int64 -> Bool
  (listContains? (list 61 62 44 40 58 124 38 43 45 42 47 63) c)

fn continuedAfter b: Bytes n: Int64 i: Int64 -> Bool
  (let [(p (nextSignificant b n i))
        (c (if (< p n) (bytesGet b p) -1))]
    (listContains? (list 123 46 61 124 38 63 58) c))

fn hasAt text: String at: Int64 needle: String -> Bool
  (and (<= (+ at (stringLength needle)) (stringLength text))
    (= (optionOr (stringSlice text at (+ at (stringLength needle))) "") needle))

fn rustAttrStart text: String start: Int64 -> Int64
  (if (<= start 0) start
    (let [(prevEnd (- start 1))
          (prevStart (lineStart text prevEnd))
          (z (lineEnd text prevStart))
          (b (stringToBytes text))
          (p (skipSpace b z prevStart))]
      (if (hasAt text p "#[") (rustAttrStart text prevStart) start)))

fn pythonDecoratorStart text: String start: Int64 -> Int64
  (if (<= start 0) start
    (let [(prevStart (lineStart text (- start 1)))
          (prevEnd (lineEnd text prevStart))
          (p (skipSpace (stringToBytes text) prevEnd prevStart))]
      (if (hasAt text p "@") (pythonDecoratorStart text prevStart) start)))

fn goParenEnd b: Bytes limit: Int64 i: Int64 depth: Int64 -> Int64
  (if (>= i limit) i
    (let [(c (bytesGet b i))
          (d (cond ((= c 40) (+ depth 1)) ((= c 41) (- depth 1)) (else depth)))]
      (if (and (= c 41) (= d 0)) (+ i 1)
        (goParenEnd b limit (+ i 1) d))))

fn rustImplNameStart text: String b: Bytes z: Int64 start: Int64 -> Int64
  (let [(generic (and (< start z) (= (bytesGet b start) 60)))
        (gt (if generic (stringIndexOf (optionOr (stringSlice text start z) "") ">") (none)))
        (base (mt gt ((none) start) ((some k) (+ start k 1))))
        (spaced (or (not generic)
          (and (some? gt) (< base z) (or (= (bytesGet b base) 32) (= (bytesGet b base) 9)))))
        (forAt (stringIndexOf (optionOr (stringSlice text base z) "") " for "))
        (forStart (mt forAt ((none) base) ((some k) (+ base k 5))))]
    (if spaced (skipSpace b z forStart) z))

fn skipNonWordBack b: Bytes low: Int64 i: Int64 -> Int64
  (if (and (> i low) (not (wordByte? (bytesGet b (- i 1)))))
    (skipNonWordBack b low (- i 1)) i)

fn wordStartBack b: Bytes low: Int64 i: Int64 -> Int64
  (if (and (> i low) (wordByte? (bytesGet b (- i 1))))
    (wordStartBack b low (- i 1)) i)

fn goReceiverName text: String b: Bytes start: Int64 end: Int64 -> String
  (let [(wordEndOff (skipNonWordBack b start (- end 1)))
        (wordStartOff (wordStartBack b start wordEndOff))]
    (optionOr (stringSlice text wordStartOff wordEndOff) ""))

fn orderedInsert d: ExtractSymbol xs: (List ExtractSymbol) -> (List ExtractSymbol)
  (if (listEmpty? xs) (list d)
    (let [(h (optionOr (listHead xs) d))
          (tail (optionOr (listTail xs) (list)))]
      (if (<= d.start h.start) (cons d xs)
        (cons h (orderedInsert d tail)))))

fn sortExtracts xs: (List ExtractSymbol) acc: (List ExtractSymbol) -> (List ExtractSymbol)
  (if (listEmpty? xs) acc
    (let [(h (optionOr (listHead xs) (ExtractSymbol :name "" :kind "" :start 0 :end 0 :depth 0 :container "")))
          (tail (optionOr (listTail xs) (list)))]
      (sortExtracts tail (orderedInsert h acc))))

fn pythonEqual b: Bytes i: Int64 end: Int64 -> Int64
  (if (>= i end) -1
    (if (= (bytesGet b i) 61)
      (if (and (< (+ i 1) end) (= (bytesGet b (+ i 1)) 61))
        (pythonEqual b (+ i 2) end)
        (if (and (> i 0) (= (bytesGet b (- i 1)) 61))
          (pythonEqual b (+ i 1) end) i))
      (pythonEqual b (+ i 1) end)))

fn pythonVariableDef text: String masked: String p: Int64 z: Int64 -> (Option ExtractSymbol)
  (let [(b (stringToBytes masked))
        (nameEnd (wordEnd b z p))
        (eq (pythonEqual b nameEnd z))
        (name (optionOr (stringSlice text p nameEnd) ""))]
    (if (or (not (= p (lineStart text p))) (= nameEnd p) (< eq 0)
            (hasAt masked p "def ") (hasAt masked p "async def ") (hasAt masked p "class "))
      (none)
      (some (ExtractSymbol :name name :kind "variable" :start p
        :end (max nameEnd (braceBlockEnd text p "python")) :depth 0 :container ""))))

fn inlineSpaceEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (or (= (bytesGet b i) 32) (= (bytesGet b i) 9))) (inlineSpaceEnd b n (+ i 1)) i)

fn closeEnd b: Bytes n: Int64 i: Int64 -> Int64
  (let [(j (inlineSpaceEnd b n i))]
    (if (and (< j n) (or (= (bytesGet b j) 59) (= (bytesGet b j) 44))) (+ j 1) j))

fn statementEnds? b: Bytes n: Int64 depth: Int64 body: Bool last: Int64 i: Int64 -> Bool
  (and (not body) (= depth 0) (>= last 0)
    (not (continuedLast last))
    (not (continuedAfter b n (+ i 1))))

fn braceScan b: Bytes n: Int64 i: Int64 depth: Int64 body: Bool quote: Int64 escaped: Bool mode: Int64 lang: String last: Int64 -> Int64
  (if (>= i n) n
    (let [(c (bytesGet b i))
          (nx (if (< (+ i 1) n) (bytesGet b (+ i 1)) -1))]
      (cond
        ((= mode 1)
          (if (= c 10) (braceScan b n i depth body quote escaped 0 lang last)
            (braceScan b n (+ i 1) depth body quote escaped 1 lang last)))
        ((and (= mode 2) (= c 10) (statementEnds? b n depth body last i)) i)
        ((= mode 2) (braceScan b n (if (and (= c 42) (= nx 47)) (+ i 2) (+ i 1)) depth body quote escaped (if (and (= c 42) (= nx 47)) 0 2) lang last))
        ((> quote 0)
          (cond
            (escaped (braceScan b n (+ i 1) depth body quote false mode lang last))
            ((= c 92) (braceScan b n (+ i 1) depth body quote true mode lang last))
            ((= c quote) (braceScan b n (+ i 1) depth body 0 false mode lang last))
            (else (braceScan b n (+ i 1) depth body quote false mode lang last)))
        )
        ((and (= c 47) (= nx 47)) (braceScan b n (+ i 2) depth body 0 false 1 lang last))
        ((and (= c 47) (= nx 42)) (braceScan b n (+ i 2) depth body 0 false 2 lang last))
        ((and (= c 35) (= lang "python")) (braceScan b n (+ i 1) depth body 0 false 1 lang last))
        ((or (= c 34) (= c 96) (and (= c 39) (or (!= lang "rust") (rustChar? b n i)))) (braceScan b n (+ i 1) depth body c false 0 lang last))
        (else
          (let [(opens (listContains? (list 40 91 123) c))
                (closes (listContains? (list 41 93 125) c))
                (bodyNow (or body (and (= c 123) (= depth 0))))
                (d (cond (opens (+ depth 1)) (closes (max 0 (- depth 1))) (else depth)))]
            (cond
              ((and bodyNow (= c 125) (= d 0)) (closeEnd b n (+ i 1)))
              ((and (= c 59) (not bodyNow) (= depth 0)) (+ i 1))
              ((and (= c 10) (statementEnds? b n depth bodyNow last i)) i)
              (else (braceScan b n (+ i 1) d bodyNow 0 false 0 lang (if (isSpace c) last c)))))))))

fn braceBlockEnd text: String start: Int64 lang: String -> Int64
  (let [(b (stringToBytes text)) (n (stringLength text))]
    (braceScan b n (max 0 start) 0 false 0 false 0 lang -1))

fn indentAt b: Bytes end: Int64 start: Int64 -> Int64
  (if (and (< start end) (or (= (bytesGet b start) 32) (= (bytesGet b start) 9)))
    (+ 1 (indentAt b end (+ start 1))) 0)

fn pythonBracketScan b: Bytes end: Int64 i: Int64 depth: Int64 quote: Int64 escaped: Bool -> Int64
  (if (>= i end) depth
    (let [(c (bytesGet b i))]
      (cond
        ((> quote 0)
          (cond
            (escaped (pythonBracketScan b end (+ i 1) depth quote false))
            ((= c 92) (pythonBracketScan b end (+ i 1) depth quote true))
            ((= c quote) (pythonBracketScan b end (+ i 1) depth 0 false))
            (else (pythonBracketScan b end (+ i 1) depth quote false)))
        )
        ((= c 35) depth)
        ((or (= c 34) (= c 39)) (pythonBracketScan b end (+ i 1) depth c false))
        ((or (= c 40) (= c 91) (= c 123))
          (pythonBracketScan b end (+ i 1) (+ depth 1) 0 false))
        ((or (= c 41) (= c 93) (= c 125))
          (pythonBracketScan b end (+ i 1) (- depth 1) 0 false))
        (else (pythonBracketScan b end (+ i 1) depth 0 false)))))

fn pythonTripleToggle b: Bytes end: Int64 i: Int64 odd: Bool -> Bool
  (if (>= i end) odd
    (let [(c (bytesGet b i))
          (triple? (and (< (+ i 2) end) (or (= c 34) (= c 39))
            (= (bytesGet b (+ i 1)) c) (= (bytesGet b (+ i 2)) c)))]
      (if triple?
        (pythonTripleToggle b end (+ i 3) (not odd))
        (pythonTripleToggle b end (+ i 1) odd))))

fn pythonEndLoop text: String masked: String n: Int64 headIndent: Int64 cur: Int64 last: Int64 inTriple: Bool -> Int64
  (if (>= cur n) last
    (let [(z (lineEnd text cur))
          (mz (lineEnd masked cur))
          (b (stringToBytes masked))
          (ind (indentAt b mz cur))
          (blank (= (skipSpace b mz cur) mz))
          (next (+ z 1))
          (triple (pythonTripleToggle b mz cur false))]
      (if (and inTriple)
        (pythonEndLoop text masked n headIndent next (if blank last z) (if triple false true))
        (if (and (not blank) (<= ind headIndent))
        last
        (let [(newLast (if blank last z))]
          (pythonEndLoop text masked n headIndent next newLast triple))))))

fn pythonHeaderEnd text: String n: Int64 cur: Int64 depth: Int64 last: Int64 -> Int64
  (if (>= cur n) last
    (let [(z (lineEnd text cur))
          (b (stringToBytes text))
          (newDepth (pythonBracketScan b z cur depth 0 false))
          (next (+ z 1))]
      (if (<= newDepth 0) z
        (pythonHeaderEnd text n next newDepth z))))

fn pythonBlockEnd text: String start: Int64 -> Int64
  (let [(n (stringLength text))
        (st (lineStart text start))
        (b (stringToBytes text))
        (headIndent (indentAt b (lineEnd text st) st))
        (headEnd (pythonHeaderEnd text n st 0 st))]
    (pythonEndLoop text text n headIndent (+ headEnd 1) headEnd false))

fn ! syntaxTs text: String -> (List ExtractSymbol)
  (map fromDef (ts/tsSymbols! text))

fn ! syntaxJs text: String -> (List ExtractSymbol)
  (map fromDef (js/jsSymbols! text))

fn rustImpl? k: String -> Bool
  (listContains? (list "impl " "impl" "unsafe impl " "unsafe impl") k)

fn makeSimpleDef text: String masked: String p: Int64 z: Int64 lang: String -> (Option ExtractSymbol)
  (let [(b (stringToBytes masked))
        (k (cond ((= lang "python")
                   (cond ((hasAt masked p "def ") "def ")
                         ((hasAt masked p "class ") "class ")
                         ((hasAt masked p "async def ") "async def ")
                         (else "")))
                 ((= lang "go")
                   (cond ((hasAt masked p "func ") "func ")
                         ((hasAt masked p "type ") "type ")
                         ((hasAt masked p "var ") "var ")
                         ((hasAt masked p "const ") "const ")
                         (else "")))
                 ((= lang "rust")
                   (cond ((hasAt masked p "fn ") "fn ")
                         ((hasAt masked p "pub fn ") "pub fn ")
                         ((hasAt masked p "pub(crate) fn ") "pub(crate) fn ")
                         ((hasAt masked p "async fn ") "async fn ")
                         ((hasAt masked p "pub async fn ") "pub async fn ")
                         ((hasAt masked p "pub(crate) async fn ") "pub(crate) async fn ")
                         ((hasAt masked p "unsafe fn ") "unsafe fn ")
                         ((hasAt masked p "pub unsafe fn ") "pub unsafe fn ")
                         ((hasAt masked p "extern \"") "extern \"")
                         ((hasAt masked p "const fn ") "const fn ")
                         ((hasAt masked p "impl ") "impl ")
                         ((hasAt masked p "impl<") "impl")
                         ((hasAt masked p "unsafe impl ") "unsafe impl ")
                         ((hasAt masked p "unsafe impl<") "unsafe impl")
                         ((hasAt masked p "struct ") "struct ")
                         ((hasAt masked p "pub struct ") "pub struct ")
                         ((hasAt masked p "pub(crate) struct ") "pub(crate) struct ")
                         ((hasAt masked p "pub(crate) union ") "pub(crate) union ")
                         ((hasAt masked p "enum ") "enum ")
                         ((hasAt masked p "pub enum ") "pub enum ")
                         ((hasAt masked p "pub(crate) enum ") "pub(crate) enum ")
                         ((hasAt masked p "trait ") "trait ")
                         ((hasAt masked p "pub trait ") "pub trait ")
                         ((hasAt masked p "pub(crate) trait ") "pub(crate) trait ")
                         ((hasAt masked p "type ") "type ")
                         ((hasAt masked p "pub type ") "pub type ")
                         ((hasAt masked p "pub(crate) type ") "pub(crate) type ")
                         ((hasAt masked p "pub(crate) mod ") "pub(crate) mod ")
                         ((hasAt masked p "pub(crate) static ") "pub(crate) static ")
                         ((hasAt masked p "pub(crate) const ") "pub(crate) const ")
                         ((hasAt masked p "pub static ") "pub static ")
                         ((hasAt masked p "pub const ") "pub const ")
                         ((hasAt masked p "mod ") "mod ")
                         ((hasAt masked p "pub mod ") "pub mod ")
                         ((hasAt masked p "union ") "union ")
                         ((hasAt masked p "pub union ") "pub union ")
                         ((hasAt masked p "static ") "static ")
                         ((hasAt masked p "const ") "const ")
                         (else "")))
                 ((= lang "shell") "function ")
                 (else "")))]
    (if (= k "")
      (if (= lang "python") (pythonVariableDef text masked p z) (none))
      (let [(afterPrefix (+ p (stringLength k)))
            (receiver? (and (= lang "go") (< afterPrefix z) (= (bytesGet b afterPrefix) 40)))
            (afterReceiver (if receiver? (goParenEnd b z afterPrefix 0) afterPrefix))
            (q (skipSpace b z (if (and (= lang "rust") (rustImpl? k))
                (rustImplNameStart text b z afterPrefix) afterReceiver)))
            (e (wordEnd b z q))
            (name (optionOr (stringSlice text q e) ""))
            (container (if receiver? (goReceiverName text b afterPrefix afterReceiver) ""))]
        (if (= e q) (none)
          (let [(end (if (= lang "python") (pythonBlockEnd text p) (braceBlockEnd text p lang)))
                (symbolStart (cond
                  ((= lang "rust") (rustAttrStart text p))
                  ((and (= lang "python") (or (= k "def ") (= k "async def ") (= k "class "))) (pythonDecoratorStart text p))
                  (else p)))]
            (some (ExtractSymbol :name name
              :kind (cond
                ((= lang "python") (if (= k "class ") "class" "def"))
                ((and (= lang "go") (= k "type ")) "type")
                ((and (= lang "go") (or (= k "var ") (= k "const "))) "variable")
                ((= lang "go") "func")
                ((and (= lang "rust") (rustImpl? k)) "impl")
                ((= lang "rust") (if (or (= k "fn ") (stringContains? k " fn ")) "fn" "type"))
                ((= lang "shell") "function")
                (else "function"))
              :start symbolStart :end (max e end) :depth 0 :container container)))))))

fn shellNameStartByte? c: Int64 -> Bool
  (or (and (>= c 65) (<= c 90)) (or (and (>= c 97) (<= c 122)) (= c 95)))

fn shellNameByte? c: Int64 -> Bool
  (or (and (>= c 65) (<= c 90)) (or (and (>= c 97) (<= c 122))
    (or (and (>= c 48) (<= c 57)) (or (= c 95) (or (= c 58) (or (= c 46) (= c 45)))))))

fn shellNameEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (shellNameByte? (bytesGet b i))) (shellNameEnd b n (+ i 1)) i)

fn shellParenSkip b: Bytes z: Int64 i: Int64 -> Int64
  (let [(s (skipSpace b z i))]
    (if (and (< (+ s 1) z) (= (bytesGet b s) 40) (= (bytesGet b (+ s 1)) 41)) (+ s 2) s))

fn shellLineTrailingOk? b: Bytes z: Int64 i: Int64 -> Bool
  (let [(p (inlineSpaceEnd b z i))] (or (>= p z) (= (bytesGet b p) 35)))

fn shellFuncNameSpan masked: String b: Bytes p: Int64 z: Int64 -> (Option (Pair Int64 Int64))
  (if (hasAt masked p "function ")
    (let [(q (skipSpace b z (+ p 9))) (e (shellNameEnd b z q))]
      (if (or (= q e) (not (shellNameStartByte? (bytesGet b q)))) (none) (some (pair q e))))
    (let [(e (shellNameEnd b z p))
          (lp (skipSpace b z e))]
      (if (and (> e p) (shellNameStartByte? (bytesGet b p)) (< (+ lp 1) z) (= (bytesGet b lp) 40) (= (bytesGet b (+ lp 1)) 41))
        (some (pair p e))
        (none))))

fn skipBlankLines text: String n: Int64 cur: Int64 -> Int64
  (if (>= cur n) n
    (let [(z (lineEnd text cur)) (b (stringToBytes text))]
      (if (= (skipSpace b z cur) z) (skipBlankLines text n (+ z 1)) cur)))

fn lineStartsWithBrace? text: String n: Int64 cur: Int64 -> Bool
  (and (< cur n)
    (let [(z (lineEnd text cur)) (b (stringToBytes text)) (p (skipSpace b z cur))]
      (and (< p z) (= (bytesGet b p) 123))))

fn shellFuncResult text: String p: Int64 q: Int64 e: Int64 -> (Option ExtractSymbol)
  (let [(end (shellBlockEnd text p))]
    (if (< end 0) (none)
      (some (ExtractSymbol :name (optionOr (stringSlice text q e) "") :kind "function"
        :start p :end end :depth 0 :container ""))))

fn shellLineDef text: String masked: String p: Int64 z: Int64 -> (Option ExtractSymbol)
  (let [(b (stringToBytes masked)) (n (stringLength masked))
        (nameSpan (shellFuncNameSpan masked b p z))]
    (mt nameSpan
      ((none) (none))
      ((some sp)
        (let [(q (pairFirst sp)) (e (pairSecond sp))
              (restStart (shellParenSkip b z e))
              (afterSpace (skipSpace b z restStart))]
          (if (and (< afterSpace z) (= (bytesGet b afterSpace) 123))
            (if (shellLineTrailingOk? b z (+ afterSpace 1)) (shellFuncResult text p q e) (none))
            (if (and (shellLineTrailingOk? b z restStart)
                     (lineStartsWithBrace? text n (skipBlankLines text n (+ z 1))))
              (shellFuncResult text p q e)
              (none)))))))

fn shellBlockEndLoop text: String opening: Int64 cur: Int64 -> Int64
  (let [(n (stringLength text))]
    (if (>= cur n) -1
      (let [(z (lineEnd text cur))
            (b (stringToBytes text))
            (indent (indentAt b z cur))
            (p (skipSpace b z cur))
            (next (+ z 1))]
        (if (and (<= indent opening) (< p z) (= (bytesGet b p) 125)) z
          (shellBlockEndLoop text opening next)))))

fn shellBlockEnd text: String start: Int64 -> Int64
  (let [(line (lineStart text start))
        (z (lineEnd text line))
        (opening (indentAt (stringToBytes text) z line))]
    (shellBlockEndLoop text opening (+ z 1)))

fn spacesOf n: Int64 -> String
  (if (<= n 0) "" (str " " (spacesOf (- n 1))))

fn maskSpan text: String a: Int64 b: Int64 -> String
  (stringJoin (map (fn [(l String)] -> String (spacesOf (stringLength l))) (stringSplit (optionOr (stringSlice text a b) "") "\n")) "\n")

fn findNewlineOrEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (>= i n) n (if (= (bytesGet b i) 10) i (findNewlineOrEnd b n (+ i 1))))

fn findCloseStar b: Bytes n: Int64 i: Int64 -> Int64
  (if (>= i n) n
    (let [(c (bytesGet b i)) (nx (if (< (+ i 1) n) (bytesGet b (+ i 1)) -1))]
      (if (and (= c 42) (= nx 47)) (+ i 2) (findCloseStar b n (+ i 1)))))

fn findCloseStarNested b: Bytes n: Int64 i: Int64 depth: Int64 -> Int64
  (if (>= i n) n
    (let [(c (bytesGet b i)) (nx (if (< (+ i 1) n) (bytesGet b (+ i 1)) -1))]
      (cond
        ((and (= c 47) (= nx 42)) (findCloseStarNested b n (+ i 2) (+ depth 1)))
        ((and (= c 42) (= nx 47)) (if (<= depth 1) (+ i 2) (findCloseStarNested b n (+ i 2) (- depth 1))))
        (else (findCloseStarNested b n (+ i 1) depth)))))

fn findBacktickEndLoop b: Bytes n: Int64 j: Int64 -> Int64
  (if (>= j n) n (if (= (bytesGet b j) 96) (+ j 1) (findBacktickEndLoop b n (+ j 1))))

fn findBacktickEnd b: Bytes n: Int64 i: Int64 -> Int64
  (findBacktickEndLoop b n (+ i 1))

fn quotedEndLoop b: Bytes n: Int64 j: Int64 qc: Int64 multiline: Bool -> Int64
  (if (>= j n) n
    (let [(c (bytesGet b j))]
      (cond
        ((= c 92) (quotedEndLoop b n (+ j 2) qc multiline))
        ((= c qc) (+ j 1))
        ((and (= c 10) (not multiline)) j)
        (else (quotedEndLoop b n (+ j 1) qc multiline)))))

fn quotedEndSimple b: Bytes n: Int64 i: Int64 qc: Int64 multiline: Bool -> Int64
  (quotedEndLoop b n (+ i 1) qc multiline)

fn rustCharEndOffset b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< (+ i 1) n) (= (bytesGet b (+ i 1)) 92)) (+ i 4) (+ i 3))

fn allHashesFrom b: Bytes n: Int64 i: Int64 remaining: Int64 -> Bool
  (if (<= remaining 0) true (and (< i n) (= (bytesGet b i) 35) (allHashesFrom b n (+ i 1) (- remaining 1))))

fn matchCloserAt b: Bytes n: Int64 i: Int64 hashCount: Int64 -> Bool
  (and (< i n) (= (bytesGet b i) 34) (allHashesFrom b n (+ i 1) hashCount))

fn findRawCloser b: Bytes n: Int64 i: Int64 hashCount: Int64 -> Int64
  (if (>= i n) n (if (matchCloserAt b n i hashCount) (+ i 1 hashCount) (findRawCloser b n (+ i 1) hashCount)))

fn rustRawHashCount b: Bytes n: Int64 i: Int64 cnt: Int64 -> Int64
  (if (and (< i n) (= (bytesGet b i) 35)) (rustRawHashCount b n (+ i 1) (+ cnt 1)) cnt)

fn rustRawQuotePos b: Bytes n: Int64 i: Int64 -> Int64
  (let [(isB (= (bytesGet b i) 98))
        (rPos (if isB (+ i 1) i))]
    (if (or (>= rPos n) (!= (bytesGet b rPos) 114)) -1
      (let [(hashStart (+ rPos 1))
            (hc (rustRawHashCount b n hashStart 0))
            (q (+ hashStart hc))]
        (if (and (< q n) (= (bytesGet b q) 34)) q -1))))

fn rustRawHashCountAt b: Bytes n: Int64 i: Int64 q: Int64 -> Int64
  (let [(isB (= (bytesGet b i) 98)) (rPos (if isB (+ i 1) i))]
    (- q (+ rPos 1)))

fn maskScan b: Bytes n: Int64 text: String i: Int64 lastCut: Int64 lang: String acc: String -> String
  (if (>= i n) (str acc (optionOr (stringSlice text lastCut n) ""))
    (let [(c (bytesGet b i)) (nx (if (< (+ i 1) n) (bytesGet b (+ i 1)) -1))
          (rawQuote (if (and (= lang "rust") (or (= c 114) (= c 98))
                          (or (= i 0) (not (wordByte? (bytesGet b (- i 1))))))
                      (rustRawQuotePos b n i) -1))]
      (cond
        ((and (= c 47) (= nx 47))
          (let [(j (findNewlineOrEnd b n i))]
            (maskScan b n text j j lang (str acc (optionOr (stringSlice text lastCut i) "") (maskSpan text i j)))))
        ((and (= c 47) (= nx 42))
          (let [(j (if (= lang "rust") (findCloseStarNested b n (+ i 2) 1) (findCloseStar b n (+ i 2))))]
            (maskScan b n text j j lang (str acc (optionOr (stringSlice text lastCut i) "") (maskSpan text i j)))))
        ((>= rawQuote 0)
          (let [(hc (rustRawHashCountAt b n i rawQuote)) (j (findRawCloser b n (+ rawQuote 1) hc))]
            (maskScan b n text j j lang (str acc (optionOr (stringSlice text lastCut i) "") (maskSpan text i j)))))
        ((and (= lang "go") (= c 34))
          (let [(j (quotedEndSimple b n i 34 false))]
            (maskScan b n text j j lang (str acc (optionOr (stringSlice text lastCut i) "") (maskSpan text i j)))))
        ((and (= lang "go") (= c 96))
          (let [(j (findBacktickEnd b n i))]
            (maskScan b n text j j lang (str acc (optionOr (stringSlice text lastCut i) "") (maskSpan text i j)))))
        ((and (= lang "go") (= c 39))
          (let [(j (quotedEndSimple b n i 39 false))]
            (maskScan b n text j j lang (str acc (optionOr (stringSlice text lastCut i) "") (maskSpan text i j)))))
        ((and (= lang "rust") (= c 34))
          (let [(j (quotedEndSimple b n i 34 true))]
            (maskScan b n text j j lang (str acc (optionOr (stringSlice text lastCut i) "") (maskSpan text i j)))))
        ((and (= lang "rust") (= c 39) (rustChar? b n i))
          (let [(j (rustCharEndOffset b n i))]
            (maskScan b n text j j lang (str acc (optionOr (stringSlice text lastCut i) "") (maskSpan text i j)))))
        (else (maskScan b n text (+ i 1) lastCut lang acc)))))

fn maskCode text: String lang: String -> String
  (if (or (= lang "go") (= lang "rust"))
    (maskScan (stringToBytes text) (stringLength text) text 0 0 lang "")
    text)

fn simpleLoop text: String masked: String lang: String cur: Int64 acc: (List ExtractSymbol) -> (List ExtractSymbol)
  (let [(n (stringLength text))]
    (if (>= cur n) (listReverse acc)
      (let [(z (lineEnd text cur))
            (p (skipSpace (stringToBytes masked) z cur))
            (found (if (= lang "shell") (shellLineDef text masked p z) (makeSimpleDef text masked p z lang)))
            (next (+ z 1))]
        (mt found
          ((none) (simpleLoop text masked lang next acc))
          ((some d) (simpleLoop text masked lang next (cons d acc)))))))

fn pythonLoop text: String cur: Int64 inTriple: Bool acc: (List ExtractSymbol) -> (List ExtractSymbol)
  (let [(n (stringLength text))]
    (if (>= cur n) (listReverse acc)
      (let [(z (lineEnd text cur))
            (p (skipSpace (stringToBytes text) z cur))
            (toggles (pythonTripleToggle (stringToBytes text) z cur false))
            (found (if inTriple (none) (makeSimpleDef text text p z "python")))
            (next (+ z 1))]
        (mt found
          ((none) (pythonLoop text next (if toggles (not inTriple) inTriple) acc))
          ((some d) (pythonLoop text next (if toggles (not inTriple) inTriple) (cons d acc)))))))

fn shellSymbols text: String -> (List ExtractSymbol)
  (sortExtracts
    (listAppend (simpleLoop text text "shell" 0 (list))
      (filter (fn [(d ExtractSymbol)] -> Bool (!= d.kind "variable"))
        (simpleLoop text text "python" 0 (list)))) (list))

fn ! extractSymbols text: String lang: String -> (List ExtractSymbol)
  (cond
    ((or (= lang "asl") (= lang "asn")) (aslSymbols text))
    ((or (= lang "markdown") (= lang "md")) (list))
    ((= lang "typescript") (syntaxTs text))
    ((= lang "javascript") (syntaxJs text))
    ((= lang "python") (pythonLoop text 0 false (list)))
    ((or (= lang "go") (= lang "rust"))
      (simpleLoop text (maskCode text lang) lang 0 (list)))
    ((= lang "shell") (shellSymbols text))
    (else (list)))

fn lastDot text: String at: Int64 found: Int64 -> Int64
  (if (>= at (stringLength text)) found
    (lastDot text (+ at 1) (if (= (optionOr (stringSlice text at (+ at 1)) "") ".") at found)))

fn pathBase text: String at: Int64 found: Int64 -> String
  (if (>= at (stringLength text)) (optionOr (stringSlice text found (stringLength text)) "")
    (pathBase text (+ at 1) (if (= (optionOr (stringSlice text at (+ at 1)) "") "/") (+ at 1) found)))

fn extOf path: String -> String
  (let [(base (pathBase path 0 0))
        (dot (lastDot base 0 -1))]
    (if (or (< dot 0) (= dot 0)) ""
      (stringLower (optionOr (stringSlice base dot (stringLength base)) ""))))

fn shebangWordEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (not (listContains? (list 9 10 13 32) (bytesGet b i))))
    (shebangWordEnd b n (+ i 1)) i)

fn stripInterpreterVersion s: String -> String
  (let [(n (stringLength s))
        (c (if (> n 0) (charCode (optionOr (stringSlice s (- n 1) n) "")) -1))]
    (if (or (and (>= c 48) (<= c 57)) (= c 46))
      (stripInterpreterVersion (optionOr (stringSlice s 0 (- n 1)) "")) s))

fn shebangLangWord text: String -> String
  (let [(b (stringToBytes text))
        (n (stringLength text))
        (lineEnd (min 256 (lineEnd text 0)))]
    (if (or (< n 2) (!= (bytesGet b 0) 35) (!= (bytesGet b 1) 33)) "text"
      (shebangLangWords text b lineEnd 2)))

fn shebangLangWords text: String b: Bytes end: Int64 at: Int64 -> String
  (let [(start (skipSpace b end at))]
    (if (>= start end) "text"
      (let [(stop (shebangWordEnd b end start))
            (word (optionOr (stringSlice text start stop) ""))
            (base (pathBase word 0 0))]
        (if (or (= base "env") (stringStartsWith? word "-"))
          (shebangLangWords text b end stop)
          (let [(prog (stripInterpreterVersion base))]
            (cond
              ((= prog "python") "python")
              ((listContains? (list "bash" "sh" "zsh" "dash" "ksh") prog) "shell")
              ((= prog "node") "javascript")
              (else "text")))))))

fn languageOf path: String text: String -> String
  (let [(ext (extOf path))]
    (if (not (stringEmpty? ext))
      (cond
        ((listContains? (list ".asl") ext) "asl")
        ((= ext ".asn") "asn")
        ((listContains? (list ".ts" ".tsx" ".mts" ".cts") ext) "typescript")
        ((listContains? (list ".js" ".jsx" ".mjs" ".cjs") ext) "javascript")
        ((= ext ".py") "python")
        ((= ext ".go") "go")
        ((= ext ".rs") "rust")
        ((listContains? (list ".c" ".h") ext) "c")
        ((= ext ".java") "java")
        ((listContains? (list ".sh" ".bash") ext) "shell")
        ((= ext ".md") "markdown")
        ((= ext ".json") "json")
        ((listContains? (list ".yaml" ".yml") ext) "yaml")
        ((= ext ".toml") "toml")
        (else "text"))
      (shebangLangWord text)))

fn toDef d: ExtractSymbol -> sym/SymbolDef
  (sym/makeScopedSymbolDef d.name d.kind d.start d.end d.container d.depth)

fn outlineReceipt file: String lang: String text: String syms: (List ExtractSymbol) -> String
  (let [(count (listLength syms))
        (source (src/sourceFromString file text))
        (items (stringJoin
          (map (fn [(d ExtractSymbol)] -> String
            (let [(startLine (optionOr (src/sourceLineAt source d.start) 1))
                  (endOffset (if (> d.end d.start) (- d.end 1) d.start))
                  (endLine (optionOr (src/sourceLineAt source endOffset) startLine))]
              (out/formatOutlineItem d.name d.kind startLine endLine))) syms) " "))]
    (str "(:outline :status :ok :file \"" (out/escapeAsnValue file)
      "\" :language \"" (out/escapeAsnValue lang)
      "\" :itemsCount " (stringFromInt64 count)
      " :items " (if (= count 0) "()" (str "(" items ")")) ")"))

fn findByStart syms: (List ExtractSymbol) start: Int64 -> (Option ExtractSymbol)
  (if (listEmpty? syms) (none)
    (let [(h (optionOr (listHead syms) (ExtractSymbol :name "" :kind "" :start -1 :end -1 :depth 0 :container "")))
          (tail (optionOr (listTail syms) (list)))]
      (if (= h.start start) (some h) (findByStart tail start))))

fn ! findSymbol text: String lang: String name: String -> (Pair (Option ExtractSymbol) (List ExtractSymbol))
  (let [(syms (extractSymbols text lang))
        (hit (sym/findSymbolDotted (map toDef syms) name))]
    (pair (mt hit ((none) (none)) ((some d) (findByStart syms (sym/symbolStart d)))) syms))
