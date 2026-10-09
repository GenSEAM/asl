(module aslGateway/config
  :x [AsnScalar
      scalarBool
      scalarInt
      scalarFloat
      scalarStr
      scalarToString
      GatewayParams
      emptyGatewayParams
      mergeParams
      GatewayRoute
      GatewayProfile
      GatewayModel
      GatewayProvider
      GatewayPool
      GatewayUpstream
      GatewayEntry
      GatewayResolvedEntry
      entryResolved
      entryUnresolved
      GatewayV1Config
      GatewayTable
      asn_scalar
      asnScalar
      asn_figure
      asnFigure
      asn_props
      asnProps
      asn_name
      asnName
      gateway_params
      gatewayParams
      calibration_registry_load!
      calibrationRegistryLoad!
      gateway_profiles_parse
      gatewayProfilesParse
      gateway_config_v2_build!
      gatewayConfigV2Build!
      gateway_config_parse!
      gatewayConfigParse!
      gateway_intent_line
      gatewayIntentLine
      gateway_v2_route
      gatewayV2Route
      gateway_v2_entry!
      gatewayV2Entry!
      gateway_v2_entries!
      gatewayV2Entries!
      gateway_v2_alias_entry!
      gatewayV2AliasEntry!
      gateway_note_intent
      gatewayNoteIntent
      gateway_undeclared_intents
      gatewayUndeclaredIntents
      gateway_any_only_intents
      gatewayAnyOnlyIntents
      gateway_entry_label
      gatewayEntryLabel
      ConfigKey
      keyBuiltin
      keyFiles
      ProfilesCache
      ProfileSelection
      RouteEntries
      ProfileHealth
      healthError
      healthV1
      healthV2
      ConfigHealth
      gatewayProfilesPath
      gatewayConfigKey!
      configKeyEqual?
      gatewayProfilesLoadText!
      gatewayLoadWarningLines
      emptyProfilesCache
      gatewayProfilesLoad!
      gatewayProfileName
      gatewayProfileSelect
      gatewayProfileModels
      gatewayRouteEntries!
      gatewayProfileHealth
      gatewayConfigHealth
      gatewayProfileAsn
      gatewayConfigAsn
      gatewayConfigReceipt
      gatewayConfigCheckText!]
  :i [(wire :a wire)
      (asl-parser/ast :a ast)
      (asl-parser/lexer :a lx)
      (asl-parser/reader :a rd)
      (aslGateway/batchPool :a bp)])

(enum AsnScalar
  (:c scalarBool [(b Bool)])
  (:c scalarInt [(n Int64)])
  (:c scalarFloat [(f Float64)])
  (:c scalarStr [(s String)]))

fn scalarToString sc: AsnScalar -> String
  (mt sc
    ((scalarBool b) (if b "true" "false"))
    ((scalarInt n) (stringFromInt64 n))
    ((scalarFloat f) (stringFromFloat64 f))
    ((scalarStr s) s))

(schema GatewayParams
  (:f temperature (Option Float64))
  (:f effort (Option String))
  (:f maxTokens (Option Int64))
  (:f contextBudget (Option Int64))
  (:f timeoutSec (Option Float64))
  (:f reasoning (Option Bool))
  (:f rpm (Option Float64)))

fn emptyGatewayParams -> GatewayParams
  (GatewayParams
    :temperature (none)
    :effort (none)
    :maxTokens (none)
    :contextBudget (none)
    :timeoutSec (none)
    :reasoning (none)
    :rpm (none))

fn mergeParams base: GatewayParams override: GatewayParams -> GatewayParams
  (GatewayParams
    :temperature (if (some? override.temperature) override.temperature base.temperature)
    :effort (if (some? override.effort) override.effort base.effort)
    :maxTokens (if (some? override.maxTokens) override.maxTokens base.maxTokens)
    :contextBudget (if (some? override.contextBudget) override.contextBudget base.contextBudget)
    :timeoutSec (if (some? override.timeoutSec) override.timeoutSec base.timeoutSec)
    :reasoning (if (some? override.reasoning) override.reasoning base.reasoning)
    :rpm (if (some? override.rpm) override.rpm base.rpm))

(schema GatewayRoute
  (:f intent String)
  (:f chain (List String))
  (:f models (List String)))

(schema GatewayProfile
  (:f id String)
  (:f routes (List GatewayRoute))
  (:f fallback (Option String)))

(schema GatewayModel
  (:f id String)
  (:f provider String)
  (:f name String)
  (:f calibration (Option String))
  (:f params GatewayParams)
  (:f shown (List (Pair String String))))

(schema GatewayProvider
  (:f id String)
  (:f kind String)
  (:f base String)
  (:f keyEnv String)
  (:f timeoutSec Float64)
  (:f rpm Float64)
  (:f pool (Option GatewayPool)))

(schema GatewayPool
  (:f config bp/PoolConfig)
  (:f batch Bool)
  (:f scaleDownPath String))

(schema GatewayUpstream
  (:f provider String)
  (:f url String)
  (:f key String))

(schema GatewayEntry
  (:f alias String)
  (:f provider String)
  (:f kind String)
  (:f name String)
  (:f dispatch String)
  (:f params GatewayParams)
  (:f upstream GatewayUpstream)
  (:f timeoutSec Float64)
  (:f rpm (Option Float64))
  (:f pool (Option GatewayPool)))

(enum GatewayResolvedEntry
  (:c entryResolved [(entry GatewayEntry)])
  (:c entryUnresolved [(alias String)]))

(schema GatewayV1Config
  (:f defaultProfile String)
  (:f profiles (Map String (List GatewayRoute))))

(schema GatewayTable
  (:f version Int64)
  (:f defaultProfile String)
  (:f profiles (Map String GatewayProfile))
  (:f profileOrder (List String))
  (:f models (Map String GatewayModel))
  (:f modelOrder (List String))
  (:f providers (Map String GatewayProvider))
  (:f intents (Map String (Option String)))
  (:f uses (Map String String))
  (:f useOrder (List String))
  (:f source String)
  (:f registry String)
  (:f registryError (Option String))
  (:f warnings (List String))
  (:f undeclaredIntents (Map String Int64)))


fn listAppendOne xs: (List String) x: String -> (List String)
  (listAppend xs (list x))

fn isStringLiteral? expr: rd/SExpr -> Bool
  (mt expr
    ((rd/sexprAtom v) (and (>= (stringLength v) 2) (stringStartsWith? v "\"") (stringEndsWith? v "\"")))
    (_ false))

fn isKeyword? expr: rd/SExpr -> Bool
  (mt expr
    ((rd/sexprAtom v) (and (> (stringLength v) 1) (stringStartsWith? v ":") (not (stringStartsWith? v "\""))))
    (_ false))

fn isBareAtom? expr: rd/SExpr -> Bool
  (mt expr
    ((rd/sexprAtom v) (and (not (stringEmpty? v)) (not (stringStartsWith? v ":")) (not (stringStartsWith? v "\""))))
    (_ false))

fn sexprRawText expr: rd/SExpr -> String
  (mt expr
    ((rd/sexprAtom v) v)
    (_ ""))

fn unescapeLoop s: String i: Int64 n: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (if (and (= c "\\") (< (+ i 1) n))
        (let [(nextC (optionOr (stringSlice s (+ i 1) (+ i 2)) ""))]
          (cond
            ((= nextC "\"") (unescapeLoop s (+ i 2) n (cons "\"" acc)))
            ((= nextC "\\") (unescapeLoop s (+ i 2) n (cons "\\" acc)))
            ((= nextC "n") (unescapeLoop s (+ i 2) n (cons "\n" acc)))
            ((= nextC "t") (unescapeLoop s (+ i 2) n (cons "\t" acc)))
            ((= nextC "r") (unescapeLoop s (+ i 2) n (cons "\r" acc)))
            (else (unescapeLoop s (+ i 2) n (cons nextC acc)))))
        (unescapeLoop s (+ i 1) n (cons c acc)))))

fn stripQuotesAndUnescape s: String -> String
  (let [(n (stringLength s))]
    (if (and (>= n 2) (stringStartsWith? s "\"") (stringEndsWith? s "\""))
      (let [(inner (optionOr (stringSlice s 1 (- n 1)) ""))]
        (if (stringContains? inner "\\")
          (unescapeLoop inner 0 (stringLength inner) (list))
          inner))
      s))

fn lstripColons s: String -> String
  (if (stringStartsWith? s ":")
    (lstripColons (optionOr (stringSlice s 1 (stringLength s)) ""))
    s)

fn isDigitChar c: String -> Bool
  (and (>= (charCode c) 48) (<= (charCode c) 57))

fn allDigits? s: String i: Int64 n: Int64 -> Bool
  (if (>= i n)
    (> n 0)
    (if (isDigitChar (optionOr (stringSlice s i (+ i 1)) ""))
      (allDigits? s (+ i 1) n)
      false))

fn isIntString? s: String -> Bool
  (let [(n (stringLength s))]
    (if (= n 0) false
      (if (stringStartsWith? s "-")
        (and (> n 1) (allDigits? s 1 n))
        (allDigits? s 0 n))))

fn isFloatString? s: String -> Bool
  (let [(n (stringLength s))
        (dot (stringIndexOf s "."))]
    (mt dot
      ((none) false)
      ((some dotIdx)
        (let [(prefix (optionOr (stringSlice s 0 dotIdx) ""))
              (suffix (optionOr (stringSlice s (+ dotIdx 1) n) ""))]
          (and (isIntString? prefix) (> (stringLength suffix) 0) (allDigits? suffix 0 (stringLength suffix)))))))

fn isEnvNameChar c: String -> Bool
  (let [(code (charCode c))]
    (or (= c "_")
        (and (>= code 65) (<= code 90))
        (and (>= code 97) (<= code 122))
        (and (>= code 48) (<= code 57))))

fn isEnvStartChar c: String -> Bool
  (let [(code (charCode c))]
    (or (= c "_")
        (and (>= code 65) (<= code 90))
        (and (>= code 97) (<= code 122))))

fn checkEnvChars s: String i: Int64 n: Int64 -> Bool
  (if (>= i n) true
    (if (isEnvNameChar (optionOr (stringSlice s i (+ i 1)) ""))
      (checkEnvChars s (+ i 1) n)
      false))

fn isValidEnvName? s: String -> Bool
  (let [(n (stringLength s))]
    (if (= n 0) false
      (if (isEnvStartChar (optionOr (stringSlice s 0 1) ""))
        (checkEnvChars s 1 n)
        false)))

fn rstripSlash s: String -> String
  (if (stringEndsWith? s "/")
    (rstripSlash (optionOr (stringSlice s 0 (- (stringLength s) 1)) ""))
    s)


fn asn_name v: rd/SExpr what: String -> (Result String String)
  (mt v
    ((rd/sexprAtom s)
      (if (or (stringEmpty? s) (stringStartsWith? s ":") (stringStartsWith? s "\""))
        (err (str what " must be a bare atom, found " s))
        (ok s)))
    (_ (err (str what " must be a bare atom, found compound"))))

fn asnName v: rd/SExpr what: String -> (Result String String)
  (asn_name v what)

fn asn_scalar expr: rd/SExpr -> AsnScalar
  (mt expr
    ((rd/sexprAtom raw)
      (if (isStringLiteral? expr)
        (scalarStr (stripQuotesAndUnescape raw))
        (cond
          ((= raw "true") (scalarBool true))
          ((= raw "false") (scalarBool false))
          ((isIntString? raw) (scalarInt (optionOr (stringToInt64 raw) 0)))
          ((isFloatString? raw) (mt (stringToFloat64 raw) ((some f) (scalarFloat f)) ((none) (scalarStr (lstripColons raw)))))
          (else (scalarStr (lstripColons raw))))))
    ((rd/sexprList _) (scalarStr ""))
    ((rd/sexprVect _) (scalarStr "")))

