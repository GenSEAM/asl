(module aslGateway/subPacing
  :x [fixed3 entryToken calOkRate freeCalScore qualityOf multiplierOf spreadWeight daysLeft subRemaining subRenews paceRpm pacePatchText modelsPaceCli!]
  :i [(config :a c)
      (localTime :a lt)
      (asl-cli/system :a sys)])

; (:m :ref SUB-MULTIPLIERS :do "asl run cliDispatch.asl models pace: proposes freePool and paidCheap :spread weights = value multiplier x quality and per-model :rpm that spends each subscription's remaining credit evenly until its renews date; reads the config, CAL rows and ~/.asl/subscriptions.asn, writes one patch file, never the config")

fn toInt f: Float64 -> Int64
  (optionOr (float64ToInt64 (round f)) 0)

fn pad3 n: Int64 -> String
  (cond ((< n 10) (str "00" (stringFromInt64 n))) ((< n 100) (str "0" (stringFromInt64 n))) (else (stringFromInt64 n)))

; (:m :do "a non-negative number with three decimals, the form the patch rows use")
fn fixed3 f: Float64 -> String
  (let [(milli (toInt (* f 1000.0)))]
    (str (stringFromInt64 (/ milli 1000)) "." (pad3 (mod milli 1000))))

fn q s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

; (:m :do "the token after key inside the entry that starts with (provider \"name\" in text, or none; a newline reads as one space because CAL rows wrap, and an entry ends at its first closing paren")
fn entryToken text: String provider: String name: String key: String -> String
  (let [(needle (str "(" provider " " (q name) " "))]
    (match (stringIndexOf (stringReplace (stringReplace text " \n" " ") "\n" " ") needle)
      ((none) "none")
      ((some i)
        (let [(flat (stringReplace (stringReplace text " \n" " ") "\n" " "))
              (rest (optionOr (stringSlice flat (+ i (stringLength needle)) (stringLength flat)) ""))
              (line (optionOr (listHead (stringSplit rest ")")) ""))
              (k (str key " "))]
          (match (stringIndexOf line k)
            ((none) "none")
            ((some j) (stringTrim (optionOr (listHead (stringSplit (optionOr (stringSlice line (+ j (stringLength k)) (stringLength line)) "") " ")) "none"))))))))

; (:m :do "the share of the FREE-PROBE row's :vps and :mac probes that answered 200; a model with no probe counts 0.5")
fn calOkRate calText: String provider: String name: String -> Float64
  (let [(seen (filter (fn [(s String)] -> Bool (!= s "none")) (list (entryToken calText provider name ":vps") (entryToken calText provider name ":mac"))))
        (ok (listLength (filter (fn [(s String)] -> Bool (= s "200")) seen)))]
    (if (listEmpty? seen) 0.5 (/ (int64ToFloat64 ok) (int64ToFloat64 (listLength seen)))))

; (:m :ref FREE-CAL :do "the forms of one head in a FREE-CAL text, each up to the next form of that head; a newline reads as one space")
fn calForms text: String head: String -> (List String)
  (optionOr (listTail (stringSplit (stringReplace (stringReplace text " \n" " ") "\n" " ") (str "(" head " "))) (list))

fn formToken form: String key: String -> String
  (let [(k (str key " "))]
    (match (stringIndexOf form k)
      ((none) "none")
      ((some j) (stringReplace (stringTrim (optionOr (listHead (stringSplit (optionOr (stringSlice form (+ j (stringLength k)) (stringLength form)) "") " ")) "none")) ")" ""))))

; (:m :ref FREE-CAL :do "the FREE-CAL score of a gateway model row: its (:cell ...) for the intent, else its overall (:modelScore ...); a null score (infra failures only) or no row is none; intent empty asks for the overall score")
fn freeCalScore scoresText: String alias: String intent: String -> (Option Float64)
  (let [(mine (fn [(f String)] -> Bool (stringStartsWith? f (str ":model " alias " "))))
        (cell (listHead (filter (fn [(f String)] -> Bool (and (mine f) (= (formToken f ":intent") intent))) (calForms scoresText ":cell"))))
        (overall (fn [] -> (Option Float64) (match (listHead (filter mine (calForms scoresText ":modelScore")))
                                              ((some f) (stringToFloat64 (formToken f ":score")))
                                              ((none) none))))]
    (match cell
      ((some f) (match (stringToFloat64 (formToken f ":score")) ((some s) (some s)) ((none) (overall))))
      ((none) (overall))))

