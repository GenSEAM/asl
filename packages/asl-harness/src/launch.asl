(module asl-harness/launch
  :x [Asn asnForm asnKw asnSym asnStr asnInt asnFloat
      readAll readOne asnGet asnForms asnDump textOf pyStr pyStrRepr truthy formsOf formOr
      Paths pathsFor runnerDisplay! Layer Attractor Harness Client Loaded loadSources
      Probe factsOf gitState migrateOn RenderOpts render hostPaths fillText
      buildArgv jsonStr absPath pathJoin writePrompt!
      Outcome Ctx freeze mainWith! usageText
      Captured runCapture! whichIn! probe! platform! today! pruneRunDirs! runChild! main mainIn!
      renderAsn renderAsnText renderAsnFor absentPaths writePromptWith! asnPrint asnQuote]
  :i [(asl-proc/runnerBin :a rb) (asl-harness/collect :a col) (asl/packages/asl-cli/src/remoteTarget :a rt)])

enum Asn
  (asnForm items: (List Asn))
  (asnKw name: String)
  (asnSym name: String)
  (asnStr s: String)
  (asnInt text: String)
  (asnFloat text: String)

(schema Frame (:f items (List Asn)) (:f start Int64))

fn slice s: String i: Int64 j: Int64 -> String
  (optionOr (stringSlice s i j) "")

fn tailOf xs: (List T) -> (List T)
  (optionOr (listTail xs) (list))

fn byteAt bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (>= i 0) (< i n)) (bytesGet bs i) -1)

fn isDigitB b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn isWordB b: Int64 -> Bool
  (or (isDigitB b) (or (and (>= b 65) (<= b 90)) (or (and (>= b 97) (<= b 122)) (or (= b 95) (>= b 128)))))

fn cpCount bs: Bytes j: Int64 i: Int64 acc: Int64 -> Int64
  (if (>= j i) acc (cpCount bs (+ j 1) i (if (= (& (bytesGet bs j) 192) 128) acc (+ acc 1))))

fn cpIndex bs: Bytes i: Int64 -> Int64
  (cpCount bs 0 i 0)

fn spaceLen bs: Bytes n: Int64 i: Int64 -> Int64
  (let [(b (byteAt bs n i)) (b1 (byteAt bs n (+ i 1))) (b2 (byteAt bs n (+ i 2)))]
    (cond
      ((or (and (>= b 9) (<= b 13)) (and (>= b 28) (<= b 32))) 1)
      ((and (= b 194) (or (= b1 133) (= b1 160))) 2)
      ((and (= b 225) (and (= b1 154) (= b2 128))) 3)
      ((and (= b 226) (and (= b1 128) (or (and (>= b2 128) (<= b2 138)) (or (= b2 168) (or (= b2 169) (= b2 175)))))) 3)
      ((and (= b 226) (and (= b1 129) (= b2 159))) 3)
      ((and (= b 227) (and (= b1 128) (= b2 128))) 3)
      (else 0)))

fn digitRunAt bs: Bytes n: Int64 i: Int64 prevUs: Bool -> Bool
  (if (>= i n)
    (not prevUs)
    (let [(b (bytesGet bs i))]
      (cond
        ((isDigitB b) (digitRunAt bs n (+ i 1) false))
        ((and (= b 95) (and (> i 0) (not prevUs))) (digitRunAt bs n (+ i 1) true))
        (else false))))

fn digitRun s: String -> Bool
  (let [(bs (stringToBytes s)) (n (bytesLength bs))]
    (and (> n 0) (digitRunAt bs n 0 false)))

fn dropZeros s: String -> String
  (if (and (stringStartsWith? s "0") (> (stringLength s) 1)) (dropZeros (slice s 1 (stringLength s))) s)

fn signSplit tok: String -> (Pair Bool String)
  (if (or (stringStartsWith? tok "-") (stringStartsWith? tok "+"))
    (pair (stringStartsWith? tok "-") (slice tok 1 (stringLength tok)))
    (pair false tok))

fn pyInt tok: String -> (Option String)
  (let [(sp (signSplit tok)) (body (pairSecond sp))]
    (if (digitRun body)
      (let [(digits (dropZeros (stringReplace body "_" "")))]
        (some (if (and (pairFirst sp) (!= digits "0")) (str "-" digits) digits)))
      (none)))

fn mantissaOk m: String -> Bool
  (match (stringIndexOf m ".")
    ((none) (digitRun m))
    ((some i)
      (let [(ip (slice m 0 i)) (fp (slice m (+ i 1) (stringLength m)))]
        (and (not (and (stringEmpty? ip) (stringEmpty? fp)))
             (and (or (stringEmpty? ip) (digitRun ip)) (or (stringEmpty? fp) (digitRun fp)))))))

fn exponentOk e: String -> Bool
  (digitRun (pairSecond (signSplit e)))

fn firstExp s: String -> (Option Int64)
  (let [(a (stringIndexOf s "e")) (b (stringIndexOf s "E"))]
    (match a
      ((none) b)
      ((some i) (match b ((none) a) ((some j) (some (min i j)))))))

fn pyFloat tok: String -> (Option String)
  (let [(sp (signSplit tok)) (neg (pairFirst sp)) (body (pairSecond sp)) (low (stringLower body))]
    (cond
      ((or (= low "inf") (= low "infinity")) (some (if neg "-inf" "inf")))
      ((= low "nan") (some "nan"))
      (else
        (let [(ok (match (firstExp body)
                    ((none) (mantissaOk body))
                    ((some i) (and (mantissaOk (slice body 0 i)) (exponentOk (slice body (+ i 1) (stringLength body)))))))]
          (if ok
            (match (stringToFloat64 (str (if neg "-" "") (stringReplace body "_" "")))
              ((some f) (some (stringFromFloat64 f)))
              ((none) (none)))
            (none))))))

fn atomOf tok: String -> Asn
  (if (and (stringStartsWith? tok ":") (> (stringLength tok) 1))
    (asnKw (slice tok 1 (stringLength tok)))
    (match (pyInt tok)
      ((some t) (asnInt t))
      ((none) (match (pyFloat tok) ((some t) (asnFloat t)) ((none) (asnSym tok))))))

fn emitInto stack: (List Frame) v: Asn -> (List Frame)
  (match (listHead stack)
    ((none) stack)
    ((some f) (cons (Frame :items (cons v f.items) :start f.start) (tailOf stack))))

fn emitOut stack: (List Frame) out: (List Asn) v: Asn -> (List Asn)
  (if (listEmpty? stack) (cons v out) out)

fn lineEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (!= (bytesGet bs i) 10)) (lineEnd bs n (+ i 1)) i)

fn isDelim b: Int64 -> Bool
  (or (= b 40) (or (= b 41) (or (= b 59) (= b 34))))

fn atomEnd bs: Bytes n: Int64 j: Int64 -> Int64
  (if (and (< j n) (and (= (spaceLen bs n j) 0) (not (isDelim (bytesGet bs j))))) (atomEnd bs n (+ j 1)) j)

fn scanStr text: String bs: Bytes n: Int64 open: Int64 j: Int64 pieceStart: Int64 pieces: (List String) -> (Result (Pair String Int64) String)
  (if (>= j n)
    (err (str "unterminated string at byte " (stringFromInt64 (cpIndex bs open))))
    (let [(b (bytesGet bs j))]
      (cond
        ((= b 92)
          (if (>= (+ j 1) n)
            (err (str "dangling escape at byte " (stringFromInt64 (cpIndex bs j))))
            (let [(c (bytesGet bs (+ j 1)))
                  (dec (cond ((= c 110) "\n") ((= c 116) "\t") ((= c 114) "\r") (else (slice text (+ j 1) (+ j 2)))))]
              (scanStr text bs n open (+ j 2) (+ j 2) (cons dec (cons (slice text pieceStart j) pieces))))))
        ((= b 34) (ok (pair (stringJoin (listReverse (cons (slice text pieceStart j) pieces)) "") (+ j 1))))
        (else (scanStr text bs n open (+ j 1) pieceStart pieces)))))

fn readLoop text: String bs: Bytes n: Int64 i: Int64 stack: (List Frame) out: (List Asn) -> (Result (List Asn) String)
  (if (>= i n)
    (match (listHead stack)
      ((some f) (err (str "unclosed ( at byte " (stringFromInt64 (cpIndex bs f.start)))))
      ((none) (ok (listReverse out))))
    (let [(b (bytesGet bs i)) (sp (spaceLen bs n i))]
      (cond
        ((> sp 0) (readLoop text bs n (+ i sp) stack out))
        ((= b 59) (readLoop text bs n (lineEnd bs n i) stack out))
        ((= b 40) (readLoop text bs n (+ i 1) (cons (Frame :items (list) :start i) stack) out))
        ((= b 41)
          (match (listHead stack)
            ((none) (err (str "unmatched ) at byte " (stringFromInt64 (cpIndex bs i)))))
            ((some f)
              (let [(v (asnForm (listReverse f.items))) (rest (tailOf stack))]
                (readLoop text bs n (+ i 1) (emitInto rest v) (emitOut rest out v))))))
        ((= b 34)
          (match (scanStr text bs n i (+ i 1) (+ i 1) (list))
            ((err e) (err e))
            ((ok p)
              (let [(v (asnStr (pairFirst p)))]
                (readLoop text bs n (pairSecond p) (emitInto stack v) (emitOut stack out v))))))
        (else
          (let [(j (atomEnd bs n i)) (v (atomOf (slice text i j)))]
            (readLoop text bs n j (emitInto stack v) (emitOut stack out v)))))))

fn readAll text: String -> (Result (List Asn) String)
  (let [(bs (stringToBytes text))]
    (readLoop text bs (bytesLength bs) 0 (list) (list)))

fn isForm v: Asn -> Bool
  (match v ((asnForm _) true) (_ false))

fn readOne text: String -> (Result Asn String)
  (match (readAll text)
    ((err e) (err e))
    ((ok vs)
      (if (and (= (listLength vs) 1) (isForm (optionOr (listHead vs) (asnSym ""))))
        (ok (optionOr (listHead vs) (asnSym "")))
        (err (str "expected one form, found " (stringFromInt64 (listLength vs)) " values")))))

fn itemsOf v: Asn -> (List Asn)
  (match v ((asnForm xs) xs) (_ (list)))

fn getLoop xs: (List Asn) key: String found: (Option Asn) -> (Option Asn)
  (match (listHead xs)
    ((none) found)
    ((some h)
      (let [(rest (tailOf xs))]
        (match (listHead rest)
          ((none) found)
          ((some v) (getLoop rest key (match h ((asnKw k) (if (= k key) (some v) found)) (_ found))))))))

fn asnGet v: Asn key: String -> (Option Asn)
  (getLoop (itemsOf v) key (none))

fn textOf v: Asn -> (Option String)
  (match v ((asnKw n) (some n)) ((asnSym n) (some n)) ((asnStr s) (some s)) (_ (none)))

fn headIs v: Asn head: String -> Bool
  (match v
    ((asnForm xs) (match (listHead xs) ((some h) (= (textOf h) (some head))) ((none) false)))
    (_ false))

fn asnForms v: Asn head: (Option String) -> (List Asn)
  (filter (fn [(x Asn)] -> Bool (and (isForm x) (match head ((none) true) ((some h) (headIs x h))))) (itemsOf v))

fn asnQuote s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn asnDump v: Asn -> String
  (match v
    ((asnForm xs) (str "(" (stringJoin (map asnDump xs) " ") ")"))
    ((asnKw n) (str ":" n))
    ((asnSym n) (str "s:" n))
    ((asnStr s) (asnQuote s))
    ((asnInt t) (str "i:" t))
    ((asnFloat t) (str "f:" t)))

fn hexDigit d: Int64 -> String
  (slice "0123456789abcdef" d (+ d 1))

fn reprPieces bs: Bytes s: String n: Int64 i: Int64 q: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (let [(b (bytesGet bs i))
          (piece (cond
                   ((= b 92) "\\\\")
                   ((= b q) (str "\\" (slice s i (+ i 1))))
                   ((= b 9) "\\t")
                   ((= b 10) "\\n")
                   ((= b 13) "\\r")
                   ((or (< b 32) (= b 127)) (str "\\x" (hexDigit (/ b 16)) (hexDigit (mod b 16))))
                   (else (slice s i (+ i 1)))))]
      (reprPieces bs s n (+ i 1) q (cons piece acc))))