fn asnScalar expr: rd/SExpr -> AsnScalar
  (asn_scalar expr)

fn parsePropsPairs items: (List rd/SExpr) what: String acc: (Map String rd/SExpr) -> (Result (Map String rd/SExpr) String)
  (mt (listHead items)
    ((none) (ok acc))
    ((some kExpr)
      (let [(tail (optionOr (listTail items) (list)))]
        (mt (listHead tail)
          ((none) (err (str what " has an odd number of items")))
          ((some vExpr)
            (let [(rest (optionOr (listTail tail) (list)))]
              (if (not (isKeyword? kExpr))
                (err (str what ": " (sexprRawText kExpr) " is not a :keyword"))
                (let [(key (lstripColons (sexprRawText kExpr)))]
                  (parsePropsPairs rest what (mapSet acc key vExpr))))))))))

fn asn_props form: rd/SExpr head: (Option String) -> (Result (Map String rd/SExpr) String)
  (let [(what (mt head ((some h) (str "(" h " ...)")) ((none) "a property list")))]
    (mt form
      ((rd/sexprList items)
        (mt head
          ((some h)
            (mt (listHead items)
              ((none) (err (str "expected " what ", found ()")))
              ((some first)
                (if (!= (sexprRawText first) h)
                  (err (str "expected " what ", found (" (sexprRawText first) " ...)"))
                  (let [(rest (optionOr (listTail items) (list)))]
                    (if (!= (mod (listLength rest) 2) 0)
                      (err (str what " has an odd number of items"))
                      (parsePropsPairs rest what (mapEmpty))))))))
          ((none)
            (if (!= (mod (listLength items) 2) 0)
              (err (str what " has an odd number of items"))
              (parsePropsPairs items what (mapEmpty))))))
      (_ (err (str "expected " what ", found compound")))))

fn asnProps form: rd/SExpr head: (Option String) -> (Result (Map String rd/SExpr) String)
  (asn_props form head)

fn asn_figure expr: rd/SExpr -> AsnScalar
  (mt expr
    ((rd/sexprList items)
      (mt (asn_props expr (none))
        ((ok props)
          (mt (mapGet props "v")
            ((some vExpr) (asn_scalar vExpr))
            ((none) (asn_scalar expr))))
        ((err _) (asn_scalar expr))))
    (_ (asn_scalar expr)))

fn asnFigure expr: rd/SExpr -> AsnScalar
  (asn_figure expr)


fn checkTemperature props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (mt (mapGet props "temperature")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asn_figure expr))]
        (mt sc
          ((scalarFloat f) (pair (with cur :temperature (some f)) errs))
          ((scalarInt n) (pair (with cur :temperature (some (int64ToFloat64 n))) errs))
          (_ (pair cur (cons (str what ": :temperature must be a number") errs)))))))

fn checkEffort props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (mt (mapGet props "effort")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asn_figure expr))]
        (mt sc
          ((scalarStr s)
            (if (or (= s "low") (or (= s "medium") (or (= s "high") (or (= s "xhigh") (= s "none")))))
              (pair (with cur :effort (some s)) errs)
              (pair cur (cons (str what ": :effort must be low, medium, high, xhigh or none") errs))))
          (_ (pair cur (cons (str what ": :effort must be low, medium, high, xhigh or none") errs)))))))

fn checkMaxTokens props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (mt (mapGet props "maxTokens")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asn_figure expr))]
        (mt sc
          ((scalarInt n)
            (if (> n 0)
              (pair (with cur :maxTokens (some n)) errs)
              (pair cur (cons (str what ": :maxTokens must be a positive number") errs))))
          ((scalarFloat f)
            (if (and (> f 0.0) (some? (float64ToInt64 f)))
              (pair (with cur :maxTokens (float64ToInt64 f)) errs)
              (pair cur (cons (str what ": :maxTokens must be a positive number") errs))))
          (_ (pair cur (cons (str what ": :maxTokens must be a positive number") errs)))))))

fn checkContextBudget props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (mt (mapGet props "contextBudget")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asn_figure expr))]
        (mt sc
          ((scalarInt n)
            (if (> n 0)
              (pair (with cur :contextBudget (some n)) errs)
              (pair cur (cons (str what ": :contextBudget must be a positive number") errs))))
          ((scalarFloat f)
            (if (and (> f 0.0) (some? (float64ToInt64 f)))
              (pair (with cur :contextBudget (float64ToInt64 f)) errs)
              (pair cur (cons (str what ": :contextBudget must be a positive number") errs))))
          (_ (pair cur (cons (str what ": :contextBudget must be a positive number") errs)))))))

fn checkTimeoutSec props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (mt (mapGet props "timeoutSec")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asn_figure expr))]
        (mt sc
          ((scalarFloat f)
            (if (> f 0.0)
              (pair (with cur :timeoutSec (some f)) errs)
              (pair cur (cons (str what ": :timeoutSec must be a positive number") errs))))
          ((scalarInt n)
            (if (> n 0)
              (pair (with cur :timeoutSec (some (int64ToFloat64 n))) errs)
              (pair cur (cons (str what ": :timeoutSec must be a positive number") errs))))
          (_ (pair cur (cons (str what ": :timeoutSec must be a positive number") errs)))))))

fn checkReasoning props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (mt (mapGet props "reasoning")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asn_figure expr))]
        (mt sc
          ((scalarBool b) (pair (with cur :reasoning (some b)) errs))
          (_ (pair cur (cons (str what ": :reasoning must be true or false") errs)))))))

fn checkRpm props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (mt (mapGet props "rpm")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asn_figure expr))]
        (mt sc
          ((scalarFloat f)
            (if (> f 0.0)
              (pair (with cur :rpm (some f)) errs)
              (pair cur (cons (str what ": :rpm must be a positive number") errs))))
          ((scalarInt n)
            (if (> n 0)
              (pair (with cur :rpm (some (int64ToFloat64 n))) errs)
              (pair cur (cons (str what ": :rpm must be a positive number") errs))))
          (_ (pair cur (cons (str what ": :rpm must be a positive number") errs)))))))

fn gateway_params props: (Map String rd/SExpr) what: String -> (Pair GatewayParams (List String))
  (let [(s0 (pair (emptyGatewayParams) (list)))
        (s1 (checkTemperature props what (pairFirst s0) (pairSecond s0)))
        (s2 (checkEffort props what (pairFirst s1) (pairSecond s1)))
        (s3 (checkMaxTokens props what (pairFirst s2) (pairSecond s2)))
        (s4 (checkContextBudget props what (pairFirst s3) (pairSecond s3)))
        (s5 (checkTimeoutSec props what (pairFirst s4) (pairSecond s4)))
        (s6 (checkReasoning props what (pairFirst s5) (pairSecond s5)))
        (s7 (checkRpm props what (pairFirst s6) (pairSecond s6)))]
    (pair (pairFirst s7) (listReverse (pairSecond s7))))

fn gatewayParams props: (Map String rd/SExpr) what: String -> (Pair GatewayParams (List String))
  (gateway_params props what)

fn paramPresent? params: GatewayParams k: String -> Bool
  (cond
    ((= k "temperature") (some? params.temperature))
    ((= k "effort") (some? params.effort))
    ((= k "maxTokens") (some? params.maxTokens))
    ((= k "contextBudget") (some? params.contextBudget))
    ((= k "timeoutSec") (some? params.timeoutSec))
    ((= k "reasoning") (some? params.reasoning))
    ((= k "rpm") (some? params.rpm))
    (else false))

fn scalarAsnValue sc: AsnScalar -> String
  (mt sc
    ((scalarBool b) (if b "true" "false"))
    ((scalarInt n) (stringFromInt64 n))
    ((scalarFloat f) (stringFromFloat64 f))
    ((scalarStr s) (str "\"" (wire/asnEscape s) "\"")))

fn paramsShown props: (Map String rd/SExpr) params: GatewayParams -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (k String)] -> (List (Pair String String))
          (mt (mapGet props k)
            ((none) acc)
            ((some expr)
              (if (paramPresent? params k)
                (listAppend acc (list (pair k (scalarAsnValue (asn_figure expr)))))
                acc))))
        (list)
        (list "temperature" "effort" "maxTokens" "contextBudget" "timeoutSec" "reasoning" "rpm"))

fn shownHasKey? shown: (List (Pair String String)) k: String -> Bool
  (listAny? (fn [(p (Pair String String))] -> Bool (= (pairFirst p) k)) shown)

fn mergeShown base: (List (Pair String String)) own: (List (Pair String String)) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (o (Pair String String))] -> (List (Pair String String))
          (if (shownHasKey? acc (pairFirst o))
            (map (fn [(p (Pair String String))] -> (Pair String String) (if (= (pairFirst p) (pairFirst o)) o p)) acc)
            (listAppend acc (list o))))
        base
        own)

fn asnReadCheck text: String -> (Option String)
  (asnScan (stringChars text) 0 0)

fn asnScan cs: (List String) i: Int64 depth: Int64 -> (Option String)
  (mt (listHead cs)
    ((none) (if (> depth 0) (some (str (stringFromInt64 depth) " unclosed ( at end of text")) (none)))
    ((some c)
      (let [(rest (optionOr (listTail cs) (list)))]
        (cond
          ((= c ";") (asnSkipLine rest (+ i 1) depth))
          ((= c "(") (asnScan rest (+ i 1) (+ depth 1)))
          ((= c ")") (if (= depth 0) (some (str "unbalanced ) at offset " (stringFromInt64 i))) (asnScan rest (+ i 1) (- depth 1))))
          ((= c "\"") (asnString rest (+ i 1) i depth))
          (else (asnScan rest (+ i 1) depth))))))

fn asnSkipLine cs: (List String) i: Int64 depth: Int64 -> (Option String)
  (mt (listHead cs)
    ((none) (asnScan (list) i depth))
    ((some c) (if (= c "\n") (asnScan (optionOr (listTail cs) (list)) (+ i 1) depth) (asnSkipLine (optionOr (listTail cs) (list)) (+ i 1) depth))))

fn asnString cs: (List String) j: Int64 start: Int64 depth: Int64 -> (Option String)
  (mt (listHead cs)
    ((none) (some (str "unterminated string at offset " (stringFromInt64 start))))
    ((some ch)
      (let [(rest (optionOr (listTail cs) (list)))
            (badEscape (some (str "bad string escape at offset " (stringFromInt64 j))))]
        (cond
          ((= ch "\"") (asnScan rest (+ j 1) depth))
          ((= ch "\\")
            (mt (listHead rest)
              ((some e) (if (listContains? (list "\\" "\"" "n" "t") e) (asnString (optionOr (listTail rest) (list)) (+ j 2) start depth) badEscape))
              ((none) badEscape)))
          (else (asnString rest (+ j 1) start depth))))))


fn calibrationRowId idExpr: rd/SExpr -> (Result String String)
  (if (isStringLiteral? idExpr)
    (let [(id (stripQuotesAndUnescape (sexprRawText idExpr)))]
      (if (stringEmpty? id) (err "calibration row :id must be a string, found ''") (ok id)))
    (err (str "calibration row :id must be a string, found '" (sexprRawText idExpr) "'")))

