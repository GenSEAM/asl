(module aslAgentBus/ndAsn :x [NDASNFrame ndAsnFrame ndAsnSerialize ndAsnSerializeSingle serializeWireFrame ndAsnDeserialize ndAsnParseLines ndAsnMakeToolcall ndAsnEvalPayload ndAsnDeserializeSingle] :i [(asl-text/escape :a esc)])

(schema NDASNFrame (:f topic Str) (:f seq I64) (:f ts I64) (:f payload Str) (:f meta (Map Str Str)))

(schema DelimDepth (:f depth I64) (:f inStr Bool) (:f esc Bool))

(schema LineAcc (:f items (List Str)) (:f cur Str) (:f depth I64))

fn ndAsnFrame topic: Str seq: I64 ts: I64 payload: Str meta: (Map Str Str) -> NDASNFrame
  (NDASNFrame :topic topic :seq seq :ts ts :payload payload :meta meta)

fn escapeNdAsnStr s: Str -> Str
  (esc/escapeAsnStr s)

fn unescapeNdAsnStr s: Str -> Str
  (esc/unescapeAsnStr s)

fn formatMeta m: (Map Str Str) -> Str
  (let [(keys (mapKeys m))] (if (listEmpty? keys) "()" (let [(entries (map (fn [(k Str)] -> Str (let [(vOpt (mapGet m k))] (let [(v (mt vOpt ((some val) val) (_ "")))] (str "(\"" (escapeNdAsnStr k) "\" \"" (escapeNdAsnStr v) "\")")))) keys))] (str "(" (stringJoin entries " ") ")"))))

fn parseMetaLoop s: Str acc: (Map Str Str) -> (Map Str Str)
  (let [(pairIdx (stringIndexOf s "(\""))] (mt pairIdx ((none) acc) ((some pStart) (let [(afterP (optionOr (stringSlice s (+ pStart 2) (stringLength s)) "")) (kEnd (stringIndexOf afterP "\""))] (mt kEnd ((none) acc) ((some ke) (let [(key (optionOr (stringSlice afterP 0 ke) "")) (afterK (optionOr (stringSlice afterP (+ ke 1) (stringLength afterP)) "")) (vStart (stringIndexOf afterK "\""))] (mt vStart ((none) acc) ((some vs) (let [(afterV (optionOr (stringSlice afterK (+ vs 1) (stringLength afterK)) "")) (vEnd (stringIndexOf afterV "\""))] (mt vEnd ((none) acc) ((some ve) (let [(val (optionOr (stringSlice afterV 0 ve) "")) (rest (optionOr (stringSlice afterV (+ ve 1) (stringLength afterV)) "")) (nextAcc (mapSet acc key val))] (parseMetaLoop rest nextAcc))))))))))))))

fn parseMetaPairs raw: Str -> (Map Str Str)
  (let [(trimmed (stringTrim raw))] (if (or (or (stringEmpty? trimmed) (= trimmed "()")) (= trimmed "[]")) (mapEmpty) (parseMetaLoop trimmed (mapEmpty))))

fn computeDelimDepth s: Str initialDepth: I64 -> I64
  (let [(chars (stringChars s)) (init (DelimDepth :depth initialDepth :inStr false :esc false))] (let [(finalSt (fold (fn [(st DelimDepth) (c Str)] -> DelimDepth (if st.inStr (if st.esc (DelimDepth :depth st.depth :inStr true :esc false) (if (= c "\\") (DelimDepth :depth st.depth :inStr true :esc true) (if (= c "\"") (DelimDepth :depth st.depth :inStr false :esc false) (DelimDepth :depth st.depth :inStr true :esc false)))) (if (= c "\"") (DelimDepth :depth st.depth :inStr true :esc false) (if (= c "(") (DelimDepth :depth (+ st.depth 1) :inStr false :esc false) (if (= c ")") (DelimDepth :depth (- st.depth 1) :inStr false :esc false) (DelimDepth :depth st.depth :inStr false :esc false)))))) init chars))] finalSt.depth))

fn ndAsnParseLines raw: Str -> (List Str)
  (let [(normalized (stringReplace raw "\r" "")) (rawLines (stringSplit normalized "\n")) (init (LineAcc :items (list) :cur "" :depth 0))] (let [(finalAcc (fold (fn [(acc LineAcc) (rawLn Str)] -> LineAcc (let [(trimmed (stringTrim rawLn))] (if (stringEmpty? trimmed) acc (if (stringEmpty? acc.cur) (let [(d (computeDelimDepth trimmed 0))] (if (<= d 0) (LineAcc :items (listAppend acc.items (list trimmed)) :cur "" :depth 0) (LineAcc :items acc.items :cur trimmed :depth d))) (let [(merged (str acc.cur " " trimmed)) (d (computeDelimDepth trimmed acc.depth))] (if (<= d 0) (LineAcc :items (listAppend acc.items (list merged)) :cur "" :depth 0) (LineAcc :items acc.items :cur merged :depth d))))))) init rawLines))] (if (stringEmpty? finalAcc.cur) finalAcc.items (listAppend finalAcc.items (list finalAcc.cur)))))

