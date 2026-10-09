(module ws/mergeRows/mergeRows
  :x [MergeResult mergeRows main]
  :i [])

(schema MergeResult (:f text String) (:f conflict Bool))

(schema Line (:f row Bool) (:f text String) (:f indent String) (:f form String) (:f suffix String) (:f key String))
(schema Out (:f key String) (:f text String) (:f theirsText String) (:f suffix String) (:f conflict Bool))
(schema Skel (:f outs (List Out)) (:f ok Bool) (:f recount Bool))
(schema Walk (:f outs (List Out)) (:f skel (List Out)) (:f ok Bool))
(schema Place (:f anchor String) (:f pending (List Out)) (:f after (Map String (List Out))) (:f before (Map String (List Out))) (:f ok Bool))

fn ch text: String i: Int64 -> String
  (optionOr (stringSlice text i (+ i 1)) "")

fn sliceFrom text: String i: Int64 -> String
  (optionOr (stringSlice text i (stringLength text)) "")

fn indentEnd text: String i: Int64 -> Int64
  (if (and (< i (stringLength text)) (or (= (ch text i) " ") (= (ch text i) "\t"))) (indentEnd text (+ i 1)) i)

fn stringEnd text: String i: Int64 escaped: Bool -> Int64
  (cond
    ((>= i (stringLength text)) (- 0 1))
    (escaped (stringEnd text (+ i 1) false))
    ((= (ch text i) "\\") (stringEnd text (+ i 1) true))
    ((= (ch text i) "\"") (+ i 1))
    (else (stringEnd text (+ i 1) false)))

fn formEnd text: String i: Int64 depth: Int64 -> Int64
  (if (>= i (stringLength text))
    (- 0 1)
    (let [(c (ch text i))]
      (cond
        ((= c "\"") (let [(e (stringEnd text (+ i 1) false))] (if (< e 0) (- 0 1) (formEnd text e depth))))
        ((= c "(") (formEnd text (+ i 1) (+ depth 1)))
        ((= c ")") (if (= depth 1) (+ i 1) (formEnd text (+ i 1) (- depth 1))))
        (else (formEnd text (+ i 1) depth)))))

fn closersOnly? text: String i: Int64 -> Bool
  (cond
    ((>= i (stringLength text)) true)
    ((listContains? (list ")" " " "\t") (ch text i)) (closersOnly? text (+ i 1)))
    (else false))

fn tokenStop text: String i: Int64 -> Int64
  (if (and (< i (stringLength text)) (not (listContains? (list " " "\t" "(" ")" "\"") (ch text i)))) (tokenStop text (+ i 1)) i)

fn digitsEnd text: String i: Int64 -> Int64
  (if (and (< i (stringLength text)) (stringContains? "0123456789" (ch text i))) (digitsEnd text (+ i 1)) i)

fn firstString form: String -> (Option String)
  (mt (stringIndexOf form "\"")
    ((none) (none))
    ((some q) (let [(e (stringEnd form (+ q 1) false))]
      (if (< e 0) (none) (stringSlice form (+ q 1) (- e 1))))))

fn canonical text: String -> String
  (canonScan text 0 (list))

fn canonScan text: String i: Int64 acc: (List String) -> String
  (if (>= i (stringLength text))
    (stringJoin (listReverse acc) "")
    (let [(c (ch text i))]
      (cond
        ((= c "\"") (let [(e (stringEnd text (+ i 1) false)) (stop (if (< e 0) (stringLength text) e))]
                       (canonScan text stop (cons (optionOr (stringSlice text i stop) "") acc))))
        ((listContains? (list " " "\t" "\r") c) (canonScan text (+ i 1) acc))
        (else (canonScan text (+ i 1) (cons c acc))))))

fn same? a: String b: String -> Bool
  (= (canonical a) (canonical b))

fn skeletonLine text: String -> Line
  (Line :row false :text text :indent "" :form "" :suffix "" :key "")