fn pyStrRepr s: String -> String
  (let [(dq (and (stringContains? s "'") (not (stringContains? s "\"")))) (qs (if dq "\"" "'")) (bs (stringToBytes s))]
    (str qs (stringJoin (reprPieces bs s (bytesLength bs) 0 (if dq 34 39) (list)) "") qs))

fn pyRepr v: Asn -> String
  (match v
    ((asnForm xs) (str "[" (stringJoin (map pyRepr xs) ", ") "]"))
    ((asnKw n) (str ":" n))
    ((asnSym n) n)
    ((asnStr s) (pyStrRepr s))
    ((asnInt t) t)
    ((asnFloat t) t))

fn pyStrV v: Asn -> String
  (match v
    ((asnForm xs) (str "[" (stringJoin (map pyRepr xs) ", ") "]"))
    ((asnKw n) n)
    ((asnSym n) n)
    ((asnStr s) s)
    ((asnInt t) t)
    ((asnFloat t) t))

fn pyStr o: (Option Asn) -> String
  (match o ((none) "None") ((some v) (pyStrV v)))

fn pyListRepr xs: (List String) -> String
  (str "[" (stringJoin (map pyStrRepr xs) ", ") "]")

fn truthy v: Asn -> Bool
  (match v
    ((asnForm xs) (not (listEmpty? xs)))
    ((asnStr s) (not (stringEmpty? s)))
    ((asnInt t) (!= t "0"))
    ((asnFloat t)
      (match (stringToFloat64 t)
        ((some f) (!= f 0.0))
        ((none) true)))
    (_ true))

fn formsOf o: (Option Asn) head: String what: String -> (Result (List Asn) String)
  (match o
    ((none) (ok (list)))
    ((some v)
      (cond
        ((not (truthy v)) (ok (list)))
        ((isForm v) (ok (asnForms v (some head))))
        (else (err (str "launch: " what " is not a list"))))))

fn formOr o: (Option Asn) what: String -> (Result Asn String)
  (match o
    ((none) (ok (asnForm (list))))
    ((some v)
      (cond
        ((not (truthy v)) (ok (asnForm (list))))
        ((isForm v) (ok v))
        (else (err (str "launch: " what " is not a list"))))))

fn pyIter o: (Option Asn) what: String -> (Result (List String) String)
  (match o
    ((none) (ok (list)))
    ((some v)
      (cond
        ((not (truthy v)) (ok (list)))
        ((isForm v) (ok (map pyStrV (itemsOf v))))
        (else (match (textOf v)
                ((some t) (ok (stringChars t)))
                ((none) (err (str "launch: " what " is not iterable"))))))))

fn assocGet xs: (List (Pair String T)) k: String -> (Option T)
  (match (listHead (filter (fn [(p (Pair String T))] -> Bool (= (pairFirst p) k)) xs))
    ((some p) (some (pairSecond p)))
    ((none) (none)))

fn assocSet xs: (List (Pair String T)) k: String v: T -> (List (Pair String T))
  (if (some? (assocGet xs k))
    (map (fn [(p (Pair String T))] -> (Pair String T) (if (= (pairFirst p) k) (pair k v) p)) xs)
    (listAppend xs (list (pair k v))))

fn lookupLast xs: (List (Pair String String)) k: String -> (Option String)
  (assocGet (listReverse xs) k)

(schema Paths (:f harness String) (:f clients String) (:f tools String) (:f host String) (:f harness5 String) (:f terms String))
(schema Layer (:f id String) (:f cond (Option (List String))) (:f text (Option String)) (:f src (Option String)) (:f vol Bool))
(schema Attractor (:f goal String) (:f shadow String))
(schema Harness (:f layers (List Layer)) (:f intro (Result String String)) (:f items (List (Pair String Attractor))) (:f modes (List (Pair String (List String)))))
(schema Client (:f id String) (:f fields (List (Pair String Asn))))
(schema Loaded (:f paths Paths) (:f harness (Result Harness String)) (:f clients (Result (List Client) String)) (:f tools (Result Asn String)))

fn pathsFor root: String host: String -> Paths
  (Paths :harness (str root "/asl/grammar/harness.asn") :clients (str root "/asl/grammar/clients.asn") :tools (str root "/asl/grammar/tools.asn") :host host
         :harness5 (str root "/asl/grammar/harness5.asn") :terms (str root "/asl/grammar/terms.asn"))

fn condList f: Asn lid: String key: String -> (Result (Option (List String)) String)
  (match (asnGet f key)
    ((none) (ok (none)))
    ((some v) (if (isForm v) (ok (some (map pyStrV (itemsOf v)))) (err (str "launch: layer " lid " :" key " must be a list of facts")))))

fn parseLayer f: Asn -> (Result Layer String)
  (let [(lid (pyStr (asnGet f "id"))) (text (asnGet f "text")) (src (asnGet f "from"))]
    (if (or (= (none? text) (none? src)) (and (some? text) (none? (textOf (optionOr text (asnSym ""))))))
      (err (str "launch: layer " lid " needs exactly one of :text \"...\" or :from"))
      (match (condList f lid "when")
        ((err e) (err e))
        ((ok w)
          (match (condList f lid "unless")
            ((err e) (err e))
            ((ok u)
              (let [(c (listAppend (optionOr w (list)) (map (fn [(x String)] -> String (str "!" x)) (optionOr u (list)))))]
                (ok (Layer :id lid :cond (if (listEmpty? c) (none) (some c))
                           :text (match text ((some t) (textOf t)) ((none) (none)))
                           :src (match src ((some s) (some (pyStrV s))) ((none) (none)))
                           :vol (= (pyStr (asnGet f "volatile")) "true"))))))))))

fn parseLayers fs: (List Asn) acc: (List Layer) -> (Result (List Layer) String)
  (match (listHead fs)
    ((none) (ok (listReverse acc)))
    ((some f) (match (parseLayer f) ((err e) (err e)) ((ok l) (parseLayers (tailOf fs) (cons l acc))))))

fn parseItems fs: (List Asn) acc: (List (Pair String Attractor)) -> (List (Pair String Attractor))
  (match (listHead fs)
    ((none) acc)
    ((some a) (parseItems (tailOf fs) (assocSet acc (pyStr (asnGet a "id")) (Attractor :goal (pyStr (asnGet a "goal")) :shadow (pyStr (asnGet a "shadow")))))))

fn parseModes fs: (List Asn) acc: (List (Pair String (List String))) -> (Result (List (Pair String (List String))) String)
  (match (listHead fs)
    ((none) (ok acc))
    ((some m)
      (let [(mid (pyStr (asnGet m "id")))]
        (match (pyIter (asnGet m "attractors") (str "mode " mid " :attractors"))
          ((err e) (err e))
          ((ok ids) (parseModes (tailOf fs) (assocSet acc mid ids)))))))

fn checkModes ms: (List (Pair String (List String))) items: (List (Pair String Attractor)) hpath: String -> (Result Unit String)
  (match (listHead ms)
    ((none) (ok ()))
    ((some m)
      (let [(missing (filter (fn [(i String)] -> Bool (none? (assocGet items i))) (pairSecond m)))]
        (if (listEmpty? missing)
          (checkModes (tailOf ms) items hpath)
          (err (str "launch: mode " (pairFirst m) " names unknown attractors " (pyListRepr missing) " in " hpath))))))

fn introOf att: Asn -> (Result String String)
  (match (asnGet att "intro")
    ((none) (ok ""))
    ((some v) (cond ((not (truthy v)) (ok "")) (else (match (textOf v) ((some t) (ok t)) ((none) (err "launch: :attractors :intro is not a string")))))))

fn parseHarness paths: Paths text: String -> (Result Harness String)
  (let [(hp paths.harness)]
    (match (readOne text)
      ((err e) (err (str "launch: " hp ": " e)))
      ((ok tree)
        (if (not (headIs tree "harness"))
          (err (str "launch: " hp " is not a (:harness ...) form"))
          (match (formsOf (asnGet tree "layers") "layer" (str hp " :layers"))
            ((err e) (err e))
            ((ok lfs)
              (match (parseLayers lfs (list))
                ((err e) (err e))
                ((ok layers)
                  (if (listEmpty? layers)
                    (err (str "launch: " hp " has no :layers"))
                    (match (formOr (asnGet tree "attractors") (str hp " :attractors"))
                      ((err e) (err e))
                      ((ok att)
                        (match (formsOf (asnGet att "items") "attractor" (str hp " :items"))
                          ((err e) (err e))
                          ((ok ifs)
                            (let [(items (parseItems ifs (list)))]
                              (match (formsOf (asnGet att "modes") "mode" (str hp " :modes"))
                                ((err e) (err e))
                                ((ok mfs)
                                  (match (parseModes mfs (list))
                                    ((err e) (err e))
                                    ((ok modes)
                                      (match (checkModes modes items hp)
                                        ((err e) (err e))
                                        ((ok _) (ok (Harness :layers layers :intro (introOf att) :items items :modes modes))))))))))))))))))))))

fn fieldPairs xs: (List Asn) acc: (List (Pair String Asn)) -> (List (Pair String Asn))
  (match (listHead xs)
    ((none) acc)
    ((some k)
      (let [(rest (tailOf xs))]
        (match (listHead rest)
          ((none) acc)
          ((some v) (fieldPairs (tailOf rest) (match k ((asnKw n) (assocSet acc n v)) (_ acc))))))))

fn parseClientList fs: (List Asn) cpath: String acc: (List Client) -> (Result (List Client) String)
  (match (listHead fs)
    ((none) (ok acc))
    ((some f)
      (let [(fields (fieldPairs (tailOf (itemsOf f)) (list)))]
        (match (assocGet fields "id")
          ((none) (err (str "launch: " cpath ": a (:client ...) has no :id")))
          ((some idv)
            (let [(cid (pyStrV idv))
                  (entry (Client :id cid :fields (filter (fn [(p (Pair String Asn))] -> Bool (!= (pairFirst p) "id")) fields)))
                  (known (listAny? (fn [(c Client)] -> Bool (= c.id cid)) acc))]
              (parseClientList (tailOf fs) cpath
                (if known
                  (map (fn [(c Client)] -> Client (if (= c.id cid) entry c)) acc)
                  (listAppend acc (list entry))))))))))

fn parseClients paths: Paths text: String -> (Result (List Client) String)
  (let [(cp paths.clients)]
    (match (readOne text)
      ((err e) (err (str "launch: " cp ": " e)))
      ((ok tree)
        (match (formsOf (asnGet tree "clients") "client" (str cp " :clients"))
          ((err e) (err e))
          ((ok fs) (parseClientList fs cp (list)))))))

fn loadSources paths: Paths harness: String clients: String tools: String -> Loaded
  (let [(cr (parseClients paths clients))
        (hr (match (parseHarness paths harness)
              ((err e) (err e))
              ((ok h) (match cr ((err e) (err e)) ((ok _) (ok h))))))
        (tr (match (readOne tools) ((err e) (err (str "launch: " paths.tools ": " e))) ((ok t) (ok t))))]
    (Loaded :paths paths :harness hr :clients cr :tools tr))

fn findClient clients: (List Client) client: String -> (Option Client)
  (listHead (filter (fn [(c Client)] -> Bool (= c.id client)) clients))

fn clientField clients: (List Client) client: String field: String -> (Option String)
  (match (findClient clients client)
    ((none) (none))
    ((some c) (match (assocGet c.fields field) ((some v) (textOf v)) ((none) (none)))))

(schema Probe (:f root String) (:f branch String) (:f rules Bool) (:f aslSrc Bool) (:f migrate Bool) (:f asl (Option String)) (:f session Bool))

fn factsOf clients: (List Client) client: String mode: String once: Bool p: Probe -> (List (Pair String Bool))
  (let [(git (not (stringEmpty? p.root)))
        (asex (and git p.rules))
        (known (some? (findClient clients client)))]
    (list (pair "git" git) (pair "asex" asex) (pair "foreign" (and git (not asex)))
          (pair "aslProject" (or asex (or (and git p.aslSrc) (and git p.migrate))))
          (pair "shell" (some? (clientField clients client "shell"))) (pair "asl" (some? p.asl)) (pair "session" p.session)
          (pair "implement" (or (= mode "implement") (= mode "grade"))) (pair "distill" (= mode "distill"))
          (pair "agy" (= client "agy")) (pair "codex" (= client "codex")) (pair "once" once)
          (pair "chat" (not known)) (pair "tools" known) (pair "subagent" (some? (clientField clients client "subagent")))))