fn parseCalibrationModel mForm: rd/SExpr -> (Result (Pair String (Pair GatewayParams (List (Pair String String)))) String)
  (mt (asn_props mForm (some ":model"))
    ((err e) (err e))
    ((ok props)
      (mt (mt (mapGet props "id") ((none) (err "calibration row :id must be a string, found None")) ((some idExpr) (calibrationRowId idExpr)))
        ((err e) (err e))
        ((ok id)
          (let [(pRes (mt (mapGet props "params")
                        ((none) (ok (mapEmpty)))
                        ((some pExpr) (mt pExpr
                                        ((rd/sexprList _) (asn_props pExpr (none)))
                                        (_ (ok (mapEmpty)))))))]
            (mt pRes
              ((err e) (err e))
              ((ok pProps)
                (let [(checked (gateway_params pProps (str "calibration " id)))]
                  (if (listEmpty? (pairSecond checked))
                    (ok (pair id (pair (pairFirst checked) (paramsShown pProps (pairFirst checked)))))
                    (err (stringJoin (pairSecond checked) "; ")))))))))))

fn parseCalibrationModels modelsList: (List rd/SExpr) acc: (Map String (Pair GatewayParams (List (Pair String String)))) -> (Result (Map String (Pair GatewayParams (List (Pair String String)))) String)
  (mt (listHead modelsList)
    ((none) (ok acc))
    ((some mForm)
      (let [(tail (optionOr (listTail modelsList) (list)))]
        (mt (parseCalibrationModel mForm)
          ((err e) (err e))
          ((ok p) (parseCalibrationModels tail (mapSet acc (pairFirst p) (pairSecond p))))))))

fn calibrationRowsLoad! path: String -> (Result (Map String (Pair GatewayParams (List (Pair String String)))) String)
  (if (stringEmpty? path)
    (err "calibration registry not found")
    (mt (fileReadString path)
      ((err e) (err (str "calibration registry " path " not found")))
      ((ok text)
        (let [(toks (lx/tokenize text))]
          (mt (mt (asnReadCheck text) ((some e) (err (ast/ParseError :msg e :line 0 :col 0))) ((none) (ast/readForms toks)))
            ((err e) (err (str "calibration registry " path ": " e.msg)))
            ((ok forms)
              (if (!= (listLength forms) 1)
                (err (str "calibration registry " path ": expected one (:calibrationIndex ...) form, found " (stringFromInt64 (listLength forms))))
                (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
                  (mt (asn_props top (some ":calibrationIndex"))
                    ((err e) (err (str "calibration registry " path ": " e)))
                    ((ok props)
                      (mt (mapGet props "models")
                        ((none) (ok (mapEmpty)))
                        ((some modelsExpr)
                          (mt modelsExpr
                            ((rd/sexprList mList) (mt (parseCalibrationModels mList (mapEmpty)) ((ok rows) (ok rows)) ((err e) (err (str "calibration registry " path ": " e)))))
                            ((rd/sexprVect mList) (mt (parseCalibrationModels mList (mapEmpty)) ((ok rows) (ok rows)) ((err e) (err (str "calibration registry " path ": " e)))))
                            (_ (ok (mapEmpty))))))))))))))))

fn calibration_registry_load! path: String -> (Result (Map String GatewayParams) String)
  (mt (calibrationRowsLoad! path)
    ((err e) (err e))
    ((ok rows) (ok (mapFromPairs (map (fn [(p (Pair String (Pair GatewayParams (List (Pair String String)))))] -> (Pair String GatewayParams) (pair (pairFirst p) (pairFirst (pairSecond p)))) (mapPairs rows))))))

fn calibrationRegistryLoad! path: String -> (Result (Map String GatewayParams) String)
  (calibration_registry_load! path)


fn parseV1Route rf: rd/SExpr pid: String -> (Result GatewayRoute String)
  (mt (asn_props rf (none))
    ((err e) (err e))
    ((ok props)
      (mt (mapGet props "intent")
        ((none) (err (str "profile " pid " route :intent must be a bare atom, found ()")))
        ((some intentExpr)
          (mt (asn_name intentExpr (str "profile " pid " route :intent"))
            ((err e) (err e))
            ((ok rawIntent)
              (let [(intent (stringLower rawIntent))]
                (mt (mapGet props "models")
                  ((none) (err (str "profile " pid " route " intent ": :models must be a non-empty list of strings")))
                  ((some modelsExpr)
                    (mt modelsExpr
                      ((rd/sexprList mItems)
                        (if (listEmpty? mItems)
                          (err (str "profile " pid " route " intent ": :models must be a non-empty list of strings"))
                          (let [(allStr (listAll? (fn [(m rd/SExpr)] -> Bool (and (isStringLiteral? m) (not (stringEmpty? (stripQuotesAndUnescape (sexprRawText m)))))) mItems))]
                            (if (not allStr)
                              (err (str "profile " pid " route " intent ": :models must be a non-empty list of strings"))
                              (ok (GatewayRoute :intent intent :chain (list) :models (map (fn [(m rd/SExpr)] -> String (stripQuotesAndUnescape (sexprRawText m))) mItems)))))))
                      ((rd/sexprVect mItems)
                        (if (listEmpty? mItems)
                          (err (str "profile " pid " route " intent ": :models must be a non-empty list of strings"))
                          (let [(allStr (listAll? (fn [(m rd/SExpr)] -> Bool (and (isStringLiteral? m) (not (stringEmpty? (stripQuotesAndUnescape (sexprRawText m)))))) mItems))]
                            (if (not allStr)
                              (err (str "profile " pid " route " intent ": :models must be a non-empty list of strings"))
                              (ok (GatewayRoute :intent intent :chain (list) :models (map (fn [(m rd/SExpr)] -> String (stripQuotesAndUnescape (sexprRawText m))) mItems)))))))
                      (_ (err (str "profile " pid " route " intent ": :models must be a non-empty list of strings")))))))))))))

fn parseV1Routes rItems: (List rd/SExpr) pid: String acc: (List GatewayRoute) -> (Result (List GatewayRoute) String)
  (mt (listHead rItems)
    ((none) (ok (listReverse acc)))
    ((some rf)
      (let [(tail (optionOr (listTail rItems) (list)))]
        (mt (parseV1Route rf pid)
          ((err e) (err e))
          ((ok route) (parseV1Routes tail pid (cons route acc)))))))

fn parseV1Profile pf: rd/SExpr profiles: (Map String (List GatewayRoute)) -> (Result (Pair String (List GatewayRoute)) String)
  (mt (asn_props pf (some ":profile"))
    ((err e) (err e))
    ((ok pProps)
      (mt (mapGet pProps "id")
        ((none) (err "(:profile :id ...) must be a bare atom, found ()"))
        ((some idExpr)
          (mt (asn_name idExpr "(:profile :id ...)")
            ((err e) (err e))
            ((ok pid)
              (if (mapHas? profiles pid)
                (err (str "profile " pid " is defined twice"))
                (mt (mapGet pProps "routes")
                  ((none) (err (str "profile " pid ": :routes must be a non-empty list")))
                  ((some routesExpr)
                    (mt routesExpr
                      ((rd/sexprList rItems)
                        (if (listEmpty? rItems)
                          (err (str "profile " pid ": :routes must be a non-empty list"))
                          (mt (parseV1Routes rItems pid (list))
                            ((err e) (err e))
                            ((ok routes) (ok (pair pid routes))))))
                      ((rd/sexprVect rItems)
                        (if (listEmpty? rItems)
                          (err (str "profile " pid ": :routes must be a non-empty list"))
                          (mt (parseV1Routes rItems pid (list))
                            ((err e) (err e))
                            ((ok routes) (ok (pair pid routes))))))
                      (_ (err (str "profile " pid ": :routes must be a non-empty list")))))))))))))

fn parseV1ProfilesList pfList: (List rd/SExpr) profiles: (Map String (List GatewayRoute)) -> (Result (Map String (List GatewayRoute)) String)
  (mt (listHead pfList)
    ((none) (ok profiles))
    ((some pf)
      (let [(tail (optionOr (listTail pfList) (list)))]
        (mt (parseV1Profile pf profiles)
          ((err e) (err e))
          ((ok pPair) (parseV1ProfilesList tail (mapSet profiles (pairFirst pPair) (pairSecond pPair))))))))

fn gateway_profiles_parse text: String -> (Result GatewayV1Config String)
  (let [(toks (lx/tokenize text))]
    (mt (mt (asnReadCheck text) ((some e) (err (ast/ParseError :msg e :line 0 :col 0))) ((none) (ast/readForms toks)))
      ((err e) (err (str e.msg)))
      ((ok forms)
        (if (!= (listLength forms) 1)
          (err (str "expected one (:gateway ...) form, found " (stringFromInt64 (listLength forms))))
          (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
            (mt (asn_props top (some ":gateway"))
              ((err e) (err e))
              ((ok g)
                (mt (mapGet g "profiles")
                  ((none) (err ":profiles must be a non-empty list of (:profile ...)"))
                  ((some pExpr)
                    (let [(pList (mt pExpr ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))]
                      (if (listEmpty? pList)
                        (err ":profiles must be a non-empty list of (:profile ...)")
                        (mt (parseV1ProfilesList pList (mapEmpty))
                          ((err e) (err e))
                          ((ok profiles)
                            (let [(defaultName (mt (mapGet g "profile")
                                                 ((none) "default")
                                                 ((some defExpr) (resultOr (asn_name defExpr "(:gateway :profile ...)") "default"))))]
                              (if (not (mapHas? profiles defaultName))
                                (err (str ":profile " defaultName " names no defined profile"))
                                (ok (GatewayV1Config :defaultProfile defaultName :profiles profiles)))))))))))))))))

fn gatewayProfilesParse text: String -> (Result GatewayV1Config String)
  (gateway_profiles_parse text)


fn defaultProviders! -> (Map String GatewayProvider)
  (let [(geminiBase "https://generativelanguage.googleapis.com/v1beta/openai")
        (groqBase (rstripSlash (optionOr (envGet "GROQ_BASE_URL") "https://api.groq.com/openai/v1")))
        (openrouterBase (rstripSlash (optionOr (envGet "OPENROUTER_BASE_URL") "https://openrouter.ai/api/v1")))
        (ollamaBase (str (rstripSlash (optionOr (envGet "OLLAMA_BASE_URL") "https://ollama.com")) "/v1"))
        (ollamaTimeout (optionOr (mt (envGet "OLLAMA_TIMEOUT_SEC")
                                   ((none) (none))
                                   ((some s) (if (isFloatString? s) (stringToFloat64 s) (mt (stringToInt64 s) ((some n) (some (int64ToFloat64 n)) ((none) (none)))))))
                                 300.0))
        (p1 (GatewayProvider :id "agy" :kind "cli" :base "" :keyEnv "" :timeoutSec 0.0 :rpm 0.0 :pool (none)))
        (p2 (GatewayProvider :id "codex" :kind "cli" :base "" :keyEnv "" :timeoutSec 0.0 :rpm 0.0 :pool (none)))
        (p3 (GatewayProvider :id "claude" :kind "cli" :base "" :keyEnv "" :timeoutSec 0.0 :rpm 0.0 :pool (none)))
        (p4 (GatewayProvider :id "gemini" :kind "openai" :base geminiBase :keyEnv "GEMINI_API_KEY" :timeoutSec 45.0 :rpm 0.0 :pool (none)))
        (p5 (GatewayProvider :id "groq" :kind "openai" :base groqBase :keyEnv "GROQ_API_KEY" :timeoutSec 45.0 :rpm 0.0 :pool (none)))
        (p6 (GatewayProvider :id "openrouter" :kind "openai" :base openrouterBase :keyEnv "OPENROUTER_API_KEY" :timeoutSec 45.0 :rpm 0.0 :pool (none)))
        (p7 (GatewayProvider :id "ollama" :kind "openai" :base ollamaBase :keyEnv "OLLAMA_API_KEY" :timeoutSec ollamaTimeout :rpm 0.0 :pool (none)))]
    (mapFromPairs (list (pair "agy" p1) (pair "codex" p2) (pair "claude" p3) (pair "gemini" p4) (pair "groq" p5) (pair "openrouter" p6) (pair "ollama" p7))))