fn parseLine text: String -> Line
  (let [(start (indentEnd text 0))
        (c (ch text start))
        (end (cond
               ((= c "(") (formEnd text start 0))
               ((= c "\"") (stringEnd text (+ start 1) false))
               (else (- 0 1))))]
    (if (or (< end 0) (not (closersOnly? text end)))
      (skeletonLine text)
      (let [(form (optionOr (stringSlice text start end) ""))]
        (mt (firstString form)
          ((none) (skeletonLine text))
          ((some first)
            (let [(tag (if (= c "\"") "\"" (optionOr (stringSlice form 1 (tokenStop form 1)) "")))]
              (Line :row true :text text :indent (optionOr (stringSlice text 0 start) "") :form form
                    :suffix (sliceFrom text end)
                    :key (if (= tag ":raise") (str ":raise|" (canonical form)) (str tag "|" first)))))))))

fn withKey l: Line key: String -> Line
  (with l :key key)

fn numberKeys lines: (List Line) seen: (Map String Int64) acc: (List Line) -> (List Line)
  (mt (listHead lines)
    ((none) (listReverse acc))
    ((some l)
      (let [(tail (optionOr (listTail lines) (list)))]
        (if (or (not l.row) (stringStartsWith? l.key ":raise|"))
          (numberKeys tail seen (cons l acc))
          (let [(n (+ (optionOr (mapGet seen l.key) 0) 1))]
            (numberKeys tail (mapSet seen l.key n) (cons (withKey l (str l.key "#" (stringFromInt64 n))) acc)))))))

fn parseLines text: String -> (List Line)
  (numberKeys (map parseLine (stringSplit text "\n")) (mapEmpty) (list))

fn rowMap lines: (List Line) -> (Map String Line)
  (fold (fn [(m (Map String Line)) (l Line)] -> (Map String Line)
          (if (and l.row (not (mapHas? m l.key))) (mapSet m l.key l) m))
        (mapEmpty) lines)

fn skeletonTexts lines: (List Line) -> (List String)
  (map (fn [(l Line)] -> String l.text) (filter (fn [(l Line)] -> Bool (not l.row)) lines))

fn plainOut text: String -> Out
  (Out :key "" :text text :theirsText "" :suffix "" :conflict false)

fn setSuffix o: Out s: String -> Out
  (with o :suffix s)

fn setText o: Out s: String -> Out
  (with o :text s)

fn setNumberAfter text: String marker: String value: String -> String
  (mt (stringIndexOf text marker)
    ((none) text)
    ((some i) (let [(s (+ i (stringLength marker)))]
      (str (optionOr (stringSlice text 0 s) "") value (sliceFrom text (digitsEnd text s))))))

fn numberAfter text: String marker: String -> Int64
  (mt (stringIndexOf text marker)
    ((none) (- 0 1))
    ((some i) (let [(s (+ i (stringLength marker)))]
      (optionOr (stringToInt64 (optionOr (stringSlice text s (digitsEnd text s)) "")) (- 0 1)))))

fn tokenAfter text: String marker: String -> String
  (mt (stringIndexOf text marker)
    ((none) "")
    ((some i) (let [(s (+ i (stringLength marker)))] (optionOr (stringSlice text s (tokenStop text s)) ""))))

fn derivedMarker mode: String -> String
  (cond ((= mode "metaBaseline") " :plain ") ((= mode "hostValidity") "(:total ") (else ""))

fn derivedLine? o: String t: String mode: String -> Bool
  (let [(marker (derivedMarker mode))]
    (and (not (stringEmpty? marker)) (stringContains? o marker) (stringContains? t marker)
         (= (setNumberAfter o marker "N") (setNumberAfter t marker "N"))))

fn derivedText lines: (List String) mode: String -> String
  (let [(marker (derivedMarker mode))]
    (if (stringEmpty? marker) "" (optionOr (listHead (filter (fn [(l String)] -> Bool (stringContains? l marker)) lines)) "")))

fn derivedBoth? bs: (List String) os: (List String) ts: (List String) mode: String -> Bool
  (let [(b (derivedText bs mode)) (o (derivedText os mode)) (t (derivedText ts mode))]
    (and (not (stringEmpty? o)) (!= o b) (!= t b)))

fn skeletonMerge bs: (List String) os: (List String) ts: (List String) mode: String -> Skel
  (let [(b (stringJoin bs "\n")) (o (stringJoin os "\n")) (t (stringJoin ts "\n"))
        (both (derivedBoth? bs os ts mode))
        (failed (Skel :outs (list) :ok false :recount false))]
    (cond
      ((or (= o t) (= t b)) (Skel :outs (map plainOut os) :ok true :recount both))
      ((= o b) (if (= (listLength ts) (listLength os)) (Skel :outs (map plainOut ts) :ok true :recount both) failed))
      ((and (= (listLength bs) (listLength os)) (= (listLength os) (listLength ts))) (skeletonByLine bs os ts mode (list) both))
      (else failed)))