fn gitState p: Probe -> String
  (if (stringEmpty? p.root) "none" (str p.root " on " (if (stringEmpty? p.branch) "detached HEAD" p.branch)))

fn skipSpaces bs: Bytes n: Int64 i: Int64 -> Int64
  (let [(k (spaceLen bs n i))] (if (> k 0) (skipSpaces bs n (+ i k)) i))

fn migrateAt text: String bs: Bytes n: Int64 from: Int64 -> Bool
  (match (stringIndexOf (slice text from n) ":migrate")
    ((none) false)
    ((some rel)
      (let [(i (+ from (+ rel 8))) (j (skipSpaces bs n i))]
        (if (and (> j i) (and (= (slice text j (+ j 4)) "true") (not (isWordB (byteAt bs n (+ j 4))))))
          true
          (migrateAt text bs n (+ from (+ rel 1)))))))

fn migrateOn text: String -> Bool
  (let [(bs (stringToBytes text))] (migrateAt text bs (bytesLength bs) 0))

fn hostScan text: String bs: Bytes n: Int64 host: String p: Int64 spanStart: Int64 acc: (List String) -> String
  (if (>= p n)
    (stringJoin (listReverse (cons (slice text spanStart n) acc)) "")
    (let [(prev (byteAt bs n (- p 1)))
          (behindOk (and (= (bytesGet bs p) 97) (not (or (isWordB prev) (or (= prev 47) (or (= prev 46) (= prev 45)))))))
          (aheadOk (fn [(q Int64)] -> Bool (let [(c (byteAt bs n q))] (not (or (isWordB c) (= c 45))))))
          (len (cond
                 ((not behindOk) 0)
                 ((and (= (slice text p (+ p 21)) "asl/host/out/asl-host") (aheadOk (+ p 21))) 21)
                 ((and (= (slice text p (+ p 8)) "asl-host") (aheadOk (+ p 8))) 8)
                 (else 0)))]
      (if (> len 0)
        (hostScan text bs n host (+ p len) (+ p len) (cons host (cons (slice text spanStart p) acc)))
        (hostScan text bs n host (+ p 1) spanStart acc))))

fn hostPaths text: String host: String -> String
  (let [(bs (stringToBytes text))] (hostScan text bs (bytesLength bs) host 0 0 (list)))

fn wordEnd bs: Bytes n: Int64 q: Int64 -> Int64
  (if (isWordB (byteAt bs n q)) (wordEnd bs n (+ q 1)) q)

fn fillScan text: String bs: Bytes n: Int64 fill: (List (Pair String String)) p: Int64 spanStart: Int64 acc: (List String) -> String
  (if (>= p n)
    (stringJoin (listReverse (cons (slice text spanStart n) acc)) "")
    (if (!= (bytesGet bs p) 123)
      (fillScan text bs n fill (+ p 1) spanStart acc)
      (let [(q (wordEnd bs n (+ p 1)))]
        (if (and (> q (+ p 1)) (= (byteAt bs n q) 125))
          (let [(name (slice text (+ p 1) q))
                (rep (optionOr (lookupLast fill name) (slice text p (+ q 1))))]
            (fillScan text bs n fill (+ q 1) (+ q 1) (cons rep (cons (slice text spanStart p) acc))))
          (fillScan text bs n fill (+ p 1) spanStart acc)))))

fn fillText text: String fill: (List (Pair String String)) -> String
  (let [(bs (stringToBytes text))] (fillScan text bs (bytesLength bs) fill 0 0 (list)))

fn toolBriefs loaded: Loaded -> (Result String String)
  (match loaded.tools
    ((err e) (err e))
    ((ok tree)
      (match (formsOf (asnGet tree "entries") "op" (str loaded.paths.tools " :entries"))
        ((err e) (err e))
        ((ok ops)
          (ok (stringJoin (fold (fn [(acc (List String)) (op Asn)] -> (List String)
                                  (match (asnGet op "brief") ((some b) (match (textOf b) ((some t) (listAppend acc (list t))) ((none) acc))) ((none) acc)))
                                (list) ops) "; "))))))

fn languageText loaded: Loaded field: String -> (Result String String)
  (let [(tp loaded.paths.tools)]
    (match loaded.tools
      ((err e) (err e))
      ((ok tree)
        (match (formsOf (asnGet tree "topics") "topic" (str tp " :topics"))
          ((err e) (err e))
          ((ok ts)
            (let [(hits (filter (fn [(t Asn)] -> Bool (and (= (pyStr (asnGet t "name")) "language")
                                                          (some? (match (asnGet t field) ((some v) (textOf v)) ((none) (none))))))
                                ts))]
              (match (listHead hits)
                ((some t) (ok (optionOr (match (asnGet t field) ((some v) (textOf v)) ((none) (none))) "")))
                ((none) (err (str "launch: " tp " has no (:topic :name :language :" field " ...)"))))))))))

fn attractorsText h: Harness mode: String hpath: String -> (Result String String)
  (let [(ids (optionOr (assocGet h.modes mode) (list)))]
    (if (listEmpty? ids)
      (err (str "launch: no attractors for mode " mode " in " hpath))
      (match h.intro
        ((err e) (err e))
        ((ok intro)
          (ok (str intro " " (stringJoin (map (fn [(i String)] -> String
                                                (match (assocGet h.items i)
                                                  ((some a) (str i ": " a.goal ", overdone: " a.shadow))
                                                  ((none) (str i ": None, overdone: None"))))
                                              ids) "; ")))))))

fn vendorFills clients: (List Client) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (k (List String))] -> (List (Pair String String))
          (match (clientField clients (optionOr (listHead k) "") (optionOr (listHead (tailOf k)) ""))
            ((some v) (listAppend acc (list (pair (optionOr (listHead (tailOf (tailOf k))) "") v))))
            ((none) acc)))
        (list)
        (list (list "agy" "workerWait" "agyWorkerWait") (list "codex" "outputCut" "codexOutputCut")))

(schema RenderOpts (:f cwd String) (:f client String) (:f mode String) (:f core Bool) (:f promptDir (Option String)) (:f drop (List String)) (:f only (List String)) (:f fills (List (Pair String String))) (:f once Bool) (:f platform String) (:f date String))

fn factOf have: (List (Pair String Bool)) k: String -> Bool
  (optionOr (assocGet have k) false)

fn layerPart loaded: Loaded h: Harness o: RenderOpts have: (List (Pair String Bool)) fill: (List (Pair String String)) l: Layer -> (Result (Option String) String)
  (let [(hp loaded.paths.harness) (lid l.id)
        (skipByList (or (listContains? o.drop lid) (and (not (listEmpty? o.only)) (not (listContains? o.only lid)))))]
    (if skipByList
      (ok (none))
      (let [(c (optionOr l.cond (list)))
            (pos (filter (fn [(w String)] -> Bool (not (stringStartsWith? w "!"))) c))
            (neg (map (fn [(w String)] -> String (slice w 1 (stringLength w))) (filter (fn [(w String)] -> Bool (stringStartsWith? w "!")) c)))
            (unknown (filter (fn [(w String)] -> Bool (none? (assocGet have w))) (listAppend pos neg)))]
        (cond
          ((not (listEmpty? unknown)) (err (str "launch: layer " lid " names unknown facts " (pyListRepr unknown) " in " hp)))
          ((and (not (listEmpty? pos)) (or o.core (not (listAll? (fn [(w String)] -> Bool (factOf have w)) pos)))) (ok (none)))
          ((listAny? (fn [(w String)] -> Bool (factOf have w)) neg) (ok (none)))
          (else
            (match l.src
              ((none) (ok (some (fillText (optionOr l.text "") fill))))
              ((some s)
                (cond
                  ((= s "attractors") (resultMap (attractorsText h o.mode hp) (fn [(t String)] -> (Option String) (some t))))
                  ((= s "language") (resultMap (languageText loaded "text") (fn [(t String)] -> (Option String) (some t))))
                  ((= s "languageTools") (resultMap (languageText loaded "tools") (fn [(t String)] -> (Option String) (some t))))
                  (else (err (str "launch: layer " lid " :from " s " is not a known source")))))))))))

fn renderLayers loaded: Loaded h: Harness o: RenderOpts have: (List (Pair String Bool)) fill: (List (Pair String String)) ls: (List Layer) acc: (List String) -> (Result (List String) String)
  (match (listHead ls)
    ((none) (ok (listReverse acc)))
    ((some l)
      (match (layerPart loaded h o have fill l)
        ((err e) (err e))
        ((ok part) (renderLayers loaded h o have fill (tailOf ls) (match part ((some t) (cons t acc)) ((none) acc)))))))

fn fillList clients: (List Client) client: String o: RenderOpts p: Probe briefs: String -> (List (Pair String String))
  (let [(pd o.promptDir)]
    (listAppend
      (list (pair "cwd" o.cwd) (pair "git" (gitState p)) (pair "platform" o.platform) (pair "date" o.date)
            (pair "shell" (optionOr (clientField clients client "shell") "shell"))
            (pair "asl" (optionOr p.asl "asl"))
            (pair "promptDir" (optionOr pd "the prompt dir"))
            (pair "note" (match pd ((some d) (pathJoin d "note.md")) ((none) "note.md")))
            (pair "aslMore" briefs)
            (pair "subagent" (optionOr (clientField clients client "subagent") "a subagent tool")))
      (listAppend (vendorFills clients) o.fills)))

; (:m :gate launchTest)
fn render loaded: Loaded p: Probe o: RenderOpts -> (Result String String)
  (match loaded.harness
    ((err e) (err e))
    ((ok h)
      (let [(clients (resultOr loaded.clients (list)))
            (client o.client)
            (have (factsOf clients client o.mode o.once p))]
        (match (toolBriefs loaded)
          ((err e) (err e))
          ((ok briefs)
            (let [(fill (fillList clients client o p briefs))
                  (lids (map (fn [(l Layer)] -> String l.id) h.layers))
                  (unknownDrop (filter (fn [(d String)] -> Bool (not (listContains? lids d))) o.drop))
                  (unknownOnly (filter (fn [(d String)] -> Bool (not (listContains? lids d))) o.only))]
              (cond
                ((not (listEmpty? unknownDrop)) (err (str "launch: cannot drop unknown layers " (pyListRepr unknownDrop))))
                ((not (listEmpty? unknownOnly)) (err (str "launch: cannot render unknown layers " (pyListRepr unknownOnly))))
                (else
                  (match (renderLayers loaded h o have fill (filter (fn [(l Layer)] -> Bool (not l.vol)) h.layers) (list))
                    ((err e) (err e))
                    ((ok stable)
                      (match (renderLayers loaded h o have fill (filter (fn [(l Layer)] -> Bool l.vol) h.layers) (list))
                        ((err e) (err e))
                        ((ok tail)
                          (let [(marked (if (and (= client "claude") (not (listEmpty? tail))) (listAppend stable (list (promptBoundary))) stable))]
                            (ok (str (stringJoin (map (fn [(t String)] -> String (hostPaths t loaded.paths.host)) (listAppend marked tail)) "\n") "\n")))))))))))))))

fn layerText loaded: Loaded lid: String -> (Result String String)
  (match loaded.harness
    ((err e) (err e))
    ((ok h)
      (match (listHead (filter (fn [(l Layer)] -> Bool (and (= l.id lid) (some? l.text))) h.layers))
        ((some l) (ok (optionOr l.text "")))
        ((none) (err (str "launch: " loaded.paths.harness " has no :text layer " lid))))))

(schema AxEnv (:f lits (List (Pair String String))) (:f fills (List (Pair String Asn))) (:f fillNames (List String)) (:f rules (List Asn)) (:f absent (List String)) (:f modeBody (List Asn)))
(schema AxLayer (:f id String) (:f whenFacts (List String)) (:f unlessFacts (List String)) (:f fromV (Option Asn)) (:f refV (Option Asn)) (:f body (List Asn)))
(schema TermRow (:f id String) (:f row Asn) (:f defs (List Asn)))

fn asnPrint v: Asn -> String
  (match v
    ((asnForm xs) (str "(" (stringJoin (map asnPrint xs) " ") ")"))
    ((asnKw n) (str ":" n))
    ((asnSym n) n)
    ((asnStr s) (asnQuote s))
    ((asnInt t) t)
    ((asnFloat t) t))