fn extractPropList items: (List rd/SExpr) head: String accForms: (List (Map String rd/SExpr)) accErrs: (List String) -> (Pair (List (Map String rd/SExpr)) (List String))
  (mt (listHead items)
    ((none) (pair (listReverse accForms) (listReverse accErrs)))
    ((some f)
      (let [(tail (optionOr (listTail items) (list)))]
        (mt (asn_props f (some head))
          ((ok props) (extractPropList tail head (cons props accForms) accErrs))
          ((err e) (extractPropList tail head accForms (cons e accErrs)))))))

fn getSubForms g: (Map String rd/SExpr) key: String head: String -> (Pair (List (Map String rd/SExpr)) (List String))
  (mt (mapGet g key)
    ((none) (pair (list) (list)))
    ((some expr)
      (mt expr
        ((rd/sexprList items) (extractPropList items head (list) (list)))
        ((rd/sexprVect items) (extractPropList items head (list) (list)))
        (_ (pair (list) (list (str ":" key " must be a list of (" head " ...)")))))))

fn poolPositiveInt props: (Map String rd/SExpr) key: String -> (Result Int64 String)
  (mt (mapGet props key)
    ((none) (err (str "pool requires :" key)))
    ((some expr)
      (mt (asn_scalar expr)
        ((scalarInt n) (if (> n 0) (ok n) (err (str "pool :" key " must be a positive integer"))))
        (_ (err (str "pool :" key " must be a positive integer"))))))

fn poolBool props: (Map String rd/SExpr) key: String -> (Result Bool String)
  (mt (mapGet props key)
    ((none) (err (str "pool requires :" key)))
    ((some expr)
      (mt (asn_scalar expr)
        ((scalarBool b) (ok b))
        (_ (err (str "pool :" key " must be true or false"))))))

fn poolOptionalBool props: (Map String rd/SExpr) key: String -> (Result Bool String)
  (if (mapHas? props key) (poolBool props key) (ok false))

fn poolOptionalPath props: (Map String rd/SExpr) key: String -> (Result String String)
  (mt (mapGet props key)
    ((none) (ok ""))
    ((some expr)
      (mt (asn_scalar expr)
        ((scalarStr text) (if (stringStartsWith? text "/") (ok text) (err (str "pool :" key " must be a path starting with /"))))
        (_ (err (str "pool :" key " must be a string path"))))))

fn parsePoolConfig expr: rd/SExpr -> (Result GatewayPool String)
  (mt (asn_props expr (none))
    ((err e) (err (str "invalid :pool: " e)))
    ((ok props)
      (mt (poolPositiveInt props "windowMs")
        ((err e) (err e))
        ((ok windowMs)
          (mt (poolPositiveInt props "peakCount")
            ((err e) (err e))
            ((ok peakCount)
              (mt (poolBool props "bypassWhileBusy")
                ((err e) (err e))
                ((ok bypassWhileBusy)
                  (mt (poolPositiveInt props "requestTimeoutMs")
                    ((err e) (err e))
                    ((ok requestTimeoutMs)
                      (mt (poolOptionalBool props "batch")
                        ((err e) (err e))
                        ((ok batch)
                          (mt (poolOptionalPath props "scaleDownPath")
                            ((err e) (err e))
                            ((ok scaleDownPath)
                              (ok (GatewayPool :config (bp/makePoolConfig windowMs peakCount bypassWhileBusy requestTimeoutMs)
                                    :batch batch :scaleDownPath scaleDownPath))))))))))))))))

fn applyOneProvider provs: (Map String GatewayProvider) curErrs: (List String) p: (Map String rd/SExpr) -> (Pair (Map String GatewayProvider) (List String))
  (mt (mapGet p "id")
    ((none) (pair provs curErrs))
    ((some idExpr)
      (mt (asn_name idExpr "(:provider :id ...)")
        ((err e) (pair provs (listAppendOne curErrs e)))
        ((ok pid)
          (let [(withKeyErr (if (mapHas? p "key") (listAppendOne curErrs (str "provider " pid ": keys are named by :keyEnv, never stored in the file")) curErrs))
                (existing (optionOr (mapGet provs pid) (GatewayProvider :id pid :kind "" :base "" :keyEnv "" :timeoutSec 0.0 :rpm 0.0 :pool (none))))
                (kind (mt (mapGet p "kind")
                        ((some kExpr) (scalarToString (asn_scalar kExpr)))
                        ((none) existing.kind)))
                (kindErr (if (and (!= kind "openai") (!= kind "cli"))
                           (listAppendOne withKeyErr (str "provider " pid ": :kind must be openai or cli"))
                           (if (and (= kind "cli") (not (or (= pid "agy") (or (= pid "codex") (= pid "claude")))))
                             (listAppendOne withKeyErr (str "provider " pid ": a cli provider is one of agy, codex, claude"))
                             withKeyErr)))
                (baseRes (mt (mapGet p "base")
                           ((none) (pair existing.base kindErr))
                           ((some bExpr)
                             (if (not (isStringLiteral? bExpr))
                               (pair existing.base (listAppendOne kindErr (str "provider " pid ": :base must be an http(s) URL string")))
                               (let [(bStr (stripQuotesAndUnescape (sexprRawText bExpr)))]
                                 (if (not (or (stringStartsWith? bStr "http://") (stringStartsWith? bStr "https://")))
                                   (pair existing.base (listAppendOne kindErr (str "provider " pid ": :base must be an http(s) URL string")))
                                   (pair (rstripSlash bStr) kindErr)))))))
                (base (pairFirst baseRes))
                (withBaseErr (pairSecond baseRes))
                (keyEnvRes (mt (mapGet p "keyEnv")
                             ((none) (pair existing.keyEnv withBaseErr))
                             ((some keExpr)
                               (let [(ke (scalarToString (asn_scalar keExpr)))]
                                 (if (not (isValidEnvName? ke))
                                   (pair existing.keyEnv (listAppendOne withBaseErr (str "provider " pid ": :keyEnv must name an environment variable")))
                                   (pair ke withBaseErr))))))
                (keyEnv (pairFirst keyEnvRes))
                (withKeErr (pairSecond keyEnvRes))
                (timeoutRes (mt (mapGet p "timeoutSec")
                              ((none) (pair existing.timeoutSec withKeErr))
                              ((some tExpr)
                                (let [(sc (asn_scalar tExpr))]
                                  (mt sc
                                    ((scalarFloat f) (if (> f 0.0) (pair f withKeErr) (pair existing.timeoutSec (listAppendOne withKeErr (str "provider " pid ": :timeoutSec must be a positive number")))))
                                    ((scalarInt n) (if (> n 0) (pair (int64ToFloat64 n) withKeErr) (pair existing.timeoutSec (listAppendOne withKeErr (str "provider " pid ": :timeoutSec must be a positive number")))))
                                    (_ (pair existing.timeoutSec (listAppendOne withKeErr (str "provider " pid ": :timeoutSec must be a positive number")))))))))
                (timeoutSec (pairFirst timeoutRes))
                (withToErr (pairSecond timeoutRes))
                (rpmRes (mt (mapGet p "rpm")
                          ((none) (pair existing.rpm withToErr))
                          ((some rExpr)
                            (let [(sc (asn_scalar rExpr))]
                              (mt sc
                                ((scalarFloat f) (if (> f 0.0) (pair f withToErr) (pair existing.rpm (listAppendOne withToErr (str "provider " pid ": :rpm must be a positive number")))))
                                ((scalarInt n) (if (> n 0) (pair (int64ToFloat64 n) withToErr) (pair existing.rpm (listAppendOne withToErr (str "provider " pid ": :rpm must be a positive number")))))
                                (_ (pair existing.rpm (listAppendOne withToErr (str "provider " pid ": :rpm must be a positive number")))))))))
                (rpm (pairFirst rpmRes))
                (withRpmErr (pairSecond rpmRes))
                (poolRes (mt (mapGet p "pool")
                            ((none) (pair existing.pool withRpmErr))
                            ((some poolExpr)
                              (mt (parsePoolConfig poolExpr)
                                ((err e) (pair existing.pool (listAppendOne withRpmErr (str "provider " pid ": " e))))
                                ((ok poolValue) (pair (some poolValue) withRpmErr))))))
                (poolValue (pairFirst poolRes))
                (withPoolErr (pairSecond poolRes))
                (finalErrs (if (and (= kind "openai") (stringEmpty? base))
                             (listAppendOne withPoolErr (str "provider " pid ": an openai provider needs :base"))
                             withPoolErr))
                (updated (GatewayProvider :id pid :kind kind :base base :keyEnv keyEnv :timeoutSec timeoutSec :rpm rpm :pool poolValue))]
            (pair (mapSet provs pid updated) finalErrs))))))

fn loopProviders pForms: (List (Map String rd/SExpr)) provs: (Map String GatewayProvider) errs: (List String) -> (Pair (Map String GatewayProvider) (List String))
  (mt (listHead pForms)
    ((none) (pair provs errs))
    ((some p)
      (let [(tail (optionOr (listTail pForms) (list)))
            (stepRes (applyOneProvider provs errs p))]
        (loopProviders tail (pairFirst stepRes) (pairSecond stepRes)))))

fn providerOrderLoop pForms: (List (Map String rd/SExpr)) provs: (Map String GatewayProvider) order: (List String) -> (List String)
  (mt (listHead pForms)
    ((none) order)
    ((some p)
      (let [(tail (optionOr (listTail pForms) (list)))
            (next (pairFirst (applyOneProvider provs (list) p)))
            (added (filter (fn [(k String)] -> Bool (not (mapHas? provs k))) (mapKeys next)))]
        (providerOrderLoop tail next (listAppend order added)))))

fn providerOrder! providerForms: (List (Map String rd/SExpr)) -> (List String)
  (providerOrderLoop providerForms (defaultProviders!) (list "agy" "codex" "claude" "gemini" "groq" "openrouter" "ollama"))

fn buildProviders providerForms: (List (Map String rd/SExpr)) initial: (Map String GatewayProvider) errs: (List String) -> (Pair (Map String GatewayProvider) (List String))
  (loopProviders providerForms initial errs)

(schema ModelAccumulator
  (:f models (Map String GatewayModel))
  (:f order (List String))
  (:f errs (List String))
  (:f warns (List String)))