fn skeletonByLine bs: (List String) os: (List String) ts: (List String) mode: String acc: (List Out) recount: Bool -> Skel
  (mt (listHead os)
    ((none) (Skel :outs (listReverse acc) :ok true :recount recount))
    ((some o)
      (let [(b (optionOr (listHead bs) "")) (t (optionOr (listHead ts) ""))
            (nb (optionOr (listTail bs) (list))) (no (optionOr (listTail os) (list))) (nt (optionOr (listTail ts) (list)))]
        (cond
          ((or (= o t) (= t b)) (skeletonByLine nb no nt mode (cons (plainOut o) acc) recount))
          ((= o b) (skeletonByLine nb no nt mode (cons (plainOut t) acc) recount))
          ((derivedLine? o t mode) (skeletonByLine nb no nt mode (cons (plainOut o) acc) true))
          (else (skeletonByLine nb no nt mode (cons (Out :key "" :text o :theirsText t :suffix "" :conflict true) acc) recount))))))

fn formOf l: (Option Line) -> String
  (mt l ((some x) x.form) (_ ""))

fn resolveBoth o: String t: String mode: String -> (Pair Int64 String)
  (let [(name (cond ((= mode "baseline") " :lines ") ((= mode "metaBaseline") " :plain ") (else "")))
        (on (numberAfter o name)) (tn (numberAfter t name))]
    (cond
      ((or (stringEmpty? name) (!= (tokenAfter o " :lang ") (tokenAfter t " :lang "))) (pair 3 t))
      ((or (< on 0) (< tn 0)) (pair 3 t))
      ((> on tn) (pair 0 o))
      ((> tn on) (pair 1 t))
      (else (pair 3 t))))

fn decide o: String b: (Option Line) t: (Option Line) mode: String -> (Pair Int64 String)
  (let [(bf (formOf b)) (tf (formOf t))]
    (cond
      ((and (some? t) (same? o tf)) (pair 0 o))
      ((and (some? b) (same? o bf)) (if (some? t) (pair 1 tf) (pair 2 "")))
      ((and (some? b) (some? t) (same? tf bf)) (pair 0 o))
      ((none? t) (if (some? b) (pair 3 "") (pair 0 o)))
      (else (resolveBoth o tf mode))))

fn rowOut l: Line form: String conflict: Bool theirs: String -> Out
  (Out :key l.key :text (str l.indent form) :theirsText (if (stringEmpty? theirs) "" (str l.indent theirs))
       :suffix l.suffix :conflict conflict)

fn addSuffix o: Out s: String -> Out
  (if (stringEmpty? (stringTrim s)) o (setSuffix o (str o.suffix (stringTrim s))))

fn walkOurs lines: (List Line) skel: (List Out) bMap: (Map String Line) tMap: (Map String Line) mode: String acc: (List Out) ok: Bool -> Walk
  (mt (listHead lines)
    ((none) (Walk :outs acc :skel skel :ok (and ok (listEmpty? skel))))
    ((some l)
      (let [(tail (optionOr (listTail lines) (list)))]
        (if (not l.row)
          (mt (listHead skel)
            ((none) (Walk :outs acc :skel skel :ok false))
            ((some s) (walkOurs tail (optionOr (listTail skel) (list)) bMap tMap mode (cons s acc) ok)))
          (let [(d (decide l.form (mapGet bMap l.key) (mapGet tMap l.key) mode))
                (action (pairFirst d)) (form (pairSecond d))]
            (cond
              ((= action 0) (walkOurs tail skel bMap tMap mode (cons (rowOut l l.form false "") acc) ok))
              ((= action 1) (walkOurs tail skel bMap tMap mode (cons (rowOut l form false "") acc) ok))
              ((= action 3) (walkOurs tail skel bMap tMap mode (cons (rowOut l l.form true form) acc) ok))
              (else (mt (listHead acc)
                      ((none) (walkOurs tail skel bMap tMap mode acc (and ok (stringEmpty? (stringTrim l.suffix)))))
                      ((some prev) (walkOurs tail skel bMap tMap mode (cons (addSuffix prev l.suffix) (optionOr (listTail acc) (list))) ok))))))))))