fn kwIs x: Asn name: String -> Bool
  (match x ((asnKw n) (= n name)) (_ false))

fn idOf f: Asn -> String
  (match (asnGet f "id") ((some v) (optionOr (textOf v) "")) ((none) ""))

fn symTexts v: Asn -> (List String)
  (map (fn [(x Asn)] -> String (optionOr (textOf x) "")) (itemsOf v))

fn axLayerLoop xs: (List Asn) acc: AxLayer -> AxLayer
  (match (listHead xs)
    ((none) (with acc :body (listReverse acc.body)))
    ((some x)
      (match x
        ((asnKw k)
          (let [(v (optionOr (listHead (tailOf xs)) (asnForm (list))))
                (skip (tailOf (tailOf xs)))]
            (cond
              ((= k "id") (axLayerLoop skip (with acc :id (optionOr (textOf v) ""))))
              ((= k "when") (axLayerLoop skip (with acc :whenFacts (symTexts v))))
              ((= k "unless") (axLayerLoop skip (with acc :unlessFacts (symTexts v))))
              ((= k "from") (axLayerLoop skip (with acc :fromV (some v))))
              ((= k "ref") (axLayerLoop skip (with acc :refV (some v))))
              (else (axLayerLoop (tailOf xs) acc)))))
        (_ (axLayerLoop (tailOf xs) (with acc :body (cons x acc.body)))))))

fn axLayerOf f: Asn -> AxLayer
  (axLayerLoop (itemsOf f) (AxLayer :id "" :whenFacts (list) :unlessFacts (list) :fromV (none) :refV (none) :body (list)))

fn axSelected l: AxLayer o: RenderOpts have: (List (Pair String Bool)) hpath: String -> (Result Bool String)
  (let [(skipByList (or (listContains? o.drop l.id) (and (not (listEmpty? o.only)) (not (listContains? o.only l.id)))))
        (unknown (filter (fn [(w String)] -> Bool (none? (assocGet have w))) (listAppend l.whenFacts l.unlessFacts)))]
    (cond
      (skipByList (ok false))
      ((not (listEmpty? unknown)) (err (str "launch: layer " l.id " names unknown facts " (pyListRepr unknown) " in " hpath)))
      ((and (not (listEmpty? l.whenFacts)) (or o.core (not (listAll? (fn [(w String)] -> Bool (factOf have w)) l.whenFacts)))) (ok false))
      ((listAny? (fn [(w String)] -> Bool (factOf have w)) l.unlessFacts) (ok false))
      (else (ok true))))

fn axFillForm name: String env: AxEnv -> (Result Asn String)
  (match (assocGet env.fills name)
    ((some v) (ok (asnForm (list (asnKw "fill") (asnSym name) v))))
    ((none) (err (str "launch: no fill value for " name))))

fn axNode v: Asn fillOk: Bool env: AxEnv -> (Result Asn String)
  (match v
    ((asnSym n)
      (match (assocGet env.lits n)
        ((some t) (ok (asnStr t)))
        ((none) (if (and fillOk (listContains? env.fillNames n)) (axFillForm n env) (ok v)))))
    ((asnForm xs) (axForm xs env))
    (_ (ok v)))

fn axAbsentNext xs: (List Asn) env: AxEnv -> Bool
  (match (listGet xs 1) ((some (asnSym n)) (listContains? env.absent n)) (_ false))

fn axArgs xs: (List Asn) i: Int64 stmt: Bool env: AxEnv acc: (List Asn) -> (Result (List Asn) String)
  (match (listHead xs)
    ((none) (ok (listReverse acc)))
    ((some x)
      (if (and (or (kwIs x "from") (kwIs x "lit")) (axAbsentNext xs env))
        (axArgs (tailOf (tailOf xs)) (+ i 2) stmt env acc)
        (match (axNode x (and stmt (>= i 2)) env)
          ((err e) (err e))
          ((ok y) (axArgs (tailOf xs) (+ i 1) stmt env (cons y acc)))))))

fn axForm xs: (List Asn) env: AxEnv -> (Result Asn String)
  (let [(head (optionOr (listHead xs) (asnSym "")))
        (stmt (match head ((asnKw _) true) (_ false)))]
    (if (and (= (listLength xs) 2) (kwIs head "fill"))
      (axFillForm (optionOr (match (listGet xs 1) ((some x) (textOf x)) ((none) (none))) "") env)
      (match (axArgs xs 0 stmt env (list))
        ((err e) (err e))
        ((ok ys) (ok (asnForm ys))))))

fn axBody ss: (List Asn) env: AxEnv acc: (List Asn) -> (Result (List Asn) String)
  (match (listHead ss)
    ((none) (ok (listReverse acc)))
    ((some s)
      (match (axNode s false env)
        ((err e) (err e))
        ((ok t) (axBody (tailOf ss) env (cons t acc))))))

fn fromIs l: AxLayer name: String -> Bool
  (match l.fromV ((some (asnSym n)) (= n name)) (_ false))

fn axLayerOut l: AxLayer env: AxEnv -> (Result Asn String)
  (match (axBody (if (fromIs l "clientRules") env.rules (if (fromIs l "taskKind") env.modeBody l.body)) env (list))
    ((err e) (err e))
    ((ok body)
      (ok (asnForm (listAppend (list (asnKw "layer") (asnKw "id") (asnSym l.id))
                     (listAppend (match l.fromV ((some v) (if (or (fromIs l "clientRules") (fromIs l "taskKind")) (list) (list (asnKw "from") v))) ((none) (list)))
                       (listAppend (match l.refV ((some v) (list (asnKw "ref") v)) ((none) (list))) body)))))))

fn axLayers fs: (List Asn) o: RenderOpts have: (List (Pair String Bool)) hpath: String env: AxEnv acc: (List Asn) -> (Result (List Asn) String)
  (match (listHead fs)
    ((none) (ok (listReverse acc)))
    ((some f)
      (let [(l (axLayerOf f))]
        (match (axSelected l o have hpath)
          ((err e) (err e))
          ((ok on)
            (if (and on (not (and (fromIs l "clientRules") (listEmpty? env.rules))))
              (match (axLayerOut l env)
                ((err e) (err e))
                ((ok out) (axLayers (tailOf fs) o have hpath env (cons out acc))))
              (axLayers (tailOf fs) o have hpath env acc)))))))

fn axRefs v: Asn -> (List String)
  (match v
    ((asnSym n) (list n))
    ((asnForm xs)
      (listAppend (match (listHead xs) ((some h) (match h ((asnKw n) (list n)) (_ (list)))) ((none) (list)))
                  (fold (fn [(acc (List String)) (x Asn)] -> (List String) (match x ((asnKw _) acc) (_ (listAppend acc (axRefs x))))) (list) xs)))
    (_ (list)))

fn termRows terms: Asn -> (List TermRow)
  (map (fn [(t Asn)] -> TermRow
         (TermRow :id (idOf t) :row t :defs (match (asnGet t "def") ((some d) (itemsOf d)) ((none) (list)))))
       (asnForms (optionOr (asnGet terms "items") (asnForm (list))) (some "term")))

fn dropKeyPairs xs: (List Asn) keys: (List String) acc: (List Asn) -> (List Asn)
  (match (listHead xs)
    ((none) (listReverse acc))
    ((some x)
      (match x
        ((asnKw k) (if (listContains? keys k) (dropKeyPairs (tailOf (tailOf xs)) keys acc) (dropKeyPairs (tailOf xs) keys (cons x acc))))
        (_ (dropKeyPairs (tailOf xs) keys (cons x acc))))))

fn flatDef d: Asn -> (List Asn)
  (match d ((asnForm xs) xs) (_ (list d)))

fn attractorForm rows: (List TermRow) id: String -> (Result Asn String)
  (match (listHead (filter (fn [(r TermRow)] -> Bool (= r.id id)) rows))
    ((none) (err (str "launch: attractor " id " is not a term")))
    ((some r) (ok (asnForm (cons (asnKw "attractor") (cons (asnSym id) (fold (fn [(acc (List Asn)) (d Asn)] -> (List Asn) (listAppend acc (flatDef d))) (list) r.defs)))))))

fn attractorForms rows: (List TermRow) ids: (List String) acc: (List Asn) -> (Result (List Asn) String)
  (match (listHead ids)
    ((none) (ok (listReverse acc)))
    ((some id)
      (match (attractorForm rows id)
        ((err e) (err e))
        ((ok f) (attractorForms rows (tailOf ids) (cons f acc))))))

fn attractorBody terms: Asn mode: String -> (Result (List Asn) String)
  (let [(rows (termRows terms))]
    (match (listHead (filter (fn [(r TermRow)] -> Bool (= r.id mode)) rows))
      ((none) (err (str "launch: mode " mode " is not a term")))
      ((some m)
        (let [(ids (fold (fn [(acc (List String)) (d Asn)] -> (List String) (if (headIs d "has") (match (listGet (itemsOf d) 1) ((some v) (listAppend acc (symTexts v))) ((none) acc)) acc)) (list) m.defs))]
          (if (listEmpty? ids)
            (err (str "launch: mode " mode " has no attractors"))
            (match (attractorForms rows ids (list))
              ((err e) (err e))
              ((ok fs) (ok (list (asnForm (cons (asnKw "mode") (cons (asnSym mode) fs))))))))))))

fn axFills fill: (List (Pair String String)) more: Asn -> (List (Pair String Asn))
  (let [(base (fold (fn [(acc (List (Pair String Asn))) (p (Pair String String))] -> (List (Pair String Asn)) (assocSet acc (pairFirst p) (asnStr (pairSecond p)))) (list) fill))
        (withTool (assocSet base "subagentTool" (optionOr (assocGet base "subagent") (asnStr "a subagent tool"))))]
    (axAlias (assocSet withTool "aslMore" more)))

fn axAlias m: (List (Pair String Asn)) -> (List (Pair String Asn))
  (fold (fn [(acc (List (Pair String Asn))) (p (Pair String String))] -> (List (Pair String Asn))
          (match (assocGet acc (pairFirst p)) ((some v) (assocSet acc (pairSecond p) v)) ((none) acc)))
        m (list (pair "codexOutputCut" "outputCut") (pair "agyWorkerWait" "waitLimit")))

fn glossaryKeep -> (List String)
  (list "mention" "use" "resolution" "done" "claimed" "exact" "generalization" "scope")

fn glossaryOf terms: Asn used: (List Asn) -> (Option Asn)
  (let [(rows (termRows terms))
        (ids (fold (fn [(acc (List String)) (x Asn)] -> (List String) (listAppend acc (axRefs x))) (list) used))
        (gl (filter (fn [(r TermRow)] -> Bool (and (listContains? ids r.id) (and (listContains? (glossaryKeep) r.id) (not (listEmpty? r.defs))))) rows))]
    (if (listEmpty? gl)
      (none)
      (some (asnForm (cons (asnKw "glossary") (map (fn [(r TermRow)] -> Asn (asnForm (dropKeyPairs (itemsOf r.row) (list "src") (list)))) gl))))))

fn renderAsn h5: Asn terms: Asn o: RenderOpts have: (List (Pair String Bool)) fill: (List (Pair String String)) more: Asn rules: (List Asn) absent: (List String) host: String hpath: String -> (Result String String)
  (match (formsOf (asnGet h5 "literals") "literal" (str hpath " :literals"))
    ((err e) (err e))
    ((ok lfs)
      (match (formsOf (asnGet h5 "static") "layer" (str hpath " :static"))
        ((err e) (err e))
        ((ok sfs)
          (match (formsOf (asnGet h5 "volatile") "layer" (str hpath " :volatile"))
            ((err e) (err e))
            ((ok vfs)
              (let [(lits (map (fn [(f Asn)] -> (Pair String String) (pair (idOf f) (optionOr (match (asnGet f "text") ((some v) (textOf v)) ((none) (none))) ""))) lfs))
                    (names (match (asnGet h5 "fills") ((some v) (symTexts v)) ((none) (list))))
                    (env0 (AxEnv :lits lits :fills (axFills fill more) :fillNames names :rules rules :absent absent :modeBody (list)))
                    (lids (map idOf (listAppend sfs vfs)))
                    (unknownDrop (filter (fn [(d String)] -> Bool (not (listContains? lids d))) o.drop))
                    (unknownOnly (filter (fn [(d String)] -> Bool (not (listContains? lids d))) o.only))]
                (match (attractorBody terms o.mode)
                  ((err e) (err e))
                  ((ok mb)
                (let [(env (with env0 :modeBody mb))]
                (cond
                  ((not (listEmpty? unknownDrop)) (err (str "launch: cannot drop unknown layers " (pyListRepr unknownDrop))))
                  ((not (listEmpty? unknownOnly)) (err (str "launch: cannot render unknown layers " (pyListRepr unknownOnly))))
                  (else
                    (match (axLayers sfs o have hpath env (list))
                      ((err e) (err e))
                      ((ok stable)
                        (match (axLayers vfs o have hpath env (list))
                          ((err e) (err e))
                          ((ok tail)
                            (let [(gloss (glossaryOf terms (listAppend stable tail)))
                                  (head (listAppend stable (match gloss ((some g) (list g)) ((none) (list)))))
                                  (marked (if (and (= o.client "claude") (not (listEmpty? tail))) (listAppend (map asnPrint head) (list (promptBoundary))) (map asnPrint head)))]
                              (ok (hostPaths (str (stringJoin (listAppend marked (map asnPrint tail)) "\n") "\n") host)))))))))))))))))))