fn applyOneModel acc: ModelAccumulator m: (Map String rd/SExpr) providers: (Map String GatewayProvider) registry: (Map String (Pair GatewayParams (List (Pair String String)))) regError: (Option String) -> ModelAccumulator
  (mt (mapGet m "id")
    ((none) acc)
    ((some idExpr)
      (mt (asn_name idExpr "(:model :id ...)")
        ((err e) (with acc :errs (listAppendOne acc.errs e)))
        ((ok mid)
          (let [(dupErr (if (mapHas? acc.models mid) (listAppendOne acc.errs (str "model alias " mid " is defined twice")) acc.errs))
                (pidRes (mt (mapGet m "provider")
                          ((none) (err (str "model " mid " :provider must be a bare atom, found ()")))
                          ((some pExpr) (asn_name pExpr (str "model " mid " :provider")))))
                (nameRes (mt (mapGet m "name")
                           ((none) (err (str "model " mid ": :name must be a non-empty string")))
                           ((some nExpr)
                             (if (not (isStringLiteral? nExpr))
                               (err (str "model " mid ": :name must be a non-empty string"))
                               (let [(ns (stripQuotesAndUnescape (sexprRawText nExpr)))]
                                 (if (stringEmpty? ns)
                                   (err (str "model " mid ": :name must be a non-empty string"))
                                   (ok ns)))))))
                (errs1 (mt pidRes ((err e) (listAppendOne dupErr e)) ((ok _) dupErr)))
                (pid (resultOr pidRes ""))
                (errs2 (if (and (not (stringEmpty? pid)) (not (mapHas? providers pid)))
                         (listAppendOne errs1 (str "model " mid ": unknown provider " pid))
                         errs1))
                (errs3 (mt nameRes ((err e) (listAppendOne errs2 e)) ((ok _) errs2)))
                (name (resultOr nameRes ""))
                (ownParamsRes (gateway_params m (str "model " mid)))
                (ownParams (pairFirst ownParamsRes))
                (ownShown (paramsShown m ownParams))
                (paramErrs (pairSecond ownParamsRes))
                (errs4 (listAppend errs3 paramErrs))
                (providerKnown (or (stringEmpty? pid) (mapHas? providers pid)))
                (calRes (if (not providerKnown)
                          (pair (none) (pair (pair ownParams ownShown) acc.warns))
                          (mt (mapGet m "calibration")
                          ((none) (pair (none) (pair (pair ownParams ownShown) acc.warns)))
                          ((some cExpr)
                            (let [(calStr (if (isStringLiteral? cExpr) (stripQuotesAndUnescape (sexprRawText cExpr)) (sexprRawText cExpr)))]
                              (mt (mapGet registry calStr)
                                ((some regRow) (pair (some calStr) (pair (pair (mergeParams (pairFirst regRow) ownParams) (mergeShown (pairSecond regRow) ownShown)) acc.warns)))
                                ((none)
                                  (let [(suffix (mt regError ((some re) (str " (" re ")")) ((none) "")))
                                        (w (str "model " mid ": calibration " calStr " is not in the registry" suffix))]
                                    (pair (some calStr) (pair (pair ownParams ownShown) (listAppendOne acc.warns w)))))))))))
                (cal (pairFirst calRes))
                (finalParams (pairFirst (pairFirst (pairSecond calRes))))
                (finalShown (pairSecond (pairFirst (pairSecond calRes))))
                (finalWarns (pairSecond (pairSecond calRes)))
                (model (GatewayModel :id mid :provider pid :name name :calibration cal :params finalParams :shown finalShown))]
            (ModelAccumulator
              :models (if providerKnown (mapSet acc.models mid model) acc.models)
              :order (if providerKnown (listAppendOne acc.order mid) acc.order)
              :errs errs4
              :warns finalWarns))))))

fn loopModels mForms: (List (Map String rd/SExpr)) acc: ModelAccumulator providers: (Map String GatewayProvider) registry: (Map String (Pair GatewayParams (List (Pair String String)))) regError: (Option String) -> ModelAccumulator
  (mt (listHead mForms)
    ((none) acc)
    ((some m)
      (let [(tail (optionOr (listTail mForms) (list)))
            (nextAcc (applyOneModel acc m providers registry regError))]
        (loopModels tail nextAcc providers registry regError))))

fn buildModels modelForms: (List (Map String rd/SExpr)) providers: (Map String GatewayProvider) registry: (Map String (Pair GatewayParams (List (Pair String String)))) regError: (Option String) -> ModelAccumulator
  (loopModels modelForms (ModelAccumulator :models (mapEmpty) :order (list) :errs (list) :warns (list)) providers registry regError)

fn intentCycleStep intents: (Map String (Option String)) cur: String seen: (List String) -> (Option (List String))
  (if (listContains? seen cur)
    (some (listAppendOne seen cur))
    (mt (mapGet intents cur)
      ((none) (none))
      ((some parentOpt)
        (mt parentOpt
          ((none) (none))
          ((some parent) (intentCycleStep intents parent (listAppendOne seen cur)))))))

fn detectIntentCycles intents: (Map String (Option String)) keys: (List String) -> (Option String)
  (mt (listHead keys)
    ((none) (none))
    ((some iid)
      (let [(cycle (intentCycleStep intents iid (list)))]
        (mt cycle
          ((some path) (some (str "intent cycle: " (stringJoin path " -> "))))
          ((none) (detectIntentCycles intents (optionOr (listTail keys) (list))))))))

fn loopIntents iForms: (List (Map String rd/SExpr)) ints: (Map String (Option String)) errs: (List String) -> (Pair (Map String (Option String)) (List String))
  (mt (listHead iForms)
    ((none) (pair ints errs))
    ((some i)
      (let [(tail (optionOr (listTail iForms) (list)))]
        (mt (mapGet i "id")
          ((none) (loopIntents tail ints errs))
          ((some idExpr)
            (mt (asn_name idExpr "(:intent :id ...)")
              ((err e) (loopIntents tail ints (listAppendOne errs e)))
              ((ok rawIid)
                (let [(iid (stringLower rawIid))
                      (parentRes (mt (mapGet i "as")
                                   ((none) (ok (none)))
                                   ((some asExpr)
                                     (mt (asn_name asExpr (str "intent " iid " :as"))
                                       ((err e) (err e))
                                       ((ok p) (ok (some (stringLower p))))))))]
                  (mt parentRes
                    ((err e) (loopIntents tail ints (listAppendOne errs e)))
                    ((ok pOpt) (loopIntents tail (mapSet ints iid pOpt) errs)))))))))))

fn buildIntents intentForms: (List (Map String rd/SExpr)) -> (Pair (Map String (Option String)) (List String))
  (let [(parsed (loopIntents intentForms (mapEmpty) (list)))
        (initialIntents (pairFirst parsed))
        (parseErrs (pairSecond parsed))
        (allIntents (fold (fn [(acc (Map String (Option String))) (pairEntry (Pair String (Option String)))] -> (Map String (Option String))
                            (mt (pairSecond pairEntry)
                              ((none) acc)
                              ((some p) (if (mapHas? acc p) acc (mapSet acc p (none))))))
                          initialIntents
                          (mapPairs initialIntents)))
        (cycleOpt (detectIntentCycles allIntents (mapKeys allIntents)))
        (finalErrs (mt cycleOpt ((some msg) (listAppendOne parseErrs msg)) ((none) parseErrs)))]
    (pair allIntents finalErrs))

fn parseChainItem a: rd/SExpr models: (Map String GatewayModel) pid: String intent: String st: (Pair (List String) (List String)) -> (Pair (List String) (List String))
  (let [(cList (pairFirst st))
        (cErrs (pairSecond st))]
    (if (isStringLiteral? a)
      (let [(s (stripQuotesAndUnescape (sexprRawText a)))]
        (if (stringEmpty? s)
          (pair cList (listAppendOne cErrs (str "profile " pid " route " intent ": chain entry \"\" is neither an alias nor a model string")))
          (pair (listAppendOne cList s) cErrs)))
      (mt a
        ((rd/sexprAtom rawA)
          (if (not (mapHas? models rawA))
            (pair (listAppendOne cList rawA) (listAppendOne cErrs (str "profile " pid " route " intent ": unknown alias " rawA)))
            (pair (listAppendOne cList rawA) cErrs)))
        (_ (pair cList (listAppendOne cErrs (str "profile " pid " route " intent ": chain entry compound is neither an alias nor a model string")))))))

fn parseProfileRoute rf: rd/SExpr pid: String intents: (Map String (Option String)) models: (Map String GatewayModel) -> (Pair (Option GatewayRoute) (List String))
  (mt (asn_props rf (none))
    ((err e) (pair (none) (list (str "profile " pid ": " e))))
    ((ok props)
      (let [(intentRes (mt (mapGet props "intent")
                         ((none) (err (str "profile " pid " route :intent must be a bare atom, found ()")))
                         ((some iExpr) (asn_name iExpr (str "profile " pid " route :intent")))))
            (intent (stringLower (resultOr intentRes "")))
            (errs1 (mt intentRes ((err e) (list (str "profile " pid ": " e))) ((ok _) (list))))
            (errs2 (if (and (not (stringEmpty? intent)) (and (!= intent "any") (not (mapHas? intents intent))))
                     (listAppendOne errs1 (str "profile " pid ": route intent " intent " is not in :intents"))
                     errs1))
            (chainExprOpt (mapGet props "chain"))]
        (mt chainExprOpt
          ((none) (pair (none) (listAppendOne errs2 (str "profile " pid " route " intent ": :chain must be a non-empty list of aliases"))))
          ((some chainExpr)
            (let [(cItems (mt chainExpr ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))]
              (if (listEmpty? cItems)
                (pair (none) (listAppendOne errs2 (str "profile " pid " route " intent ": :chain must be a non-empty list of aliases")))
                (let [(chainRes (fold (fn [(st (Pair (List String) (List String))) (a rd/SExpr)] -> (Pair (List String) (List String))
                                        (parseChainItem a models pid intent st))
                                      (pair (list) (list))
                                      cItems))
                      (chain (pairFirst chainRes))
                      (chainErrs (pairSecond chainRes))
                      (finalErrs (listAppend errs2 chainErrs))]
                  (pair (some (GatewayRoute :intent intent :chain chain :models (list))) finalErrs)))))))))

fn profileFallbackStep profiles: (Map String GatewayProfile) cur: String seen: (List String) -> (Option (List String))
  (if (listContains? seen cur)
    (some (listAppendOne seen cur))
    (mt (mapGet profiles cur)
      ((none) (none))
      ((some pr)
        (mt pr.fallback
          ((none) (none))
          ((some fb)
            (if (mapHas? profiles fb)
              (profileFallbackStep profiles fb (listAppendOne seen cur))
              (none)))))))

fn detectProfileFallbackCycles profiles: (Map String GatewayProfile) keys: (List String) -> (Option String)
  (mt (listHead keys)
    ((none) (none))
    ((some pid)
      (let [(cycle (profileFallbackStep profiles pid (list)))]
        (mt cycle
          ((some path) (some (str "profile fallback cycle: " (stringJoin path " -> "))))
          ((none) (detectProfileFallbackCycles profiles (optionOr (listTail keys) (list))))))))

(schema ProfileAccumulator
  (:f profiles (Map String GatewayProfile))
  (:f order (List String))
  (:f errs (List String)))

fn applyOneProfile acc: ProfileAccumulator p: (Map String rd/SExpr) intents: (Map String (Option String)) models: (Map String GatewayModel) -> ProfileAccumulator
  (mt (mapGet p "id")
    ((none) acc)
    ((some idExpr)
      (mt (asn_name idExpr "(:profile :id ...)")
        ((err e) (with acc :errs (listAppendOne acc.errs e)))
        ((ok pid)
          (let [(dupErr (if (mapHas? acc.profiles pid) (listAppendOne acc.errs (str "profile " pid " is defined twice")) acc.errs))
                (routesExprOpt (mapGet p "routes"))
                (routesList (mt routesExprOpt
                              ((none) (list))
                              ((some re) (mt re ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))))
                (routesEmptyErr (if (listEmpty? routesList) (listAppendOne dupErr (str "profile " pid ": :routes must be a non-empty list")) dupErr))
                (routesParsed (fold (fn [(st (Pair (List GatewayRoute) (List String))) (rf rd/SExpr)] -> (Pair (List GatewayRoute) (List String))
                                      (let [(rRes (parseProfileRoute rf pid intents models))]
                                        (mt (pairFirst rRes)
                                          ((none) (pair (pairFirst st) (listAppend (pairSecond st) (pairSecond rRes))))
                                          ((some route) (pair (listAppendOne (pairFirst st) route) (listAppend (pairSecond st) (pairSecond rRes)))))))
                                    (pair (list) (list))
                                    routesList))
                (routes (pairFirst routesParsed))
                (routeErrs (pairSecond routesParsed))
                (errs1 (listAppend routesEmptyErr routeErrs))
                (fbRes (mt (mapGet p "fallback")
                         ((none) (ok (none)))
                         ((some fbExpr)
                           (mt (asn_name fbExpr (str "profile " pid " :fallback"))
                             ((err e) (err e))
                             ((ok fb) (ok (some fb)))))))
                (errs2 (mt fbRes ((err e) (listAppendOne errs1 e)) ((ok _) errs1)))
                (fallback (resultOr fbRes (none)))
                (profile (GatewayProfile :id pid :routes routes :fallback fallback))]
            (ProfileAccumulator
              :profiles (mapSet acc.profiles pid profile)
              :order (listAppendOne acc.order pid)
              :errs errs2))))))