fn addPlaced st: Place o: Out -> Place
  (if (stringEmpty? st.anchor)
    (with st :anchor "" :pending (cons o st.pending))
    (with st :after (mapSet st.after st.anchor (cons o (optionOr (mapGet st.after st.anchor) (list))))))

fn placeLine l: Line present: (Map String Bool) oMap: (Map String Line) bMap: (Map String Line) st: Place -> Place
  (let [(k l.key)]
    (cond
      ((not l.row) (with st :anchor "" :pending (list) :ok (and st.ok (listEmpty? st.pending))))
      ((mapHas? present k)
        (with st :anchor k :pending (list) :before (if (listEmpty? st.pending) st.before (mapSet st.before k st.pending))))
      ((mapHas? oMap k) st)
      ((mapHas? bMap k)
        (if (same? l.form (formOf (mapGet bMap k)))
          st
          (addPlaced st (Out :key k :text "" :theirsText (str l.indent l.form) :suffix "" :conflict true))))
      (else (addPlaced st (Out :key k :text (str l.indent l.form) :theirsText "" :suffix "" :conflict false)))))

fn placeTheirs lines: (List Line) present: (Map String Bool) oMap: (Map String Line) bMap: (Map String Line) st: Place -> Place
  (mt (listHead lines)
    ((none) (with st :anchor "" :pending (list) :ok (and st.ok (listEmpty? st.pending))))
    ((some l) (placeTheirs (optionOr (listTail lines) (list)) present oMap bMap (placeLine l present oMap bMap st))))

fn pushAll xs: (List Out) acc: (List Out) -> (List Out)
  (fold (fn [(a (List Out)) (x Out)] -> (List Out) (cons x a)) acc xs)

fn moveSuffix xs: (List Out) s: String -> (List Out)
  (let [(r (listReverse xs))]
    (mt (listHead r)
      ((none) xs)
      ((some last) (listReverse (cons (setSuffix last s) (optionOr (listTail r) (list)))))))

fn assemble outs: (List Out) after: (Map String (List Out)) before: (Map String (List Out)) acc: (List Out) -> (List Out)
  (mt (listHead outs)
    ((none) (listReverse acc))
    ((some o)
      (let [(tail (optionOr (listTail outs) (list)))
            (k o.key)
            (pre (if (stringEmpty? k) (list) (listReverse (optionOr (mapGet before k) (list)))))
            (post (if (stringEmpty? k) (list) (listReverse (optionOr (mapGet after k) (list)))))
            (acc1 (pushAll pre acc))]
        (if (listEmpty? post)
          (assemble tail after before (cons o acc1))
          (assemble tail after before (pushAll (moveSuffix post o.suffix) (cons (setSuffix o "") acc1)))))))

fn shiftAfter outs: (List Out) after: (Map String (List Out)) bMap: (Map String Line) tMap: (Map String Line) cur: String -> (Map String (List Out))
  (mt (listHead outs)
    ((none) after)
    ((some o)
      (let [(tail (optionOr (listTail outs) (list))) (k o.key)]
        (cond
          ((stringEmpty? k) (shiftAfter tail after bMap tMap ""))
          ((and (not (stringEmpty? cur)) (not (mapHas? bMap k)) (not (mapHas? tMap k)) (not (listEmpty? (optionOr (mapGet after cur) (list)))))
            (shiftAfter tail (mapSet (mapSet after k (optionOr (mapGet after cur) (list))) cur (list)) bMap tMap k))
          (else (shiftAfter tail after bMap tMap k))))))

fn recount outs: (List Out) mode: String -> (List Out)
  (let [(rows (filter (fn [(o Out)] -> Bool (not (stringEmpty? o.key))) outs))
        (marker (derivedMarker mode))
        (value (if (= mode "metaBaseline")
                 (fold (fn [(acc Int64) (o Out)] -> Int64 (+ acc (max 0 (numberAfter o.text " :plain ")))) 0 rows)
                 (listLength (filter (fn [(o Out)] -> Bool
                                       (and (stringStartsWith? (stringTrim o.text) "(:f ")
                                            (not (stringContains? o.text ":class negativeFixture")))) rows))))]
    (map (fn [(o Out)] -> Out
           (if (and (stringEmpty? o.key) (stringContains? o.text marker))
             (setText o (setNumberAfter o.text marker (stringFromInt64 value)))
             o)) outs))