fn toolOps loaded: Loaded -> (Result Asn String)
  (match loaded.tools
    ((err e) (err e))
    ((ok tree)
      (match (formsOf (asnGet tree "entries") "op" (str loaded.paths.tools " :entries"))
        ((err e) (err e))
        ((ok ops)
          (ok (asnStr (stringJoin (fold (fn [(acc (List String)) (op Asn)] -> (List String)
                               (match (asnGet op "brief")
                                 ((none) acc)
                                 ((some _) (match (listGet (itemsOf op) 1)
                                             ((none) acc)
                                             ((some n) (match (textOf n) ((some t) (listAppend acc (list t))) ((none) acc)))))))
                             (list) ops) " ")))))))

fn renderAsnText loaded: Loaded p: Probe o: RenderOpts harnessText: String termsText: String absent: (List String) -> (Result String String)
  (match (readOne harnessText)
    ((err e) (err (str "launch: " loaded.paths.harness5 ": " e)))
    ((ok h5)
      (match (readOne termsText)
        ((err e) (err (str "launch: " loaded.paths.terms ": " e)))
        ((ok terms)
          (if (not (and (headIs h5 "harness") (headIs terms "terms")))
            (err (str "launch: " loaded.paths.harness5 " and " loaded.paths.terms " must be (:harness ...) and (:terms ...) forms"))
            (match (toolOps loaded)
              ((err e) (err e))
              ((ok more)
                (let [(clients (resultOr loaded.clients (list)))
                      (have (factsOf clients o.client o.mode o.once p))
                      (fill (fillList clients o.client o p ""))]
                  (renderAsn h5 terms o have fill more (match (findClient clients o.client) ((some c) (match (assocGet c.fields "rules") ((some v) (itemsOf v)) ((none) (list)))) ((none) (list))) absent loaded.paths.host loaded.paths.harness5)))))))))

fn ! renderAsnFor loaded: Loaded p: Probe o: RenderOpts -> (Result String String)
  (match (readSource loaded.paths.harness5)
    ((err e) (err e))
    ((ok ht)
      (match (readSource loaded.paths.terms)
        ((err e) (err e))
        ((ok tt) (renderAsnText loaded p o ht tt (absentPaths ht (if (stringEmpty? p.root) o.cwd p.root)))))))

fn ! absentPaths h5Text: String root: String -> (List String)
  (match (readOne h5Text)
    ((err _) (list))
    ((ok h5)
      (let [(lits (asnForms (optionOr (asnGet h5 "literals") (asnForm (list))) (some "literal")))
            (missing (fn [(f Asn)] -> Bool
                       (and (= (litField f "kind") "path")
                            (not (fileExists? (pathJoin root (litField f "text")))))))]
        (map idOf (filter missing lits)))))

fn litField f: Asn key: String -> String
  (optionOr (match (asnGet f key) ((some v) (textOf v)) ((none) (none))) "")

fn pathJoin a: String b: String -> String
  (cond
    ((stringStartsWith? b "/") b)
    ((or (stringEmpty? a) (stringEndsWith? a "/")) (str a b))
    (else (str a "/" b)))

fn normComps cs: (List String) initial: Int64 acc: (List String) -> (List String)
  (match (listHead cs)
    ((none) (listReverse acc))
    ((some c)
      (cond
        ((or (stringEmpty? c) (= c ".")) (normComps (tailOf cs) initial acc))
        ((or (!= c "..") (or (and (= initial 0) (listEmpty? acc)) (= (listHead acc) (some ".."))))
          (normComps (tailOf cs) initial (cons c acc)))
        ((not (listEmpty? acc)) (normComps (tailOf cs) initial (tailOf acc)))
        (else (normComps (tailOf cs) initial acc)))))

fn normPath p: String -> String
  (let [(initial (cond
                   ((not (stringStartsWith? p "/")) 0)
                   ((and (stringStartsWith? p "//") (not (stringStartsWith? p "///"))) 2)
                   (else 1)))
        (body (stringJoin (normComps (stringSplit p "/") initial (list)) "/"))
        (full (str (stringRepeat "/" initial) body))]
    (if (stringEmpty? full) "." full))

fn absPath p: String base: String -> String
  (normPath (if (stringStartsWith? p "/") p (pathJoin base p)))

fn hex4 cp: Int64 -> String
  (str (hexDigit (mod (/ cp 4096) 16)) (hexDigit (mod (/ cp 256) 16)) (hexDigit (mod (/ cp 16) 16)) (hexDigit (mod cp 16)))

fn utf8Len b: Int64 -> Int64
  (cond ((< b 224) 2) ((< b 240) 3) (else 4))

fn utf8Cp bs: Bytes i: Int64 k: Int64 -> Int64
  (let [(b (bytesGet bs i))
        (lead (cond ((= k 2) (& b 31)) ((= k 3) (& b 15)) (else (& b 7))))]
    (fold (fn [(acc Int64) (j Int64)] -> Int64 (+ (* acc 64) (& (bytesGet bs (+ i j)) 63))) lead (range 1 k)))

fn jsonPieces s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (let [(b (bytesGet bs i))]
      (if (< b 128)
        (jsonPieces s bs n (+ i 1)
          (cons (cond
                  ((= b 34) "\\\"")
                  ((= b 92) "\\\\")
                  ((= b 10) "\\n")
                  ((= b 13) "\\r")
                  ((= b 9) "\\t")
                  ((= b 8) "\\b")
                  ((= b 12) "\\f")
                  ((or (< b 32) (= b 127)) (str "\\u" (hex4 b)))
                  (else (slice s i (+ i 1))))
                acc))
        (let [(k (min (utf8Len b) (- n i))) (cp (utf8Cp bs i k))]
          (jsonPieces s bs n (+ i k)
            (cons (if (>= cp 65536)
                    (let [(v (- cp 65536))] (str "\\u" (hex4 (+ 55296 (/ v 1024))) "\\u" (hex4 (+ 56320 (mod v 1024)))))
                    (str "\\u" (hex4 cp)))
                  acc))))))

fn jsonStr s: String -> String
  (let [(bs (stringToBytes s))] (str "\"" (stringJoin (jsonPieces s bs (bytesLength bs) 0 (list)) "") "\""))

fn splitWsLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (if (> i start) (cons (slice s start i) acc) acc))
    (let [(k (spaceLen bs n i))]
      (if (> k 0)
        (splitWsLoop s bs n (+ i k) (+ i k) (if (> i start) (cons (slice s start i) acc) acc))
        (splitWsLoop s bs n (+ i 1) start acc))))

fn splitWs s: String -> (List String)
  (let [(bs (stringToBytes s))] (splitWsLoop s bs (bytesLength bs) 0 0 (list)))

fn promptBoundary -> String
  "__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__"
fn claudeSkillOff -> String
  "{\"skillOverrides\":{\"asl-toolbelt\":\"off\"},\"includeGitInstructions\":false,\"attribution\":{\"commit\":\"\",\"pr\":\"\"}}"
fn codexSkillOff -> String
  "skills.config=[{name=\"asl-toolbelt\",enabled=false}]"
fn agyAgent -> String
  "asl"

fn claudeArgv clients: (List Client) cpath: String exe: String promptPath: String lean: Bool coord: Bool shellOnly: Bool -> (Result (List String) String)
  (let [(head (list exe "--system-prompt-file" promptPath "--settings" (claudeSkillOff)))]
    (cond
      (shellOnly
        (if (or lean coord)
          (err "launch: --shell-only replaces --lean and --coord")
          (match (clientField clients "claude" "shell")
            ((none) (err (str "launch: no :shell for claude in " cpath)))
            ((some sh) (ok (listAppend head (list "--tools" sh "--strict-mcp-config" "--disable-slash-commands")))))))
      (lean
        (let [(tools (optionOr (clientField clients "claude" "lean") ""))]
          (if (stringEmpty? tools)
            (err (str "launch: no :lean tool list for claude in " cpath))
            (if coord
              (let [(extraTools (optionOr (clientField clients "claude" "coord") ""))]
                (if (stringEmpty? extraTools)
                  (err (str "launch: no :coord tool list for claude in " cpath))
                  (ok (listAppend head (list "--tools" (str tools "," extraTools) "--strict-mcp-config" "--disable-slash-commands")))))
              (ok (listAppend head (list "--tools" tools "--strict-mcp-config" "--disable-slash-commands")))))))
      (else (ok head))))

; (:m :gate launchTest)
fn buildArgv clients: (List Client) cpath: String client: String exe: (Option String) promptPath: String extraDir: String lean: Bool extra: (List String) coord: Bool cwd: String base: String ask: Bool shellOnly: Bool -> (Result (List String) String)
  (match exe
    ((none) (err (str "launch: " client " not found on PATH")))
    ((some x)
      (let [(sub (and (= client "codex") (match (listHead extra) ((some a) (or (= a "exec") (or (= a "e") (= a "review")))) ((none) false))))
            (rest (if sub (tailOf extra) extra))
            (built (cond
                     ((= client "claude") (claudeArgv clients cpath x promptPath lean coord shellOnly))
                     ((= client "codex")
                       (let [(mode (optionOr (clientField clients "codex" "agentMode") ""))]
                         (ok (listAppend (listAppend (cons x (if sub (list (optionOr (listHead extra) "")) (list)))
                                                     (list "-c" (str "model_instructions_file=" promptPath) "-c" (codexSkillOff)))
                                         (if (stringEmpty? mode) (list) (list "-c" (str "features.multi_agent_v2.multi_agent_mode_hint_text=" (jsonStr mode))))))))
                     (else (ok (list x "--agent" (agyAgent) "--add-dir" extraDir "--add-dir" (absPath (if (stringEmpty? cwd) base cwd) base))))))]
        (match built
          ((err e) (err e))
          ((ok argv)
            (cond
              ((and shellOnly (= client "codex")) (err "launch: --shell-only is not available for codex (its built-in tools cannot be removed)"))
              ((and lean (!= client "claude")) (err "launch: --lean applies to claude only"))
              ((and coord (not lean)) (err "launch: --coord adds peer-session tools to --lean; without --lean claude keeps all its tools"))
              (else
                (let [(auto0 (if ask (list) (splitWs (optionOr (clientField clients client "auto") ""))))
                      (auto (if (and (= client "codex") (= (listGet argv 1) (some "exec"))) (list) auto0))]
                  (ok (listAppend argv (listAppend (filter (fn [(a String)] -> Bool (not (listContains? rest a))) auto) rest)))))))))))

fn writeAll! fd: Int64 s: String -> (Result Unit String)
  (if (stringEmpty? s)
    (ok ())
    (match (fdWrite fd s)
      ((err e) (err e))
      ((ok k) (writeAll! fd (slice s k (stringLength s))))))

fn ! mkdirs dir: String -> (Result Unit String)
  (match (dirCreate dir) ((ok _) (ok ())) ((err e) (err (str "launch: cannot create " dir ": " e))))

fn ! writeFile path: String text: String -> (Result Unit String)
  (match (fileWrite path text) ((ok _) (ok ())) ((err e) (err (str "launch: cannot write " path ": " e))))

fn toolLines tools: (List String) -> String
  (stringJoin (map (fn [(t String)] -> String (str "  - " t "\n")) tools) "")