fn ndAsnSerializeSingle frame: NDASNFrame -> Str
  (let [(top frame.topic) (seqStr (stringFromInt64 frame.seq)) (tsStr (stringFromInt64 frame.ts)) (escPayload (escapeNdAsnStr frame.payload)) (metaStr (formatMeta frame.meta))] (str "(:frame :topic \"" top "\" :seq " seqStr " :ts " tsStr " :payload \"" escPayload "\" :meta " metaStr ")"))

fn serializeWireFrame frame: NDASNFrame -> Str
  (ndAsnSerializeSingle frame)

fn ndAsnSerialize frames: (List NDASNFrame) -> Str
  (if (listEmpty? frames) "" (stringJoin (map (fn [(f NDASNFrame)] -> Str (ndAsnSerializeSingle f)) frames) "\n"))

fn ndAsnDeserializeSingle line: Str -> (Result NDASNFrame Str)
  (let [(t (stringTrim line))] (if (not (and (or (stringStartsWith? t "(:frame ") (stringStartsWith? t "(:nd-asn ")) (stringEndsWith? t ")"))) (err (str "malformed-frame: invalid framing delimiters: " t)) (let [(topIdx (stringIndexOf t ":topic \"")) (seqIdx (stringIndexOf t ":seq ")) (tsIdx (stringIndexOf t ":ts ")) (payIdx (stringIndexOf t ":payload \"")) (metaIdx (stringIndexOf t ":meta "))] (if (or (none? topIdx) (or (none? seqIdx) (or (none? tsIdx) (or (none? payIdx) (none? metaIdx))))) (err (str "malformed-frame: missing required field markers: " t)) (let [(ti (optionOr topIdx 0)) (si (optionOr seqIdx 0)) (tsi (optionOr tsIdx 0)) (pi (optionOr payIdx 0)) (mi (optionOr metaIdx 0))] (let [(topSub (optionOr (stringSlice t (+ ti 8) (stringLength t)) "")) (topEnd (stringIndexOf topSub "\""))] (mt topEnd ((none) (err "malformed-frame: unclosed topic quote")) ((some te) (let [(topic (optionOr (stringSlice topSub 0 te) "")) (seqSub (optionOr (stringSlice t (+ si 5) (stringLength t)) "")) (seqEnd (stringIndexOf seqSub " "))] (mt seqEnd ((none) (err "malformed-frame: missing space after seq")) ((some se) (let [(seqOpt (stringToInt64 (optionOr (stringSlice seqSub 0 se) "")))] (mt seqOpt ((none) (err "malformed-frame: invalid seq integer")) ((some seq) (let [(tsSub (optionOr (stringSlice t (+ tsi 4) (stringLength t)) "")) (tsEnd (stringIndexOf tsSub " "))] (mt tsEnd ((none) (err "malformed-frame: missing space after ts")) ((some tse) (let [(tsOpt (stringToInt64 (optionOr (stringSlice tsSub 0 tse) "")))] (mt tsOpt ((none) (err "malformed-frame: invalid ts integer")) ((some ts) (let [(payStart (+ pi 10)) (payEndIdx (stringIndexOf t "\" :meta "))] (mt payEndIdx ((none) (err "malformed-frame: payload delimiter mismatch")) ((some pei) (let [(escPayload (optionOr (stringSlice t payStart pei) "")) (payload (unescapeNdAsnStr escPayload)) (metaStart (+ mi 6)) (metaEnd (- (stringLength t) 1)) (metaRaw (optionOr (stringSlice t metaStart metaEnd) "()")) (meta (parseMetaPairs metaRaw))] (ok (NDASNFrame :topic topic :seq seq :ts ts :payload payload :meta meta))))))))))))))))))))))))))

fn ndAsnDeserialize raw: Str -> (List (Result NDASNFrame Str))
  (let [(lines (ndAsnParseLines raw))] (map (fn [(line Str)] -> (Result NDASNFrame Str) (ndAsnDeserializeSingle line)) lines))

fn ndAsnMakeToolcall tool: Str col: Str q: Str limit: I64 -> NDASNFrame
  (let [(payload (str "(call! " tool " :col " col " :q " q " :limit " (stringFromInt64 limit) ")"))] (NDASNFrame :topic "toolcall" :seq 1 :ts 0 :payload payload :meta (mapEmpty)))

fn ndAsnEvalPayload frame: NDASNFrame -> (Result Str Str)
  (let [(p (stringTrim frame.payload))] (cond ((stringEmpty? p) (err "empty-payload")) ((not (and (stringStartsWith? p "(") (stringEndsWith? p ")"))) (err (str "invalid-syntax: " p))) ((stringStartsWith? p "(call! ") (let [(inner (optionOr (stringSlice p 7 (- (stringLength p) 1)) "")) (sp (stringIndexOf inner " ")) (tool (mt sp ((some idx) (optionOr (stringSlice inner 0 idx) inner)) ((none) inner)))] (if (stringEmpty? tool) (err "missing-tool-identifier") (ok (str "dispatched:" tool))))) ((stringStartsWith? p "(load! ") (let [(inner (optionOr (stringSlice p 7 (- (stringLength p) 1)) "")) (chunk (stringTrim inner))] (if (stringEmpty? chunk) (err "missing-chunk-identifier") (ok (str "loaded:" chunk))))) ((stringStartsWith? p "(echo ") (let [(inner (optionOr (stringSlice p 6 (- (stringLength p) 1)) ""))] (ok (stringTrim inner)))) (else (ok (str "eval:" p)))))