; (:m :do "quality in 0..1: the FREE-CAL score of the model row for the intent when it exists, else the probe ok rate")
fn qualityOf scoresText: String calText: String alias: String intent: String provider: String name: String -> Float64
  (match (freeCalScore scoresText alias intent)
    ((some s) (if (> s 1.0) 1.0 (if (< s 0.0) 0.0 s)))
    ((none) (calOkRate calText provider name)))

; (:m :do "the value multiplier recorded in CAL/subMultipliers: a number, free, or unknown")
fn multiplierOf multText: String provider: String name: String -> String
  (let [(x (entryToken multText provider name ":x"))]
    (if (= x "none") "unknown" x))

fn freeName? name: String -> Bool
  (or (stringEndsWith? name ":free") (stringEndsWith? name "-free"))

fn freeTier? provider: String -> Bool
  (listContains? (list "gemini" "groq" "nim" "ollama" "ifm" "openrouter" "vercel" "together") provider)

; (:m :do "weight = round(multiplier x quality), at least 1; a free model counts as multiplier 8, level with the best credit models; unknown and per-token paid are 1")
fn spreadWeight multText: String scoresText: String calText: String alias: String intent: String provider: String name: String -> Int64
  (let [(x (multiplierOf multText provider name))
        (qual (qualityOf scoresText calText alias intent provider name))
        (num (stringToFloat64 x))
        (raw (match num
               ((some m) (* m qual))
               ((none) (if (or (= x "free") (or (freeName? name) (and (freeTier? provider) (!= (entryToken calText provider name ":vps") "none")))) (* 8.0 qual) 1.0))))]
    (max 1 (toInt raw)))

fn dateDays d: String -> Int64
  (let [(parts (stringSplit (optionOr (listHead (stringSplit d " ")) "") "-"))]
    (lt/daysFromCivil (optionOr (stringToInt64 (optionOr (listGet parts 0) "1970")) 1970) (optionOr (stringToInt64 (optionOr (listGet parts 1) "1")) 1) (optionOr (stringToInt64 (optionOr (listGet parts 2) "1")) 1)))

; (:m :do "whole days from today to the renews date, at least 1")
fn daysLeft today: String renews: String -> Int64
  (max 1 (- (dateDays renews) (dateDays today)))

fn subBlock subsText: String provider: String -> String
  (match (stringIndexOf subsText (str "(:sub :id " provider " "))
    ((none) "")
    ((some i) (optionOr (listHead (stringSplit (optionOr (stringSlice subsText i (stringLength subsText)) "") "\n")) "")))

fn quotedAfter s: String key: String -> String
  (match (stringIndexOf s (str key " \""))
    ((none) "")
    ((some i) (optionOr (listHead (stringSplit (optionOr (stringSlice s (+ i (+ (stringLength key) 2)) (stringLength s)) "") "\"")) "")))

; (:m :do "the renews date of a subscription in ~/.asl/subscriptions.asn, or empty")
fn subRenews subsText: String provider: String -> String
  (quotedAfter (subBlock subsText provider) ":renews")

; (:m :do "remaining percent of the monthly window, 100 - usedPercent of its (:monthly ...) row, or none when the ledger has no figure")
fn subRemaining subsText: String provider: String -> (Option Float64)
  (let [(b (subBlock subsText provider))]
    (match (stringIndexOf b "(:monthly ")
      ((none) none)
      ((some i)
        (let [(seg (optionOr (stringSlice b i (stringLength b)) ""))]
          (match (stringIndexOf seg ":usedPercent ")
            ((none) none)
            ((some j) (match (stringToFloat64 (stringReplace (optionOr (listHead (stringSplit (optionOr (stringSlice seg (+ j 13) (stringLength seg)) "") " ")) "") ")" ""))
                        ((some u) (some (- 100.0 u)))
                        ((none) none))))))))