fn clientTools clients: (List Client) -> (List String)
  (match (clientField clients "agy" "tools")
    ((none) (list))
    ((some t) (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (map stringTrim (stringSplit t ",")))))

fn workerDescription -> String
  "runs one independent subtask in its own context (a survey, an audit, a search, a fix over the paths it is given, or a check) and reports its conclusion; several run at once, which pays when the parts are independent and each needs many reads or commands that would crowd this context, and a quick targeted lookup is cheaper done here; a follow-up to a worker's part goes to that worker by its conversation id with send_message"
fn workerReport -> String
  "this agent is a worker: its report to the main agent is its only output, it lists every file it changed, and it edits only the paths its task names"

fn stripLayer loaded: Loaded prompt: String lid: String subagent: (Option String) -> (Result String String)
  (match (layerText loaded lid)
    ((err e) (err e))
    ((ok t)
      (if (and (none? subagent) (stringContains? t "{subagent}"))
        (err (str "launch: agy has no :subagent in " loaded.paths.clients))
        (let [(filled (fillText t (match subagent ((some s) (list (pair "subagent" s))) ((none) (list)))))]
          (ok (stringReplace prompt (str (hostPaths filled loaded.paths.host) "\n") ""))))))

fn workerPrompt loaded: Loaded clients: (List Client) prompt: String runDir: String -> (Result String String)
  (let [(sub (clientField clients "agy" "subagent"))]
    (match (stripLayer loaded prompt "delegate" sub)
      ((err e) (err e))
      ((ok p1)
        (match (stripLayer loaded p1 "agyOnce" sub)
          ((err e) (err e))
          ((ok p2)
            (let [(note (pathJoin runDir "note.md"))]
              (ok (stringReplace (str p2 (workerReport) "\n")
                                 (str "this session's working note is " note)
                                 (str "the main agent's working note, which a worker leaves alone, is " note)))))))))

fn ! writeWorker loaded: Loaded clients: (List Client) prompt: String runDir: String agentsDir: String tools: (List String) override: (Option String) -> (Result String String)
  (let [(worker (pathJoin agentsDir (str (agyAgent) "-worker.md")))
        (head (str "---\nname: " (agyAgent) "-worker\ndescription: " (workerDescription) "\nmainAgent: false\nsubagent: true\ninheritCustomizations: false\ninheritMcp: false\ntools:\n"
                   (toolLines (filter (fn [(t String)] -> Bool (not (or (= t "invoke_subagent") (= t "manage_subagents")))) tools)) "---\n\n"))]
    (match (match override ((some t) (ok t)) ((none) (workerPrompt loaded clients prompt runDir)))
      ((err e) (match (writeFile worker head) ((err e2) (err e2)) ((ok _) (err e))))
      ((ok wp) (match (writeFile worker (str head wp)) ((err e) (err e)) ((ok _) (ok (str "agents:\n  - " worker "\n")))))))

fn ! writeAgy loaded: Loaded clients: (List Client) prompt: String runDir: String bare: Bool shellOnly: Bool override: (Option String) -> (Result (Pair String String) String)
  (let [(agentsDir (pathJoin runDir (str ".agents/plugins/" (agyAgent) "/agents")))
        (pluginDir (pathJoin runDir (str ".agents/plugins/" (agyAgent))))]
    (match (mkdirs agentsDir)
      ((err e) (err e))
      ((ok _)
        (match (writeFile (pathJoin pluginDir "plugin.json") (str "{\"name\": \"" (agyAgent) "\"}\n"))
          ((err e) (err e))
          ((ok _)
            (let [(shellTool (clientField clients "agy" "shell"))
                  (tools (if shellOnly (match shellTool ((some s) (list s)) ((none) (list ""))) (clientTools clients)))]
              (if (or (listEmpty? tools) (stringEmpty? (optionOr (listHead tools) "")))
                (err (str "launch: no :tools for agy in " loaded.paths.clients "; without it agy gets no run_command or edit tools"))
                (match (if (listContains? tools "invoke_subagent") (writeWorker loaded clients prompt runDir agentsDir tools override) (ok ""))
                  ((err e) (err e))
                  ((ok declared)
                    (let [(notePath (pathJoin runDir "note.md"))
                          (path (pathJoin agentsDir (str (agyAgent) ".md")))]
                      (match (if (fileExists? notePath) (ok ()) (writeFile notePath ""))
                        ((err e) (err e))
                        ((ok _)
                          (match (writeFile path (str "---\nname: " (agyAgent) "\ndescription: asl harness\nmainAgent: true\nsubagent: false\ninheritCustomizations: false\ninheritMcp: false\n"
                                                   (if bare "excludeDefaultComponents: true\n" "") declared "tools:\n" (toolLines tools) "---\n\n" prompt))
                            ((err e) (err e))
                            ((ok _) (ok (pair path runDir))))))))))))))))

fn ! writePrompt! loaded: Loaded client: String prompt: String runDir: String bare: Bool shellOnly: Bool -> (Result (Pair String String) String)
  (writePromptWith! loaded client prompt runDir bare shellOnly (none))

fn ! writePromptWith! loaded: Loaded client: String prompt: String runDir: String bare: Bool shellOnly: Bool override: (Option String) -> (Result (Pair String String) String)
  (let [(clients (resultOr loaded.clients (list)))]
    (match (mkdirs runDir)
      ((err e) (err e))
      ((ok _)
        (if (= client "agy")
          (writeAgy loaded clients prompt runDir bare shellOnly override)
          (let [(path (pathJoin runDir (str client ".md")))]
            (match (writeFile path prompt) ((err e) (err e)) ((ok _) (ok (pair path "")))))))))

fn usageText -> String
  "asl launch: start claude, codex or agy with the asl harness as the system prompt.\n\nThe prompt is rendered from asl/grammar/harness.asn: its layers in order, each layer with :when only\nwhere its facts hold for this client and workspace, and the attractors of the mode, so the client\nneeds no toolbelt skill. Usage:\n  asl launch <claude|codex|agy> [--lean [--coord]] [--mode scout|implement|grade|distill] [--core]\n            [--bare] [--shell-only] [--ask] [--format prose|asn] [--dry-run] [--print-prompt] [--prompt-only] [-- client args...]\n--lean (claude only) also narrows the tool set to the :lean list, drops MCP servers and skills;\n--coord adds the :coord tools (see and message peer sessions, about 2.4k tokens);\n--core renders only the layers without :when (no asl knowledge, no conditional layers);\n--ask keeps the client's permission prompts instead of its :auto mode (clients.asn);\n--bare (agy only) drops agy's default components too (workspace map, injected context);\n--shell-only (claude, agy) leaves the client its shell tool alone, so reads and edits go through the shell or asl;\n--prompt-only writes the rendered prompt and returns its path, freeze digest and requested client argv without launching;\n--format asn renders asl/grammar/harness5.asn as ASN forms with a glossary of the terms it uses (default prose; not passed to the client);\nASL_LAUNCH_DROP removes one harness layer, ASL_LAUNCH_FILL_ASL substitutes the asl command path,\nASL_LAUNCH_ONCE omits the memory layer, and ASL_LAUNCH_PROMPT_DIR selects the prompt output directory."

fn launchClients -> (List String)
  (list "claude" "codex" "agy")
fn launchOptions -> (List String)
  (list "--lean" "--coord" "--core" "--bare" "--shell-only" "--ask" "--dry-run" "--print-prompt" "--prompt-only")

(schema Outcome (:f exit Int64) (:f out String) (:f errText String) (:f action String) (:f argv (List String)) (:f launched String) (:f runDir String) (:f digest String) (:f cwd String))
(schema Plan (:f client String) (:f mode String) (:f format String) (:f codexMode String) (:f rest (List String)) (:f extra (List String)) (:f promptOnly Bool))
(schema Ctx (:f cwd String) (:f runDir String) (:f probe Probe) (:f exes (List (Pair String String))) (:f platform String) (:f date String) (:f fills (List (Pair String String))))

fn stop code: Int64 msg: String -> Outcome
  (Outcome :exit code :out "" :errText msg :action "none" :argv (list) :launched "" :runDir "" :digest "" :cwd "")

fn usageOutcome args: (List String) -> (Option Outcome)
  (match (listHead args)
    ((none) (some (stop 2 (str (usageText) "\n"))))
    ((some c) (if (listContains? (launchClients) c) (none) (some (stop 2 (str (usageText) "\n"))))))

fn splitDashes xs: (List String) -> (Pair (List String) (List String))
  (match (listIndexOf xs "--")
    ((none) (pair xs (list)))
    ((some i) (pair (listTake xs i) (listDrop xs (+ i 1)))))

fn withoutAt xs: (List String) i: Int64 k: Int64 -> (List String)
  (listAppend (listTake xs i) (listDrop xs (+ i k)))

fn valuePick rest0: (List String) flag: String allowed: (List String) dflt: String -> (Result (Pair String (List String)) Outcome)
  (let [(bad (stop 2 (str "launch: " flag " takes " (stringJoin allowed " or ") "\n")))]
    (match (listIndexOf rest0 flag)
      ((none) (ok (pair dflt rest0)))
      ((some i)
        (match (listGet rest0 (+ i 1))
          ((some f) (if (listContains? allowed f) (ok (pair f (withoutAt rest0 i 2))) (err bad)))
          ((none) (err bad))))))

fn appendArgv argv: (List String) prompt: String -> (List String)
  (map (fn [(a String)] -> String (if (stringStartsWith? a "model_instructions_file=") (str "developer_instructions=" (jsonStr prompt)) a)) argv)

fn parseArgs loaded: Loaded args: (List String) -> (Result Plan Outcome)
  (match (usageOutcome args)
    ((some o) (err o))
    ((none)
      (let [(client (optionOr (listHead args) ""))
            (sp (splitDashes (tailOf args)))
            (rest0 (pairFirst sp))
            (extra (pairSecond sp))
            (modePick (match (listIndexOf rest0 "--mode")
                        ((none) (ok (pair "implement" rest0)))
                        ((some i)
                          (match loaded.harness
                            ((err e) (err (stop 1 (str e "\n"))))
                            ((ok h)
                              (let [(known (listSort (map (fn [(m (Pair String (List String)))] -> String (pairFirst m)) h.modes)))
                                    (arg (listGet rest0 (+ i 1)))]
                                (match arg
                                  ((some m) (if (listContains? known m) (ok (pair m (withoutAt rest0 i 2)))
                                              (err (stop 2 (str "launch: --mode takes one of " (stringJoin known ", ") " (the :modes of harness.asn)\n")))))
                                  ((none) (err (stop 2 (str "launch: --mode takes one of " (stringJoin known ", ") " (the :modes of harness.asn)\n")))))))))))]
        (match modePick
          ((err o) (err o))
          ((ok mp)
           (match (valuePick (pairSecond mp) "--format" (list "prose" "asn") "prose")
            ((err o) (err o))
            ((ok fp)
            (match (valuePick (pairSecond fp) "--codex-mode" (list "replace" "append") "replace")
             ((err o) (err o))
             ((ok cp)
            (let [(rest0 (pairSecond cp))
                  (rest (filter (fn [(a String)] -> Bool (listContains? (launchOptions) a)) rest0))
                  (passthrough (filter (fn [(a String)] -> Bool (not (listContains? (launchOptions) a))) rest0))]
              (cond
                ((listContains? passthrough "--mode") (err (stop 2 "launch: unknown option --mode\n")))
                ((and (listContains? rest "--bare") (!= client "agy")) (err (stop 2 "launch: --bare applies to agy only\n")))
                ((and (!= (pairFirst cp) "replace") (!= client "codex")) (err (stop 2 "launch: --codex-mode applies to codex only\n")))
                (else (ok (Plan :client client :mode (pairFirst mp) :format (pairFirst fp) :codexMode (pairFirst cp) :rest rest :extra (listAppend passthrough extra) :promptOnly (listContains? rest "--prompt-only")))))))))))))))

fn cpLength s: String -> Int64
  (let [(bs (stringToBytes s))] (cpIndex bs (bytesLength bs)))

fn dryRunLine client: String lean: Bool path: String prompt: String argv: (List String) -> String
  (str "(:launch :client " client " :lean " (if lean "true" "false") " :prompt " (asnQuote path) " :promptChars " (stringFromInt64 (cpLength prompt))
       " :argv (" (stringJoin (map asnQuote argv) " ") "))\n")