fn renderOut o: Out -> String
  (if o.conflict
    (str "<<<<<<< ours\n" o.text o.suffix "\n=======\n" o.theirsText o.suffix "\n>>>>>>> theirs")
    (str o.text o.suffix))

fn balanceOf text: String -> Int64
  (balanceScan text 0 0)

fn balanceScan text: String i: Int64 depth: Int64 -> Int64
  (if (>= i (stringLength text))
    depth
    (let [(c (ch text i))]
      (cond
        ((= c "\"") (let [(e (stringEnd text (+ i 1) false))] (if (< e 0) depth (balanceScan text e depth))))
        ((= c "(") (balanceScan text (+ i 1) (+ depth 1)))
        ((= c ")") (balanceScan text (+ i 1) (- depth 1)))
        (else (balanceScan text (+ i 1) depth)))))

fn withNewline s: String -> String
  (if (or (stringEmpty? s) (stringEndsWith? s "\n")) s (str s "\n"))

fn wholeConflict ours: String theirs: String -> MergeResult
  (MergeResult :text (str "<<<<<<< ours\n" (withNewline ours) "=======\n" (withNewline theirs) ">>>>>>> theirs\n") :conflict true)

fn lineMerge base: String ours: String theirs: String mode: String -> MergeResult
  (let [(bl (parseLines base)) (ol (parseLines ours)) (tl (parseLines theirs))
        (bMap (rowMap bl)) (oMap (rowMap ol)) (tMap (rowMap tl))
        (skel (skeletonMerge (skeletonTexts bl) (skeletonTexts ol) (skeletonTexts tl) mode))]
    (if (not skel.ok)
      (wholeConflict ours theirs)
      (let [(walk (walkOurs ol skel.outs bMap tMap mode (list) true))
            (outs (listReverse walk.outs))
            (present (fold (fn [(m (Map String Bool)) (o Out)] -> (Map String Bool)
                             (if (stringEmpty? o.key) m (mapSet m o.key true))) (mapEmpty) outs))
            (placed (placeTheirs tl present oMap bMap (Place :anchor "" :pending (list) :after (mapEmpty) :before (mapEmpty) :ok true)))]
        (if (not (and walk.ok placed.ok))
          (wholeConflict ours theirs)
          (let [(assembled (assemble outs (shiftAfter outs placed.after bMap tMap "") placed.before (list)))
                (final (if skel.recount (recount assembled mode) assembled))
                (text (stringJoin (map renderOut final) "\n"))
                (conflict (listAny? (fn [(o Out)] -> Bool o.conflict) final))]
            (if (and (not conflict) (!= (balanceOf text) (balanceOf ours)))
              (wholeConflict ours theirs)
              (MergeResult :text text :conflict conflict)))))))

fn mergeRows base: String ours: String theirs: String mode: String -> MergeResult
  (cond
    ((= ours theirs) (MergeResult :text ours :conflict false))
    ((= base ours) (MergeResult :text theirs :conflict false))
    ((= base theirs) (MergeResult :text ours :conflict false))
    (else (lineMerge base ours theirs mode)))

fn ! main args: (List String) -> (Result Int64 String)
  (if (!= (listLength args) 4)
    (err "usage: asl-host run mergeRows.asl BASE OURS THEIRS PATH")
    (let [(basePath (optionOr (listGet args 0) ""))
          (oursPath (optionOr (listGet args 1) ""))
          (theirsPath (optionOr (listGet args 2) ""))
          (path (optionOr (listGet args 3) ""))]
      (mt (fileReadString basePath)
        ((err e) (err e))
        ((ok b) (mt (fileReadString oursPath)
          ((err e) (err e))
          ((ok o) (mt (fileReadString theirsPath)
            ((err e) (err e))
            ((ok t)
              (let [(mode (cond
                      ((stringContains? path "metaBaseline") "metaBaseline")
                      ((stringContains? path "foreignBaseline") "baseline")
                      ((stringContains? path "hostValidity") "hostValidity")
                      (else "rows")))
                    (m (mergeRows b o t mode))]
                (mt (fileWrite oursPath m.text)
                  ((err e) (err e))
                  ((ok _) (ok (if m.conflict 1 0)))))))))))))