fn loopProfiles pForms: (List (Map String rd/SExpr)) acc: ProfileAccumulator intents: (Map String (Option String)) models: (Map String GatewayModel) -> ProfileAccumulator
  (mt (listHead pForms)
    ((none) acc)
    ((some p)
      (let [(tail (optionOr (listTail pForms) (list)))
            (nextAcc (applyOneProfile acc p intents models))]
        (loopProfiles tail nextAcc intents models))))

fn buildProfiles profileForms: (List (Map String rd/SExpr)) intents: (Map String (Option String)) models: (Map String GatewayModel) -> (Pair (Pair (Map String GatewayProfile) (List String)) (List String))
  (let [(parsed (loopProfiles profileForms (ProfileAccumulator :profiles (mapEmpty) :order (list) :errs (list)) intents models))
        (profiles parsed.profiles)
        (order parsed.order)
        (errs0 parsed.errs)
        (fbUnknownErrs (fold (fn [(acc (List String)) (pid String)] -> (List String)
                               (mt (mapGet profiles pid)
                                 ((none) acc)
                                 ((some pr)
                                   (mt pr.fallback
                                     ((none) acc)
                                     ((some fb) (if (not (mapHas? profiles fb)) (listAppendOne acc (str "profile " pid ": unknown fallback profile " fb)) acc))))))
                             (list)
                             order))
        (errs1 (listAppend errs0 fbUnknownErrs))
        (cycleOpt (detectProfileFallbackCycles profiles order))
        (finalErrs (mt cycleOpt ((some msg) (listAppendOne errs1 msg)) ((none) errs1)))]
    (pair (pair profiles order) finalErrs))

fn useOrderAdd order: (List String) uses: (Map String String) uf: String -> (List String)
  (if (mapHas? uses uf) order (listAppendOne order uf))

fn applyOneUse uses: (Pair (Map String String) (List String)) errs: (List String) u: (Map String rd/SExpr) profiles: (Map String GatewayProfile) -> (Pair (Pair (Map String String) (List String)) (List String))
  (mt (mapGet u "for")
    ((none) (pair uses errs))
    ((some forExpr)
      (mt (asn_name forExpr "(:use :for ...)")
        ((err e) (pair uses (listAppendOne errs e)))
        ((ok uf)
          (mt (mapGet u "profile")
            ((none) (pair uses (listAppendOne errs (str "use " uf " :profile must be a bare atom, found ()"))))
            ((some pExpr)
              (mt (asn_name pExpr (str "use " uf " :profile"))
                ((err e) (pair uses (listAppendOne errs e)))
                ((ok up)
                  (let [(upErr (if (not (mapHas? profiles up)) (listAppendOne errs (str "use " uf ": unknown profile " up)) errs))
                        (useMap (pairFirst uses))]
                    (pair (pair (mapSet useMap uf up) (useOrderAdd (pairSecond uses) useMap uf)) upErr))))))))))

fn loopUses uForms: (List (Map String rd/SExpr)) uses: (Pair (Map String String) (List String)) errs: (List String) profiles: (Map String GatewayProfile) -> (Pair (Pair (Map String String) (List String)) (List String))
  (mt (listHead uForms)
    ((none) (pair uses errs))
    ((some u)
      (let [(tail (optionOr (listTail uForms) (list)))
            (stepRes (applyOneUse uses errs u profiles))]
        (loopUses tail (pairFirst stepRes) (pairSecond stepRes) profiles))))

fn buildUses useForms: (List (Map String rd/SExpr)) profiles: (Map String GatewayProfile) -> (Pair (Pair (Map String String) (List String)) (List String))
  (loopUses useForms (pair (mapEmpty) (list)) (list) profiles)

fn gateway_config_v2_build! g: (Map String rd/SExpr) source: String registryPath: String -> (Pair GatewayTable (List String))
  (let [(provForms (getSubForms g "providers" ":provider"))
        (modelForms (getSubForms g "models" ":model"))
        (intentForms (getSubForms g "intents" ":intent"))
        (profileForms (getSubForms g "profiles" ":profile"))
        (useForms (getSubForms g "uses" ":use"))
        (listErrors (listAppend (pairSecond provForms) (listAppend (pairSecond modelForms) (listAppend (pairSecond intentForms) (listAppend (pairSecond profileForms) (pairSecond useForms))))))
        (provRes (buildProviders (pairFirst provForms) (defaultProviders!) listErrors))
        (providers (pairFirst provRes))
        (provErrs (pairSecond provRes))
        (regRes (calibrationRowsLoad! registryPath))
        (reg (mt regRes ((ok r) r) ((err _) (mapEmpty))))
        (regErr (mt regRes ((err e) (some e)) ((ok _) (none))))
        (modRes (buildModels (pairFirst modelForms) providers reg regErr))
        (models modRes.models)
        (modelOrder modRes.order)
        (modErrs modRes.errs)
        (warnings modRes.warns)
        (intRes (buildIntents (pairFirst intentForms)))
        (intents (pairFirst intRes))
        (intErrs (pairSecond intRes))
        (profRes (buildProfiles (pairFirst profileForms) intents models))
        (profiles (pairFirst (pairFirst profRes)))
        (profileOrder (pairSecond (pairFirst profRes)))
        (profErrs (pairSecond profRes))
        (useRes (buildUses (pairFirst useForms) profiles))
        (uses (pairFirst (pairFirst useRes)))
        (useOrder (pairSecond (pairFirst useRes)))
        (useErrs (pairSecond useRes))
        (allErrs0 (listAppend provErrs (listAppend modErrs (listAppend intErrs (listAppend profErrs useErrs)))))
        (defaultFromUse (mapGet uses "default"))
        (defaultRes (mt defaultFromUse
                      ((some dp) (pair (some dp) allErrs0))
                      ((none)
                        (mt (mapGet g "profile")
                          ((none) (pair (none) (listAppendOne allErrs0 "no default profile: add (:use :for default :profile ID)")))
                          ((some pExpr)
                            (mt (asn_name pExpr "(:gateway :profile ...)")
                              ((err e) (pair (none) (listAppendOne allErrs0 e)))
                              ((ok defName)
                                (if (not (mapHas? profiles defName))
                                  (pair (none) (listAppendOne allErrs0 (str ":profile " defName " names no defined profile")))
                                  (pair (some defName) allErrs0)))))))))
        (defaultProf (optionOr (pairFirst defaultRes) ""))
        (allErrs1 (pairSecond defaultRes))
        (allErrs2 (if (listEmpty? profileOrder)
                    (listAppendOne allErrs1 ":profiles must define at least one (:profile ...)")
                    allErrs1))
        (envWarns (fold (fn [(acc (List String)) (pid String)] -> (List String)
                          (let [(pv (optionOr (mapGet providers pid) (GatewayProvider :id pid :kind "" :base "" :keyEnv "" :timeoutSec 0.0 :rpm 0.0 :pool (none))))]
                            (if (and (not (stringEmpty? pv.keyEnv)) (listAny? (fn [(m GatewayModel)] -> Bool (= m.provider pid)) (mapValues models)))
                              (mt (envGet pv.keyEnv)
                                ((none) (listAppendOne acc (str "provider " pid ": key env " pv.keyEnv " is not set")))
                                ((some val) (if (stringEmpty? val) (listAppendOne acc (str "provider " pid ": key env " pv.keyEnv " is not set")) acc)))
                              acc)))
                        (list)
                        (providerOrder! (pairFirst provForms))))
        (allWarns (listAppend warnings envWarns))
        (table (GatewayTable
                 :version 2
                 :defaultProfile defaultProf
                 :profiles profiles
                 :profileOrder profileOrder
                 :models models
                 :modelOrder modelOrder
                 :providers providers
                 :intents intents
                 :uses uses
                 :useOrder useOrder
                 :source source
                 :registry registryPath
                 :registryError regErr
                 :warnings allWarns
                 :undeclaredIntents (mapEmpty)))]
    (pair table allErrs2))

fn gatewayConfigV2Build! g: (Map String rd/SExpr) source: String registryPath: String -> (Pair GatewayTable (List String))
  (gateway_config_v2_build! g source registryPath)


fn convertV1ToTable! v1: GatewayV1Config source: String -> GatewayTable
  (let [(profilesMap (fold (fn [(acc (Map String GatewayProfile)) (pairEntry (Pair String (List GatewayRoute)))] -> (Map String GatewayProfile)
                             (mapSet acc (pairFirst pairEntry) (GatewayProfile :id (pairFirst pairEntry) :routes (pairSecond pairEntry) :fallback (none))))
                           (mapEmpty)
                           (mapPairs v1.profiles)))
        (profileOrder (mapKeys v1.profiles))]
    (GatewayTable
      :version 1
      :defaultProfile v1.defaultProfile
      :profiles profilesMap
      :profileOrder profileOrder
      :models (mapEmpty)
      :modelOrder (list)
      :providers (defaultProviders!)
      :intents (mapEmpty)
      :uses (mapSet (mapEmpty) "default" v1.defaultProfile)
      :useOrder (list "default")
      :source source
      :registry ""
      :registryError (none)
      :warnings (list)
      :undeclaredIntents (mapEmpty)))

fn gateway_config_parse! text: String source: String registryPath: String -> (Result GatewayTable String)
  (let [(toks (lx/tokenize text))]
    (mt (mt (asnReadCheck text) ((some e) (err (ast/ParseError :msg e :line 0 :col 0))) ((none) (ast/readForms toks)))
      ((err e) (err (str e.msg)))
      ((ok forms)
        (if (!= (listLength forms) 1)
          (err (str "expected one (:gateway ...) form, found " (stringFromInt64 (listLength forms))))
          (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
            (mt (asn_props top (some ":gateway"))
              ((err e) (err e))
              ((ok g)
                (let [(v (mt (mapGet g "v")
                           ((none) 1)
                           ((some vExpr)
                             (mt (asn_scalar vExpr)
                               ((scalarInt n) n)
                               (_ 1)))))]
                  (if (= v 2)
                    (let [(built (gateway_config_v2_build! g source registryPath))
                          (tbl (pairFirst built))
                          (errs (pairSecond built))]
                      (if (not (listEmpty? errs))
                        (err (stringJoin errs "; "))
                        (ok tbl)))
                    (mt (gateway_profiles_parse text)
                      ((err e) (err e))
                      ((ok v1) (ok (convertV1ToTable! v1 source)))))))))))))

fn gatewayConfigParse! text: String source: String registryPath: String -> (Result GatewayTable String)
  (gateway_config_parse! text source registryPath)


fn intentLineLoop intents: (Map String (Option String)) cur: String acc: (List String) -> (List String)
  (if (or (stringEmpty? cur) (listContains? acc cur))
    (listReverse acc)
    (let [(nextAcc (cons cur acc))]
      (mt (mapGet intents cur)
        ((none) (listReverse nextAcc))
        ((some parentOpt)
          (mt parentOpt
            ((none) (listReverse nextAcc))
            ((some parent) (intentLineLoop intents parent nextAcc)))))))

fn gateway_intent_line table: GatewayTable intent: String -> (List String)
  (let [(cur (stringLower (lstripColons intent)))]
    (intentLineLoop table.intents cur (list)))

fn gatewayIntentLine table: GatewayTable intent: String -> (List String)
  (gateway_intent_line table intent)