fn ! freeze loaded: Loaded -> (Result String String)
  (match (fileReadString loaded.paths.harness)
    ((err e) (err e))
    ((ok h)
      (match (fileReadString loaded.paths.clients)
        ((err e) (err e))
        ((ok c)
          (match (fileReadString loaded.paths.tools)
            ((err e) (err e))
            ((ok t) (ok (optionOr (stringSlice (bytesSha256 (stringToBytes (str h c t))) 0 8) ""))))))))

fn promptOnlyLine path: String extraDir: String digest: String argv: (List String) -> String
  (str "(:promptOnly :path " (asnQuote path) " :extraDir " (asnQuote extraDir) " :freeze " (asnQuote digest)
       " :argv (" (stringJoin (map asnQuote argv) " ") "))\n")

fn ! promptArgv loaded: Loaded ctx: Ctx plan: Plan written: (Pair String String) prompt: String -> (Result (List String) String)
  (if (listEmpty? plan.extra)
    (ok (list))
    (resultMap (buildArgv (resultOr loaded.clients (list)) loaded.paths.clients plan.client (assocGet ctx.exes plan.client) (pairFirst written)
               (pairSecond written) (listContains? plan.rest "--lean") plan.extra (listContains? plan.rest "--coord") "" ctx.cwd
               (listContains? plan.rest "--ask") (listContains? plan.rest "--shell-only")) (fn [(a (List String))] -> (List String) (if (= plan.codexMode "append") (appendArgv a prompt) a))))

fn quiet out: String -> Outcome
  (Outcome :exit 0 :out out :errText "" :action "none" :argv (list) :launched "" :runDir "" :digest "" :cwd "")

fn workerReportAsn -> String
  "(:layer :id workerReport (:is finalMessage report) (:keeps writer ownedPaths))\n"

fn ! freezeAsn loaded: Loaded -> (Result String String)
  (match (fileReadString loaded.paths.harness5)
    ((err e) (err e))
    ((ok h)
      (match (fileReadString loaded.paths.terms)
        ((err e) (err e))
        ((ok m)
          (match (fileReadString loaded.paths.clients)
            ((err e) (err e))
            ((ok c)
              (match (fileReadString loaded.paths.tools)
                ((err e) (err e))
                ((ok t) (ok (optionOr (stringSlice (bytesSha256 (stringToBytes (str h m c t))) 0 8) ""))))))))))

fn ! workerAsn loaded: Loaded ctx: Ctx opts: RenderOpts -> (Result (Option String) String)
  (if (!= opts.client "agy")
    (ok (none))
    (match (renderAsnFor loaded ctx.probe (with opts :drop (listAppend opts.drop (list "delegate" "agyOnce"))))
      ((err e) (err e))
      ((ok t) (ok (some (str t (workerReportAsn)))))))

; (:m :ref REMOTE-TARGET :do "when the cwd workspace has a remote .asl/target.asn the prompt ends with one line naming NODE:wt/UNIT and that asl forms, test and check are the only view of that tree; appended last so the cached prefix stays byte-stable, and a malformed profile is reported on stderr and adds nothing")
fn ! withTarget! cwd: String rendered: (Result String String) -> (Result String String)
  (match rendered
    ((err e) (err e))
    ((ok prompt)
      (match (rt/findProfile! cwd)
        ((ok (some t)) (ok (str prompt (rt/promptLine t) "\n")))
        ((ok (none)) (ok prompt))
        ((err e) (do (eprintln (str "launch: " e)) (ok prompt))))))

fn ! runPlan loaded: Loaded ctx: Ctx plan: Plan -> Outcome
  (let [(client plan.client) (rest plan.rest) (extra plan.extra)
        (has (fn [(f String)] -> Bool (listContains? rest f)))
        (once (or (listAny? (fn [(a String)] -> Bool (or (= a "-p") (= a "--print"))) extra)
                  (and (= client "codex") (or (= (listHead extra) (some "exec")) (= (listHead extra) (some "e"))))))
        (asn (= plan.format "asn"))
        (drop (match (envGet "ASL_LAUNCH_DROP") ((some lid) (list lid)) ((none) (list))))
        (aslFill (envGet "ASL_LAUNCH_FILL_ASL"))
        (fills (match aslFill ((some a) (cons (pair "asl" a) ctx.fills)) ((none) ctx.fills)))
        (promptDir (optionOr (envGet "ASL_LAUNCH_PROMPT_DIR") ctx.runDir))
        (opts (RenderOpts :cwd ctx.cwd :client client :mode plan.mode :core (has "--core") :promptDir (some promptDir)
                          :drop drop :only (list) :fills fills :once (or once (= (optionOr (envGet "ASL_LAUNCH_ONCE") "") "true")) :platform ctx.platform :date ctx.date))]
    (match (withTarget! ctx.cwd (if asn (renderAsnFor loaded ctx.probe opts) (render loaded ctx.probe opts)))
      ((err e) (stop 1 (str e "\n")))
      ((ok prompt)
        (if (has "--print-prompt")
          (quiet prompt)
          (match (if asn (workerAsn loaded ctx opts) (ok (none)))
            ((err e) (stop 1 (str e "\n")))
            ((ok worker)
              (match (writePromptWith! loaded client prompt promptDir (has "--bare") (has "--shell-only") worker)
                ((err e) (stop 1 (str e "\n")))
                ((ok written)
                  (if plan.promptOnly
                    (match (if asn (freezeAsn loaded) (freeze loaded))
                      ((err e) (stop 1 (str e "\n")))
                      ((ok digest)
                        (match (promptArgv loaded ctx plan written prompt)
                          ((err e) (stop 1 (str e "\n")))
                          ((ok argv) (quiet (promptOnlyLine (pairFirst written) (pairSecond written) digest argv))))))
                    (match (buildArgv (resultOr loaded.clients (list)) loaded.paths.clients client (assocGet ctx.exes client) (pairFirst written)
                                 (pairSecond written) (has "--lean") extra (has "--coord") "" ctx.cwd (has "--ask") (has "--shell-only"))
                      ((err e) (stop 1 (str e "\n")))
                      ((ok argv0)
                        (let [(argv (if (= plan.codexMode "append") (appendArgv argv0 prompt) argv0))]
                        (if (has "--dry-run")
                          (quiet (dryRunLine client (has "--lean") (pairFirst written) prompt argv))
                          (Outcome :exit 0 :out "" :errText "" :action (if once "child" "exec") :argv argv :launched client
                                   :runDir promptDir :digest (bytesSha256 (stringToBytes prompt)) :cwd ctx.cwd))))))))))))))

; (:m :gate launchTest)
fn ! mainWith! loaded: Loaded ctx: Ctx args: (List String) -> Outcome
  (match (parseArgs loaded args)
    ((err o) o)
    ((ok plan) (runPlan loaded ctx plan)))

(schema Captured (:f code Int64) (:f out String) (:f errText String))
(schema Pump (:f inOpen Bool) (:f outOpen Bool) (:f errOpen Bool) (:f out String) (:f errText String) (:f tailOut String) (:f tailErr String) (:f empty Bool))

fn noOutput -> String
  "run ended with no output"

fn tailKeep s: String -> String
  (let [(n (stringLength s)) (k (- (stringLength (noOutput)) 1))]
    (if (> n k) (slice s (- n k) n) s))

fn pollSet sp: SpawnedProc pm: Pump -> (List (Pair Int64 Int64))
  (listAppend (if pm.inOpen (list (pair 0 1)) (list)) (listAppend (if pm.outOpen (list (pair sp.stdout 1)) (list)) (if pm.errOpen (list (pair sp.stderr 1)) (list))))

fn readyOn ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn ! stepFd sp: SpawnedProc pm: Pump isOut: Bool relay: Bool -> (Result Pump String)
  (let [(fd (if isOut sp.stdout sp.stderr))]
    (match (fdRead fd 65536)
      ((err e) (if (= e "wouldBlock") (ok pm) (err (str "read: " e))))
      ((ok chunk)
        (if (stringEmpty? chunk)
          (match (fdClose fd)
            ((err e) (err (str "close: " e)))
            ((ok _) (ok (with pm :outOpen (if isOut false pm.outOpen) :errOpen (if isOut pm.errOpen false)))))
          (match (if relay (writeAll! (if isOut 1 2) chunk) (ok ()))
            ((err e) (err (str "write: " e)))
            ((ok _)
              (let [(seen (str (if isOut pm.tailOut pm.tailErr) chunk))]
                (ok (with pm :out (if (or relay (not isOut)) pm.out (str pm.out chunk)) :errText (if (or relay isOut) pm.errText (str pm.errText chunk)) :tailOut (if isOut (tailKeep seen) pm.tailOut) :tailErr (if isOut pm.tailErr (tailKeep seen)) :empty (or pm.empty (stringContains? seen (noOutput))))))))))))

fn ! closeIn sp: SpawnedProc pm: Pump -> (Result Pump String)
  (match (fdClose sp.stdin)
    ((err e) (err (str "close stdin: " e)))
    ((ok _) (ok (with pm :inOpen false))))

fn ! stepIn sp: SpawnedProc pm: Pump -> (Result Pump String)
  (match (fdRead 0 4096)
    ((err e) (if (= e "wouldBlock") (ok pm) (closeIn sp pm)))
    ((ok chunk)
      (if (stringEmpty? chunk)
        (closeIn sp pm)
        (match (writeAll! sp.stdin chunk)
          ((err _) (closeIn sp pm))
          ((ok _) (ok pm))))))

fn ! pump sp: SpawnedProc pm: Pump relay: Bool -> (Result Pump String)
  (if (not (or pm.outOpen pm.errOpen))
    (ok pm)
    (match (fdPoll (pollSet sp pm) -1)
      ((err e) (err (str "poll: " e)))
      ((ok ready)
        (match (if (and pm.outOpen (readyOn ready sp.stdout)) (stepFd sp pm true relay) (ok pm))
          ((err e) (err e))
          ((ok p1)
            (match (if (and p1.errOpen (readyOn ready sp.stderr)) (stepFd sp p1 false relay) (ok p1))
              ((err e) (err e))
              ((ok p2)
                (match (if (and p2.inOpen (readyOn ready 0)) (stepIn sp p2) (ok p2))
                  ((err e) (err e))
                  ((ok p3) (pump sp p3 relay))))))))))

fn posixExitCode raw: Int64 -> Int64
  (if (< raw 0) (+ 128 (- 0 raw)) raw)

fn ! reap sp: SpawnedProc -> (Result Int64 String)
  (match (procWaitPid sp.pid false)
    ((err e) (err (str "wait: " e)))
    ((ok c) (match c ((some k) (ok (posixExitCode k))) ((none) (err "wait: no exit status")))))

fn ! abandon sp: SpawnedProc e: String -> (Result (Pair Int64 Pump) String)
  (match (procKill (- 0 sp.pid) "SIGKILL")
    ((err k) (err (str e "; kill: " k)))
    ((ok _) (match (reap sp) ((err w) (err (str e "; " w))) ((ok _) (err e)))))

fn ! spawnPump argv: (List String) cwd: (Option String) env: (Option (List String)) relay: Bool -> (Result (Pair Int64 Pump) String)
  (match (procSpawnv argv cwd env)
    ((err e) (err (if (= e "notFound") (str (optionOr (listHead argv) "") " not found on PATH") (str "cannot start " (optionOr (listHead argv) "") ": " e))))
    ((ok sp)
      (match (if relay (ok ()) (fdClose sp.stdin))
        ((err e) (abandon sp (str "close stdin: " e)))
        ((ok _)
          (match (pump sp (Pump :inOpen relay :outOpen true :errOpen true :out "" :errText "" :tailOut "" :tailErr "" :empty false) relay)
            ((err e) (abandon sp e))
            ((ok pm)
              (match (if pm.inOpen (closeIn sp pm) (ok pm))
                ((err e) (abandon sp e))
                ((ok pc) (match (reap sp) ((err e) (err e)) ((ok k) (ok (pair k pc))))))))))))

fn ! runCapture! argv: (List String) cwd: (Option String) env: (Option (List String)) -> (Result Captured String)
  (match (spawnPump argv cwd env false)
    ((err e) (err e))
    ((ok r) (ok (Captured :code (pairFirst r) :out (pairSecond r).out :errText (pairSecond r).errText))))