; (:m :do "requests per minute that spend the remaining share of a monthly request allowance evenly over the days left; with no remaining figure the full allowance is spread over 30 days")
fn paceRpm reqMonth: Float64 remaining: (Option Float64) days: Int64 -> Float64
  (match remaining
    ((some r) (/ (* reqMonth (/ r 100.0)) (* (int64ToFloat64 days) 1440.0)))
    ((none) (/ reqMonth 43200.0)))

fn poolRoutes table: c/GatewayTable profile: String -> (List c/GatewayRoute)
  (match (mapGet table.profiles profile) ((some p) p.routes) ((none) (list)))

fn rowOf table: c/GatewayTable alias: String -> (Pair String String)
  (match (mapGet table.models alias) ((some m) (pair m.provider m.name)) ((none) (pair "" "")))

fn routeSpread table: c/GatewayTable multText: String scoresText: String calText: String profile: String r: c/GatewayRoute -> String
  (str "(:set :profile " profile " :intent " r.intent " :spread ("
       (stringJoin (map (fn [(a String)] -> String
                          (let [(pn (rowOf table a))]
                            (str "(" a " " (stringFromInt64 (spreadWeight multText scoresText calText a r.intent (pairFirst pn) (pairSecond pn))) ")")))
                        r.chain) " ")
       ") :cooldownSec 300)")

fn poolAliases table: c/GatewayTable -> (List String)
  (fold (fn [(acc (List String)) (r c/GatewayRoute)] -> (List String)
          (fold (fn [(a2 (List String)) (a String)] -> (List String) (if (listContains? a2 a) a2 (listAppend a2 (list a)))) acc r.chain))
        (list) (listAppend (poolRoutes table "freePool") (poolRoutes table "paidCheap")))

fn ccPlan? table: c/GatewayTable alias: String -> Bool
  (let [(pn (rowOf table alias))]
    (and (= (pairFirst pn) "commandCode") (not (freeName? (pairSecond pn)))))

; (:m :do "the patch: per-route spreads, per-model rpm rows (opencodeGo from each model's :reqMonth, commandCode from the shared plan request pool by weight share) and per-provider budget rows")
fn pacePatchText table: c/GatewayTable multText: String scoresText: String calText: String subsText: String today: String host: String ccPoolMonth: Float64 -> String
  (let [(spreads (fold (fn [(acc (List String)) (prof String)] -> (List String)
                         (listAppend acc (map (fn [(r c/GatewayRoute)] -> String (routeSpread table multText scoresText calText prof r)) (poolRoutes table prof))))
                       (list) (list "freePool" "paidCheap")))
        (aliases (poolAliases table))
        (ocDays (daysLeft today (subRenews subsText "opencodeGo")))
        (ocRem (subRemaining subsText "opencodeGo"))
        (ccDays (daysLeft today (subRenews subsText "commandCode")))
        (ccRem (subRemaining subsText "commandCode"))
        (wOf (fn [(a String)] -> Int64 (let [(pn (rowOf table a))] (spreadWeight multText scoresText calText a "" (pairFirst pn) (pairSecond pn)))))
        (ccAliases (filter (fn [(a String)] -> Bool (ccPlan? table a)) aliases))
        (ccTotal (fold (fn [(acc Int64) (a String)] -> Int64 (+ acc (wOf a))) 0 ccAliases))
        (ocRows (fold (fn [(acc (List String)) (a String)] -> (List String)
                        (let [(pn (rowOf table a))]
                          (if (!= (pairFirst pn) "opencodeGo") acc
                            (match (stringToFloat64 (entryToken multText "opencodeGo" (pairSecond pn) ":reqMonth"))
                              ((none) acc)
                              ((some rm) (listAppend acc (list (str "(" a " :rpm " (fixed3 (paceRpm rm ocRem ocDays)) " :why " (q (str "opencodeGo " (pairSecond pn) ": monthly requests x remaining over " (stringFromInt64 ocDays) " days")) ")"))))))))
                      (list) aliases))
        (ccRows (if (= ccTotal 0) (list)
                  (map (fn [(a String)] -> String
                         (let [(share (/ (int64ToFloat64 (wOf a)) (int64ToFloat64 ccTotal)))]
                           (str "(" a " :rpm " (fixed3 (* share (paceRpm ccPoolMonth ccRem ccDays))) " :why " (q (str "commandCode plan pool share " (fixed3 share))) ")")))
                       ccAliases)))
        (remText (fn [(r (Option Float64))] -> String (match r ((some v) (fixed3 v)) ((none) "unknown"))))]
    (str "(:patch :id " (q (str "SUB-PACE-" today)) " :host " host " :apply \"by the lead; replaces each named route's :spread (chains unchanged) and sets :rpm on the named model rows\"\n"
         "  :spreads (" (stringJoin spreads "\n            ") ")\n"
         "  :rpm (" (stringJoin (listAppend ocRows ccRows) "\n        ") ")\n"
         "  :budgets ((:budget :provider opencodeGo :renews " (q (subRenews subsText "opencodeGo")) " :remainingPercent " (remText ocRem) " :daysLeft " (stringFromInt64 ocDays) ")\n"
         "             (:budget :provider commandCode :renews " (q (subRenews subsText "commandCode")) " :remainingPercent " (remText ccRem) " :daysLeft " (stringFromInt64 ccDays) " :poolRequestsMonth " (fixed3 ccPoolMonth) ")))\n"))