fn routeFindIntent routes: (List GatewayRoute) targetIntent: String -> (Option (List String))
  (mt (listHead routes)
    ((none) (none))
    ((some r)
      (if (= r.intent targetIntent)
        (some r.chain)
        (routeFindIntent (optionOr (listTail routes) (list)) targetIntent))))

fn routeFindLine routes: (List GatewayRoute) line: (List String) -> (Option (List String))
  (mt (listHead line)
    ((none) (none))
    ((some i)
      (mt (routeFindIntent routes i)
        ((some ch) (some ch))
        ((none) (routeFindLine routes (optionOr (listTail line) (list)))))))

fn gateway_v2_route profile: GatewayProfile line: (List String) -> (List String)
  (mt (routeFindLine profile.routes line)
    ((some ch) ch)
    ((none)
      (mt (routeFindIntent profile.routes "any")
        ((some ch) ch)
        ((none) (list)))))

fn gatewayV2Route profile: GatewayProfile line: (List String) -> (List String)
  (gateway_v2_route profile line)

fn gateway_v2_entry! table: GatewayTable alias: String -> GatewayResolvedEntry
  (mt (mapGet table.models alias)
    ((none) (entryUnresolved alias))
    ((some m)
      (mt (mapGet table.providers m.provider)
        ((none) (entryUnresolved alias))
        ((some pv)
          (if (= pv.kind "cli")
            (entryResolved (GatewayEntry
                             :alias alias
                             :provider m.provider
                             :kind "cli"
                             :name m.name
                             :dispatch (str m.provider "/" m.name)
                             :params m.params
                             :upstream (GatewayUpstream :provider (str m.provider "-cli") :url (str "cli://" m.provider) :key "")
                             :timeoutSec 0.0
                             :rpm (none)
                             :pool none))
            (let [(key (if (stringEmpty? pv.keyEnv) "" (optionOr (envGet pv.keyEnv) "")))
                  (tSec (mt m.params.timeoutSec
                          ((some ts) ts)
                          ((none) pv.timeoutSec)))
                  (rpmVal (mt m.params.rpm
                            ((some r) (some r))
                            ((none) (if (> pv.rpm 0.0) (some pv.rpm) (none)))))]
              (entryResolved (GatewayEntry
                               :alias alias
                               :provider m.provider
                               :kind "openai"
                               :name m.name
                               :dispatch m.name
                               :params m.params
                               :upstream (GatewayUpstream :provider m.provider :url pv.base :key key)
                               :timeoutSec tSec
                               :rpm rpmVal
                               :pool pv.pool))))))))

fn gatewayV2Entry! table: GatewayTable alias: String -> GatewayResolvedEntry
  (gateway_v2_entry! table alias)

fn entriesStep! pairState: (Pair (List String) (List GatewayResolvedEntry)) a: String table: GatewayTable -> (Pair (List String) (List GatewayResolvedEntry))
  (if (listContains? (pairFirst pairState) a)
    pairState
    (pair (cons a (pairFirst pairState)) (cons (gateway_v2_entry! table a) (pairSecond pairState))))

fn entriesLoop! table: GatewayTable cur: String line: (List String) seen: (List String) tried: (List String) acc: (List GatewayResolvedEntry) -> (List GatewayResolvedEntry)
  (if (or (stringEmpty? cur) (listContains? seen cur))
    (listReverse acc)
    (mt (mapGet table.profiles cur)
      ((none) (listReverse acc))
      ((some prof)
        (let [(chain (gateway_v2_route prof line))
              (res (fold (fn [(st (Pair (List String) (List GatewayResolvedEntry))) (a String)] -> (Pair (List String) (List GatewayResolvedEntry))
                           (entriesStep! st a table))
                         (pair tried acc)
                         chain))
              (nextTried (pairFirst res))
              (nextAcc (pairSecond res))
              (nextSeen (cons cur seen))]
          (mt prof.fallback
            ((none) (listReverse nextAcc))
            ((some fb) (entriesLoop! table fb line nextSeen nextTried nextAcc)))))))

fn gateway_v2_entries! table: GatewayTable name: String intent: String -> (List GatewayResolvedEntry)
  (let [(line (gateway_intent_line table intent))]
    (entriesLoop! table name line (list) (list) (list)))

fn gatewayV2Entries! table: GatewayTable name: String intent: String -> (List GatewayResolvedEntry)
  (gateway_v2_entries! table name intent)

fn findModelByProviderAndName models: (List GatewayModel) target: String -> (Option GatewayModel)
  (mt (listHead models)
    ((none) (none))
    ((some m)
      (if (= (str m.provider "/" m.name) target)
        (some m)
        (findModelByProviderAndName (optionOr (listTail models) (list)) target))))

fn gateway_v2_alias_entry! table: GatewayTable model: String -> (Option GatewayResolvedEntry)
  (if (!= table.version 2)
    (none)
    (mt (mapGet table.models model)
      ((some _) (some (gateway_v2_entry! table model)))
      ((none)
        (mt (findModelByProviderAndName (mapValues table.models) model)
          ((some m) (some (gateway_v2_entry! table m.id)))
          ((none) (none))))))

fn gatewayV2AliasEntry! table: GatewayTable model: String -> (Option GatewayResolvedEntry)
  (gateway_v2_alias_entry! table model)

fn gateway_entry_label e: GatewayResolvedEntry -> String
  (mt e
    ((entryResolved entry) entry.alias)
    ((entryUnresolved alias) alias))

fn gatewayEntryLabel e: GatewayResolvedEntry -> String
  (gateway_entry_label e)

fn anyOnlyForProfile table: GatewayTable pid: String pr: GatewayProfile -> (List String)
  (let [(namedRoutes (filter (fn [(r GatewayRoute)] -> Bool (!= r.intent "any")) pr.routes))
        (named (map (fn [(r GatewayRoute)] -> String r.intent) namedRoutes))
        (leonIntents (list "auto" "code" "plan" "research" "reinforce"))]
    (fold (fn [(acc (List String)) (i String)] -> (List String)
            (let [(line (gateway_intent_line table i))
                  (hasMatch (listAny? (fn [(l String)] -> Bool (listContains? named l)) line))]
              (if hasMatch
                acc
                (listAppendOne acc (str "profile " pid ": Leon intent " i " resolves only to any")))))
          (list)
          leonIntents))

fn gateway_any_only_intents table: GatewayTable -> (List String)
  (fold (fn [(acc (List String)) (pid String)] -> (List String)
          (mt (mapGet table.profiles pid)
            ((none) acc)
            ((some pr) (listAppend acc (anyOnlyForProfile table pid pr)))))
        (list)
        table.profileOrder)

fn gatewayAnyOnlyIntents table: GatewayTable -> (List String)
  (gateway_any_only_intents table)

fn gateway_note_intent table: GatewayTable intent: String -> GatewayTable
  (if (and (= table.version 2) (and (not (stringEmpty? intent)) (not (mapHas? table.intents intent))))
    (let [(curCount (optionOr (mapGet table.undeclaredIntents intent) 0))
          (nextMap (mapSet table.undeclaredIntents intent (+ curCount 1)))]
      (with table :undeclaredIntents nextMap))
    table)

fn gatewayNoteIntent table: GatewayTable intent: String -> GatewayTable
  (gateway_note_intent table intent)

fn gateway_undeclared_intents table: GatewayTable -> (Map String Int64)
  table.undeclaredIntents

fn gatewayUndeclaredIntents table: GatewayTable -> (Map String Int64)
  (gateway_undeclared_intents table)


(enum ConfigKey
  (:c keyBuiltin [])
  (:c keyFiles [(parts (List (Pair String (Option (Pair Int64 Int64)))))]))

(schema ProfilesCache
  (:f key (Option ConfigKey))
  (:f result (Result GatewayTable String)))

(schema ProfileSelection
  (:f name String)
  (:f profile GatewayProfile)
  (:f source String))

(schema RouteEntries
  (:f name String)
  (:f entries (List GatewayResolvedEntry))
  (:f table GatewayTable))

(enum ProfileHealth
  (:c healthError [(error String) (source String)])
  (:c healthV1 [(name String) (routes (List GatewayRoute)) (source String)])
  (:c healthV2 [(name String) (routes (List GatewayRoute)) (fallback (Option String)) (source String)]))

(schema ConfigHealth
  (:f source String)
  (:f uses (List (Pair String String)))
  (:f profiles (List GatewayProfile))
  (:f models (List GatewayModel))
  (:f registry String)
  (:f registryError (Option String))
  (:f warnings (List String)))

fn gatewayProfilesPath home: String -> String
  (str (rstripSlash home) "/.asl/gateway.asn")

fn configKeyPart! path: String -> (Pair String (Option (Pair Int64 Int64)))
  (mt (fileStat path)
    ((ok st) (pair path (some (pair st.mtime st.size))))
    ((err _) (pair path (none))))

fn gatewayConfigKey! path: String registryPath: String -> ConfigKey
  (keyFiles (list (configKeyPart! path) (configKeyPart! registryPath)))

fn statEqual? a: (Option (Pair Int64 Int64)) b: (Option (Pair Int64 Int64)) -> Bool
  (mt a
    ((none) (none? b))
    ((some x)
      (mt b
        ((none) false)
        ((some y) (and (= (pairFirst x) (pairFirst y)) (= (pairSecond x) (pairSecond y)))))))

fn keyPartsEqual? a: (List (Pair String (Option (Pair Int64 Int64)))) b: (List (Pair String (Option (Pair Int64 Int64)))) -> Bool
  (mt (listHead a)
    ((none) (listEmpty? b))
    ((some x)
      (mt (listHead b)
        ((none) false)
        ((some y)
          (and (= (pairFirst x) (pairFirst y))
               (statEqual? (pairSecond x) (pairSecond y))
               (keyPartsEqual? (optionOr (listTail a) (list)) (optionOr (listTail b) (list))))))))

fn configKeyEqual? a: ConfigKey b: ConfigKey -> Bool
  (mt a
    ((keyBuiltin) (mt b ((keyBuiltin) true) (_ false)))
    ((keyFiles pa) (mt b ((keyFiles pb) (keyPartsEqual? pa pb)) (_ false))))

fn gatewayProfileHasRoutes? table: GatewayTable -> Bool
  (listAny? (fn [(name String)] -> Bool
              (mt (mapGet table.profiles name)
                ((some p) (not (listEmpty? p.routes)))
                ((none) false)))
            table.profileOrder)

fn gatewayNoRoutesError? message: String -> Bool
  (or (stringContains? message "routes must be a non-empty list")
      (or (stringContains? message "profiles must be a non-empty list")
          (stringContains? message "profiles must define at least one")))

fn gatewayProfilesLoadText! path: String exists: Bool text: (Result String String) registryPath: String -> (Result GatewayTable String)
  (if (not exists)
    (err (str "ERR_GATEWAY_NO_CONFIG: " path))
    (mt text
      ((err _) (err (str "ERR_GATEWAY_NO_CONFIG: " path)))
      ((ok t)
        (mt (gateway_config_parse! t path registryPath)
          ((err e) (if (gatewayNoRoutesError? e) (err (str "ERR_GATEWAY_NO_CONFIG: " path)) (err (str path ": " e))))
          ((ok tbl) (if (gatewayProfileHasRoutes? tbl) (ok tbl) (err (str "ERR_GATEWAY_NO_CONFIG: " path))))))))

fn gatewayLoadWarningLines path: String table: GatewayTable -> (List String)
  (map (fn [(w String)] -> String (str "[Gateway Config] " path ": " w)) table.warnings)

fn emptyProfilesCache -> ProfilesCache
  (ProfilesCache :key (none) :result (err "gateway profiles not loaded"))