; (:m :gate launchTest)
fn ! runChild! argv: (List String) env: (List String) -> Int64
  (match (spawnPump argv (none) (some env) true)
    ((err e) (do (writeAll! 2 (str "launch: " e "\n")) 1))
    ((ok r)
      (if (pairSecond r).empty
        (do (writeAll! 2 "launch: agy run ended with no output\n") 1)
        (pairFirst r))))

fn ! accessOk path: String -> Bool
  (match (fileStat path)
    ((err _) false)
    ((ok st) (and (not st.isDir) (!= (& st.mode 73) 0))))

fn ! whichDirs dirs: (List String) seen: (List String) name: String -> (Option String)
  (match (listHead dirs)
    ((none) (none))
    ((some d)
      (if (listContains? seen d)
        (whichDirs (tailOf dirs) seen name)
        (let [(cand (pathJoin d name))]
          (if (accessOk cand) (some cand) (whichDirs (tailOf dirs) (cons d seen) name))))))

fn ! whichIn! pathVar: (Option String) name: String -> (Option String)
  (if (stringContains? name "/")
    (if (accessOk name) (some name) (none))
    (let [(p (optionOr pathVar "/bin:/usr/bin"))]
      (if (stringEmpty? p) (none) (whichDirs (stringSplit p ":") (list) name))))

fn ! gitOut args: (List String) cwd: String -> (Result Captured String)
  (runCapture! (cons "git" args) (some cwd) (none))

fn ! probe! cwd: String -> (Result Probe String)
  (match (gitOut (list "rev-parse" "--show-toplevel") cwd)
    ((err e) (err (str "launch: " e)))
    ((ok top)
      (let [(root (if (= top.code 0) (stringTrim top.out) ""))
            (asl (whichIn! (envGet "PATH") "asl"))
            (session (not (stringEmpty? (optionOr (envGet "ASL_SESSION") ""))))]
        (if (stringEmpty? root)
          (ok (Probe :root "" :branch "" :rules false :aslSrc false :migrate false :asl asl :session session))
          (match (gitOut (list "branch" "--show-current") cwd)
            ((err e) (err (str "launch: " e)))
            ((ok br)
              (match (gitOut (list "ls-files" "--" "*.asl") root)
                ((err e) (err (str "launch: " e)))
                ((ok ls)
                  (let [(rules (match (fileStat (pathJoin root "asl/grammar/rules.asn")) ((ok st) st.isFile) ((err _) false)))
                        (cfg (pathJoin root ".asl.config.asn"))
                        (cfgFile (match (fileStat cfg) ((ok st) st.isFile) ((err _) false)))]
                    (match (if cfgFile (match (fileReadString cfg) ((ok t) (ok (migrateOn t))) ((err e) (err (str "launch: cannot read " cfg ": " e)))) (ok false))
                      ((err e) (err e))
                      ((ok migrate)
                        (ok (Probe :root root :branch (stringTrim br.out) :rules rules :aslSrc (not (stringEmpty? (stringTrim ls.out)))
                                   :migrate migrate :asl asl :session session)))))))))))))

fn ! toolLine argv: (List String) -> (Result String String)
  (match (runCapture! argv (none) (none))
    ((err e) (err (str "launch: " e)))
    ((ok c) (if (= c.code 0) (ok (stringTrim c.out)) (err (str "launch: " (stringJoin argv " ") " exited " (stringFromInt64 c.code) ": " (stringTrim c.errText))))))

fn ! platform! -> (Result String String)
  (toolLine (list "uname" "-s" "-r" "-m"))

fn ! today! -> (Result String String)
  (toolLine (list "date" "+%Y-%m-%d"))

fn allDigits s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [(c String)] -> Bool (isDigitB (charCode c))) (stringChars s)))

fn lastDash s: String i: Int64 -> (Option Int64)
  (if (< i 0) (none) (if (= (slice s i (+ i 1)) "-") (some i) (lastDash s (- i 1))))

fn ! keepReceipt? dir: String -> Bool
  (match (fileStat (pathJoin dir "run.asn"))
    ((err _) false)
    ((ok st) (> st.mtime (- (/ (nowNs) 1000000000) 604800))))

fn startLine client: String startedAt: Int64 cwd: String digest: String -> String
  (str "(:launchStart :client " client " :startedAt " (stringFromInt64 startedAt) " :cwd " (asnQuote cwd) " :promptDigest " (asnQuote digest) ")\n")

fn intOf o: (Option Asn) -> Int64
  (match o ((some (asnInt n)) (optionOr (stringToInt64 n) 0)) (_ 0))

fn ! collectStart! home: String dir: String startPath: String -> Unit
  (match (fileReadString startPath)
    ((err _) ())
    ((ok t)
      (match (readOne t)
        ((err e) (do (writeAll! 2 (str "launch: sweep: " startPath ": " e "\n")) ()))
        ((ok v)
          (match (col/collect! (pyStr (asnGet v "client")) home dir (intOf (asnGet v "startedAt")) (pyStr (asnGet v "cwd")) -1 (pyStr (asnGet v "promptDigest")))
            ((err e) (do (writeAll! 2 (str "launch: sweep: " e "\n")) ()))
            ((ok _) ()))))))

fn ! sweepOne! home: String runRoot: String name: String -> Unit
  (match (lastDash name (- (stringLength name) 1))
    ((none) ())
    ((some i)
      (let [(client (slice name 0 i)) (pid (slice name (+ i 1) (stringLength name)))
            (dir (pathJoin runRoot name))]
        (if (or (not (and (listContains? (launchClients) client) (allDigits pid)))
                (or (fileExists? (pathJoin dir "run.asn")) (not (fileExists? (pathJoin dir "start.asn")))))
          ()
          (match (runCapture! (list "ps" "-p" pid "-o" "pid=") (none) (none))
            ((err _) ())
            ((ok c) (if (= c.code 0) () (collectStart! home dir (pathJoin dir "start.asn")))))))))

fn ! sweepRuns! home: String runRoot: String -> Unit
  (match (dirList runRoot)
    ((err _) ())
    ((ok names) (do (map (fn [(n String)] -> Unit (sweepOne! home runRoot n)) names) ())))

fn ! pruneOne runRoot: String name: String -> (Result Unit String)
  (match (lastDash name (- (stringLength name) 1))
    ((none) (ok ()))
    ((some i)
      (let [(client (slice name 0 i)) (pid (slice name (+ i 1) (stringLength name)))]
        (if (not (and (listContains? (launchClients) client) (allDigits pid)))
          (ok ())
          (match (runCapture! (list "ps" "-p" pid "-o" "pid=") (none) (none))
            ((err e) (err (str "launch: " e " (needed to prune " runRoot ")")))
            ((ok c)
              (if (or (= c.code 0) (keepReceipt? (pathJoin runRoot name)))
                (ok ())
                (match (pathRemove (pathJoin runRoot name))
                  ((ok _) (ok ()))
                  ((err e) (do (writeAll! 2 (str "launch: cannot prune " (pathJoin runRoot name) ": " e "\n")) (ok ())))))))))))

fn ! pruneList runRoot: String names: (List String) -> (Result Unit String)
  (match (listHead names)
    ((none) (ok ()))
    ((some n) (match (pruneOne runRoot n) ((err e) (err e)) ((ok _) (pruneList runRoot (tailOf names))))))

fn ! pruneRunDirs! runRoot: String -> (Result Unit String)
  (match (fileStat runRoot)
    ((err _) (ok ()))
    ((ok st)
      (if (not st.isDir)
        (ok ())
        (match (dirList runRoot)
          ((err e) (err (str "launch: cannot list " runRoot ": " e)))
          ((ok names) (pruneList runRoot names))))))

fn envKey row: String -> String
  (match (stringIndexOf row "=") ((some i) (slice row 0 i)) ((none) row))

fn ! launchedEnv client: String -> (List String)
  (listAppend (filter (fn [(r String)] -> Bool (and (!= (envKey r) "ASL_LAUNCHED") (!= (envKey r) "ASL_LEASE_PID"))) (envList))
    (list (str "ASL_LAUNCHED=" client)
          (str "ASL_LEASE_PID=" (optionOr (envGet "ASL_LEASE_PID") (stringFromInt64 (procSelf))))))

fn ! readSource path: String -> (Result String String)
  (match (fileReadString path) ((ok t) (ok t)) ((err e) (err (str "launch: cannot read " path ": " e))))

fn ! runnerDisplay! root: String -> String
  (rb/runnerDisplay! root)

fn ! loadRoot root: String -> (Result Loaded String)
  (let [(paths (pathsFor root (runnerDisplay! root)))]
    (match (readSource paths.harness)
      ((err e) (err e))
      ((ok h)
        (match (readSource paths.clients)
          ((err e) (err e))
          ((ok c)
            (match (readSource paths.tools)
              ((err e) (err e))
              ((ok t) (ok (loadSources paths h c t)))))))))

fn ! gatherCtx client: String -> (Result Ctx String)
  (match (envGet "HOME")
    ((none) (err "launch: HOME is not set"))
    ((some home)
      (let [(runRoot (pathJoin home ".asl/run/harness"))]
        (match (do (sweepRuns! home runRoot) (pruneRunDirs! runRoot))
          ((err e) (err e))
          ((ok _)
            (match (realPath ".")
              ((err e) (err (str "launch: cannot resolve the working directory: " e)))
              ((ok cwd)
                (match (probe! cwd)
                  ((err e) (err e))
                  ((ok p)
                    (match (platform!)
                      ((err e) (err e))
                      ((ok plat)
                        (match (today!)
                          ((err e) (err e))
                          ((ok day)
                            (let [(exe (whichIn! (envGet "PATH") client))]
                              (ok (Ctx :cwd cwd :runDir (pathJoin runRoot (str client "-" (stringFromInt64 (procSelf)))) :probe p
                                       :exes (match exe ((some x) (list (pair client x))) ((none) (list))) :platform plat :date day :fills (list)))))))))))))))))

fn ! collectAfter! o: Outcome startedAt: Int64 exit: Int64 -> Unit
  (match (envGet "HOME")
    ((none) (do (writeAll! 2 "launch: collect: HOME is not set\n") ()))
    ((some home)
      (match (col/collect! o.launched home o.runDir startedAt o.cwd exit o.digest)
        ((err e) (do (writeAll! 2 (str "launch: collect: " e "\n")) ()))
        ((ok _) ()))))

fn ! runCollected! o: Outcome -> Int64
  (let [(startedAt (/ (nowNs) 1000000000))
        (code (runChild! o.argv (launchedEnv o.launched)))]
    (do (collectAfter! o startedAt code) code))

fn ! writeStart! o: Outcome -> Unit
  (if (stringEmpty? o.runDir)
    ()
    (do (fileWrite (pathJoin o.runDir "start.asn") (startLine o.launched (/ (nowNs) 1000000000) o.cwd o.digest)) ()))

fn ! act o: Outcome -> Int64
  (cond
    ((= o.action "exec")
      (match (do (writeStart! o) (procExecv o.argv (some (launchedEnv o.launched))))
        ((ok _) 0)
        ((err e) (match (writeAll! 2 (str "launch: cannot exec " (optionOr (listHead o.argv) "") ": " e "\n")) ((ok _) 1) ((err _) 1)))))
    ((= o.action "child") (runCollected! o))
    (else o.exit))

fn ! finish o: Outcome -> Int64
  (match (writeAll! 1 o.out)
    ((err _) 120)
    ((ok _) (match (writeAll! 2 o.errText) ((err _) 120) ((ok _) (act o)))))

fn ! main args: (List String) -> (Result Int64 String)
  (match (usageOutcome args)
    ((some o) (ok (finish o)))
    ((none)
      (match (envGet "ASL_ROOT")
        ((none) (ok (finish (stop 1 "launch: ASL_ROOT is not set; bin/asl launch sets it to the repository root\n"))))
        ((some root) (mainIn! root args)))))

fn ! mainIn! root: String args: (List String) -> (Result Int64 String)
  (match (usageOutcome args)
    ((some o) (ok (finish o)))
    ((none)
      (match (loadRoot root)
        ((err e) (ok (finish (stop 1 (str e "\n")))))
        ((ok loaded)
          (match (parseArgs loaded args)
            ((err o) (ok (finish o)))
            ((ok plan)
              (match (gatherCtx plan.client)
                ((err e) (ok (finish (stop 1 (str e "\n")))))
                ((ok ctx) (ok (finish (runPlan loaded ctx plan)))))))))))