fn argAfter args: (List String) flag: String d: String -> String
  (match (listHead args)
    ((none) d)
    ((some a) (if (= a flag) (optionOr (listGet args 1) d) (argAfter (optionOr (listTail args) (list)) flag d))))

fn ! readOr! path: String -> String
  (resultOr (fileReadString path) "")

; (:m :do "models pace --date YYYY-MM-DD [--config P] [--cal P] [--mult P] [--scores P] [--subs P] [--out FILE] [--host NAME] [--ccPool N]: writes the patch to --out (default ~/.asl/run/gwsync/subMultipliers.patch); the config is only read")
fn ! modelsPaceCli! args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") "/tmp"))
        (root (optionOr (envGet "ASL_GATEWAY_ROOT") "."))
        (source (argAfter args "--config" (c/gatewayProfilesPath home)))
        (calDir (str root "/.asl/mem/work/CAL"))
        (today (argAfter args "--date" ""))
        (out (argAfter args "--out" (str home "/.asl/run/gwsync/subMultipliers.patch")))
        (ccPool (optionOr (stringToFloat64 (argAfter args "--ccPool" "75000")) 75000.0))]
    (if (stringEmpty? today)
      (do (sys/sayErr! "(:modelsPace :status :error :why \"--date YYYY-MM-DD is required\")") (ok 2))
      (match (fileReadString source)
        ((err e) (do (sys/sayErr! (str "(:modelsPace :status :error :why " (q (str "cannot read " source ": " e)) ")")) (ok 1)))
        ((ok text)
          (match (c/gatewayConfigParse! text source "")
            ((err e) (do (sys/sayErr! (str "(:modelsPace :status :error :why " (q e) ")")) (ok 1)))
            ((ok table)
              (let [(patch (pacePatchText table (readOr! (argAfter args "--mult" (str calDir "/subMultipliers-20261028.asn")))
                                          (readOr! (argAfter args "--scores" (str calDir "/freeCal-20261028.asn")))
                                          (readOr! (argAfter args "--cal" (str calDir "/freeModels.asn")))
                                          (readOr! (argAfter args "--subs" (str home "/.asl/subscriptions.asn")))
                                          today (argAfter args "--host" "local") ccPool))
                    (wrote (fileWrite out patch))]
                (do (sys/say! (str "(:modelsPace :status " (if (ok? wrote) ":ok" ":error") " :patch " (q out) " :configWritten false)"))
                    (ok (if (ok? wrote) 0 1))))))))))