fn cacheHit? cache: ProfilesCache key: ConfigKey -> Bool
  (mt cache.key
    ((none) false)
    ((some k) (configKeyEqual? k key)))

fn gatewayProfilesLoad! cache: ProfilesCache home: String registryPath: String -> (Pair ProfilesCache (Result GatewayTable String))
  (let [(path (gatewayProfilesPath home))
        (exists (fileExists? path))
        (key (if exists (gatewayConfigKey! path registryPath) (keyBuiltin)))]
    (if (cacheHit? cache key)
      (pair cache cache.result)
      (let [(text (if exists (fileReadString path) (err "not read")))
            (result (gatewayProfilesLoadText! path exists text registryPath))]
        (do
          (mt result
            ((ok tbl)
              (let [(lines (gatewayLoadWarningLines path tbl))]
                (if (and exists (not (listEmpty? lines))) (eprintln (stringJoin lines "\n")) ())))
            ((err _) ()))
          (pair (ProfilesCache :key (some key) :result result) result)))))

fn headerGet headers: (List (Pair String String)) name: String -> String
  (mt (listHead headers)
    ((none) "")
    ((some h)
      (if (= (stringLower (pairFirst h)) (stringLower name))
        (pairSecond h)
        (headerGet (optionOr (listTail headers) (list)) name))))

fn gatewayProfileName table: GatewayTable headers: (List (Pair String String)) envProfile: (Option String) -> (Result String String)
  (let [(fromHeader (stringTrim (headerGet headers "X-ASL-Profile")))
        (use (stringTrim (headerGet headers "X-ASL-Use")))
        (uses (if (= (mapSize table.uses) 0) (mapSet (mapEmpty) "default" table.defaultProfile) table.uses))
        (viaUse (if (and (stringEmpty? fromHeader) (not (stringEmpty? use)))
                  (mt (mapGet uses use)
                    ((none) (err (str "unknown use " use)))
                    ((some p) (ok p)))
                  (ok fromHeader)))]
    (mt viaUse
      ((err e) (err e))
      ((ok picked)
        (let [(fromEnv (stringTrim (optionOr envProfile "")))
              (name (cond
                      ((not (stringEmpty? picked)) picked)
                      ((not (stringEmpty? fromEnv)) fromEnv)
                      (else table.defaultProfile)))]
          (if (mapHas? table.profiles name)
            (ok name)
            (err (str "unknown profile " name)))))))

fn gatewayProfileSelect table: GatewayTable headers: (List (Pair String String)) envProfile: (Option String) -> (Result ProfileSelection String)
  (mt (gatewayProfileName table headers envProfile)
    ((err e) (err e))
    ((ok name)
      (mt (mapGet table.profiles name)
        ((none) (err (str "unknown profile " name)))
        ((some pr) (ok (ProfileSelection :name name :profile pr :source table.source))))))

fn isPlanIntent? i: String -> Bool
  (or (= i "plan") (= i "design") (= i "research"))

fn routeModelsNamed routes: (List GatewayRoute) i: String -> (Option (List String))
  (mt (listHead routes)
    ((none) (none))
    ((some r)
      (if (and (!= r.intent "any") (or (= r.intent i) (and (= r.intent "plan") (isPlanIntent? i))))
        (some r.models)
        (routeModelsNamed (optionOr (listTail routes) (list)) i))))

fn routeModelsAny routes: (List GatewayRoute) -> (Option (List String))
  (mt (listHead routes)
    ((none) (none))
    ((some r)
      (if (= r.intent "any")
        (some r.models)
        (routeModelsAny (optionOr (listTail routes) (list))))))

fn gatewayProfileModels routes: (List GatewayRoute) intent: String -> (Option (List String))
  (let [(i (stringLower (lstripColons intent)))]
    (mt (routeModelsNamed routes i)
      ((some ms) (some ms))
      ((none) (routeModelsAny routes))))

fn gatewayRouteEntries! table: GatewayTable headers: (List (Pair String String)) envProfile: (Option String) intent: String -> (Result RouteEntries String)
  (mt (gatewayProfileName table headers envProfile)
    ((err e) (err e))
    ((ok name)
      (if (= table.version 2)
        (let [(noted (gateway_note_intent table (stringLower (lstripColons intent))))]
          (ok (RouteEntries :name name :entries (gateway_v2_entries! noted name intent) :table noted)))
        (let [(routes (mt (mapGet table.profiles name) ((some pr) pr.routes) ((none) (list))))
              (models (optionOr (gatewayProfileModels routes intent) (list)))]
          (ok (RouteEntries :name name :entries (map (fn [(m String)] -> GatewayResolvedEntry (entryUnresolved m)) models) :table table))))))

fn gatewayProfileHealth loaded: (Result GatewayTable String) headers: (List (Pair String String)) envProfile: (Option String) path: String exists: Bool -> ProfileHealth
  (let [(errSource (if exists path "builtin"))]
    (mt loaded
      ((err e) (healthError e errSource))
      ((ok table)
        (mt (gatewayProfileSelect table headers envProfile)
          ((err e) (healthError e errSource))
          ((ok sel)
            (if (= table.version 2)
              (healthV2 sel.name sel.profile.routes sel.profile.fallback table.source)
              (healthV1 sel.name sel.profile.routes table.source)))))))

fn orderedUnique order: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (k String)] -> (List String) (if (listContains? acc k) acc (cons k acc))) (list) order))

fn gatewayConfigHealth loaded: (Result GatewayTable String) -> (Option ConfigHealth)
  (mt loaded
    ((err _) (none))
    ((ok table)
      (if (!= table.version 2)
        (none)
        (some (ConfigHealth
                :source table.source
                :uses (fold (fn [(acc (List (Pair String String))) (k String)] -> (List (Pair String String))
                              (mt (mapGet table.uses k) ((some p) (listAppend acc (list (pair k p)))) ((none) acc)))
                            (list)
                            (orderedUnique table.useOrder))
                :profiles (fold (fn [(acc (List GatewayProfile)) (k String)] -> (List GatewayProfile)
                                  (mt (mapGet table.profiles k) ((some p) (listAppend acc (list p))) ((none) acc)))
                                (list)
                                (orderedUnique table.profileOrder))
                :models (fold (fn [(acc (List GatewayModel)) (k String)] -> (List GatewayModel)
                                (mt (mapGet table.models k) ((some m) (listAppend acc (list m))) ((none) acc)))
                              (list)
                              (orderedUnique table.modelOrder))
                :registry table.registry
                :registryError table.registryError
                :warnings table.warnings)))))

fn asnQuoted s: String -> String
  (str "\"" (wire/asnEscape s) "\"")

fn fallbackAsn fallback: (Option String) -> String
  (mt fallback
    ((none) "")
    ((some fb) (if (stringEmpty? fb) "" (str " :fallback " fb))))

fn gatewayProfileAsn info: ProfileHealth -> String
  (mt info
    ((healthError e source) (str "(:error " (asnQuoted e) " :source " (asnQuoted source) ")"))
    ((healthV2 name routes fallback source)
      (let [(rs (stringJoin (map (fn [(r GatewayRoute)] -> String (str "(:intent " r.intent " :chain (" (stringJoin r.chain " ") "))")) routes) " "))]
        (str "(:name " name " :v 2 :source " (asnQuoted source) " :routes (" rs ")" (fallbackAsn fallback) ")")))
    ((healthV1 name routes source)
      (let [(rs (stringJoin (map (fn [(r GatewayRoute)] -> String (str "(:intent " r.intent " :models (" (stringJoin (map asnQuoted r.models) " ") "))")) routes) " "))]
        (str "(:name " name " :source " (asnQuoted source) " :routes (" rs "))"))))

fn modelAsn m: GatewayModel -> String
  (let [(cal (mt m.calibration
               ((none) "")
               ((some c) (if (stringEmpty? c) "" (str " :calibration " (asnQuoted c))))))
        (params (stringJoin (map (fn [(p (Pair String String))] -> String (str " :" (pairFirst p) " " (pairSecond p))) m.shown) ""))]
    (str "(:model :id " m.id " :provider " m.provider " :name " (asnQuoted m.name) cal params ")"))

fn gatewayConfigAsn cfg: (Option ConfigHealth) -> String
  (mt cfg
    ((none) "")
    ((some c)
      (let [(uses (stringJoin (map (fn [(u (Pair String String))] -> String (str "(:use :for " (pairFirst u) " :profile " (pairSecond u) ")")) c.uses) " "))
            (profiles (stringJoin (map (fn [(p GatewayProfile)] -> String (gatewayProfileAsn (healthV2 p.id p.routes p.fallback c.source))) c.profiles) " "))
            (models (stringJoin (map modelAsn c.models) " "))]
        (str " :gateway (:v 2 :source " (asnQuoted c.source) " :registry " (asnQuoted c.registry)
             " :uses (" uses ") :profiles (" profiles ") :models (" models "))"))))

fn gatewayConfigReceipt path: String registry: String status: String v: Int64 errors: (List String) warnings: (List String) extra: String -> String
  (str "(:configCheck :file " (asnQuoted path) " :v " (stringFromInt64 v) " :registry " (asnQuoted registry) " :status :" status
       " :errors (" (stringJoin (map asnQuoted errors) " ") ") :warnings (" (stringJoin (map asnQuoted warnings) " ") ")" extra ")")

fn gatewayConfigCheckText! text: String source: String registry: String -> (Pair String Int64)
  (let [(tokens (lx/tokenize text))
        (checked (mt (asnReadCheck text)
                   ((some e) (err e))
                   ((none)
                     (mt (ast/readForms tokens)
                       ((err e) (err e.msg))
                       ((ok forms) (ok forms))))))]
    (mt checked
      ((err e) (pair (gatewayConfigReceipt source registry "error" 0 (list e) (list) "") 1))
      ((ok forms)
        (if (!= (listLength forms) 1)
          (pair (gatewayConfigReceipt source registry "error" 0
                    (list (str "expected one (:gateway ...) form, found " (stringFromInt64 (listLength forms)))) (list) "") 1)
          (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
            (mt (asn_props top (some ":gateway"))
              ((err e)
                (let [(message (if (isStringLiteral? top)
                                 (str "expected (:gateway ...), found '" (stripQuotesAndUnescape (sexprRawText top)) "'")
                                 e))]
                  (pair (gatewayConfigReceipt source registry "error" 0 (list message) (list) "") 1)))
              ((ok g)
                (let [(version (mt (mapGet g "v")
                                ((none) 1)
                                ((some value)
                                  (mt (asn_scalar value)
                                    ((scalarInt n) n)
                                    (_ 1)))))]
                  (if (!= version 2)
                    (mt (gateway_profiles_parse text)
                      ((err e) (pair (gatewayConfigReceipt source registry "error" 1 (list e) (list) "") 1))
                      ((ok parsed)
                        (pair
                          (gatewayConfigReceipt source registry "ok" 1 (list) (list)
                            (str " :profiles " (stringFromInt64 (listLength (mapKeys parsed.profiles)))))
                          0)))
                    (let [(built (gateway_config_v2_build! g source registry))
                          (table (pairFirst built))
                          (errors (pairSecond built))
                          (warnings (if (listEmpty? errors) (listAppend table.warnings (gateway_any_only_intents table)) table.warnings))
                          (extra (str " :profiles " (stringFromInt64 (listLength (mapKeys table.profiles)))
                                      " :models " (stringFromInt64 (listLength (mapKeys table.models)))
                                      " :uses " (stringFromInt64 (listLength (mapKeys table.uses)))))
                          (status (if (listEmpty? errors) "ok" "error"))]
                      (pair (gatewayConfigReceipt source registry status 2 errors warnings extra)
                            (if (listEmpty? errors) 0 1))))))))))))
