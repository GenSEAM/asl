(module aslGateway/subPacing
  :x [PaceSet RouteEdit fixed3 entryToken calOkRate freeCalScore saturatedQuality qualityOf multiplierOf spreadWeight daysLeft subRemaining subRenews paceRpm pacePatchText modelsPaceCli!]
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
; (:m :ref FREE-CAL :do "the FREE-CAL cell of a model for an intent, by gateway model row id, else by provider and model name, so a host whose row ids differ from the calibrating host still finds its cells")
fn cellOf scoresText: String alias: String provider: String name: String intent: String -> (Option String)
  (let [(cells (filter (fn [(f String)] -> Bool (= (formToken f ":intent") intent)) (calForms scoresText ":cell")))
        (byId (listHead (filter (fn [(f String)] -> Bool (stringStartsWith? f (str ":model " alias " "))) cells)))]
    (match byId
      ((some f) (some f))
      ((none) (if (stringEmpty? name) none (listHead (filter (fn [(f String)] -> Bool (stringContains? f (str " :provider " provider " :name " (q name) " "))) cells))))))

fn freeCalScore scoresText: String alias: String provider: String name: String intent: String -> (Option Float64)
  (let [(overall (fn [] -> (Option Float64) (match (listHead (filter (fn [(f String)] -> Bool (stringStartsWith? f (str ":model " alias " "))) (calForms scoresText ":modelScore")))
                                              ((some f) (stringToFloat64 (formToken f ":score")))
                                              ((none) none))))]
    (match (cellOf scoresText alias provider name intent)
      ((some f) (match (stringToFloat64 (formToken f ":score")) ((some s) (some s)) ((none) (overall))))
      ((none) (overall))))

; (:m :ref FREE-CAL :do "grade, plan, research and any saturate in FREE-CAL-20261028 (the top models tie at 1.00), so there quality ranks by reliability and speed")
fn saturated? intent: String -> Bool
  (listContains? (list "grade" "plan" "research" "any") intent)

fn clamp01 s: Float64 -> Float64
  (if (> s 1.0) 1.0 (if (< s 0.0) 0.0 s))

; (:m :ref FREE-CAL :do "a saturated intent's cell quality: score x n/(n+infra) x 1/(1+ms/10000), the speed term freelimits used; none when the cell counted no call")
fn saturatedQuality scoresText: String alias: String provider: String name: String intent: String -> (Option Float64)
  (match (cellOf scoresText alias provider name intent)
    ((none) none)
    ((some f)
      (let [(n (optionOr (stringToFloat64 (formToken f ":n")) 0.0))
            (infra (optionOr (stringToFloat64 (formToken f ":infra")) 0.0))
            (ms (optionOr (stringToFloat64 (formToken f ":ms")) 0.0))
            (score (optionOr (stringToFloat64 (formToken f ":score")) 0.0))]
        (if (<= (+ n infra) 0.0) none
          (some (* (clamp01 score) (* (/ n (+ n infra)) (/ 1.0 (+ 1.0 (/ ms 10000.0))))))))))

; (:m :do "quality in 0..1: on a saturated intent the reliability-and-speed quality of its FREE-CAL cell; otherwise the FREE-CAL score (cell, else overall); else the probe ok rate")
fn qualityOf scoresText: String calText: String alias: String intent: String provider: String name: String -> Float64
  (match (if (saturated? intent) (saturatedQuality scoresText alias provider name intent) none)
    ((some s) s)
    ((none) (match (freeCalScore scoresText alias provider name intent)
              ((some s) (clamp01 s))
              ((none) (calOkRate calText provider name)))))

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

; (:m :do "one --set row: a model field the patch sets, its value as ASN text")
(schema PaceSet
  (:f alias String)
  (:f key String)
  (:f value String))

(schema RpmRow
  (:f alias String)
  (:f rpm Float64)
  (:f why String))

fn kept drops: (List String) chain: (List String) -> (List String)
  (filter (fn [(a String)] -> Bool (not (listContains? drops a))) chain)

; (:m :do "one per-route lead decision: --dropRoute ALIAS PROFILE/INTENT (weight 0) takes the alias out of that one chain, --weight ALIAS PROFILE/INTENT N fixes its spread weight there")
(schema RouteEdit
  (:f alias String)
  (:f route String)
  (:f weight Int64))

fn routeEditFor edits: (List RouteEdit) alias: String key: String -> (Option RouteEdit)
  (listHead (filter (fn [(e RouteEdit)] -> Bool (and (= e.alias alias) (= e.route key))) edits))

fn routeWeights table: c/GatewayTable multText: String scoresText: String calText: String drops: (List String) edits: (List RouteEdit) prof: String r: c/GatewayRoute -> (List (Pair String Int64))
  (let [(key (str prof "/" r.intent))
        (members (filter (fn [(a String)] -> Bool (match (routeEditFor edits a key) ((some e) (> e.weight 0)) ((none) true))) (kept drops r.chain)))]
    (map (fn [(a String)] -> (Pair String Int64)
           (match (routeEditFor edits a key)
             ((some e) (pair a e.weight))
             ((none) (let [(pn (rowOf table a))] (pair a (spreadWeight multText scoresText calText a r.intent (pairFirst pn) (pairSecond pn)))))))
         members))

fn routeSpread ws: (List (Pair String Int64)) profile: String r: c/GatewayRoute -> String
  (str "(:set :profile " profile " :intent " r.intent " :spread ("
       (stringJoin (map (fn [(p (Pair String Int64))] -> String (str "(" (pairFirst p) " " (stringFromInt64 (pairSecond p)) ")")) ws) " ")
       ") :cooldownSec 300)")

fn oldWeight r: c/GatewayRoute a: String -> String
  (match (listHead (filter (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) a)) r.spread))
    ((some p) (stringFromInt64 (pairSecond p)))
    ((none) "none"))

fn optFixed o: (Option Float64) -> String
  (match o ((some v) (fixed3 v)) ((none) "none"))

; (:m :do "the configured value of a model field a --set row replaces, as text; none when unset, unknown for a field this tool does not read")
fn oldParam table: c/GatewayTable alias: String key: String -> String
  (match (mapGet table.models alias)
    ((none) "none")
    ((some m)
      (cond
        ((= key ":temperature") (optFixed m.params.temperature))
        ((= key ":timeoutSec") (optFixed m.params.timeoutSec))
        ((= key ":rpm") (optFixed m.params.rpm))
        ((= key ":retry") (match m.params.retry ((some p) (str "(:max " (stringFromInt64 p.maxAttempts) ")")) ((none) "none")))
        (else "unknown"))))

fn change alias: String field: String old: String new: String -> String
  (str "(" alias " " field " " old " " new ")")

fn poolAliases table: c/GatewayTable -> (List String)
  (fold (fn [(acc (List String)) (r c/GatewayRoute)] -> (List String)
          (fold (fn [(a2 (List String)) (a String)] -> (List String) (if (listContains? a2 a) a2 (listAppend a2 (list a)))) acc r.chain))
        (list) (listAppend (poolRoutes table "freePool") (poolRoutes table "paidCheap")))

fn ccPlan? table: c/GatewayTable alias: String -> Bool
  (let [(pn (rowOf table alias))]
    (and (= (pairFirst pn) "commandCode") (not (freeName? (pairSecond pn)))))

; (:m :do "the patch: per-route spreads without the dropped aliases, per-model rpm rows (opencodeGo from each model's :reqMonth, commandCode from the shared plan request pool by overall weight share), the --set model fields, the drops, per-provider budget rows and every (alias field old new) change")
fn pacePatchText table: c/GatewayTable multText: String scoresText: String calText: String subsText: String today: String host: String ccPoolMonth: Float64 sets: (List PaceSet) drops: (List String) edits: (List RouteEdit) -> String
  (let [(routes (fold (fn [(acc (List (Pair String c/GatewayRoute))) (prof String)] -> (List (Pair String c/GatewayRoute))
                        (listAppend acc (map (fn [(r c/GatewayRoute)] -> (Pair String c/GatewayRoute) (pair prof r)) (poolRoutes table prof))))
                      (list) (list "freePool" "paidCheap")))
        (weighed (map (fn [(pr (Pair String c/GatewayRoute))] -> (Pair (Pair String c/GatewayRoute) (List (Pair String Int64)))
                        (pair pr (routeWeights table multText scoresText calText drops edits (pairFirst pr) (pairSecond pr))))
                      routes))
        (spreads (map (fn [(w (Pair (Pair String c/GatewayRoute) (List (Pair String Int64))))] -> String
                        (routeSpread (pairSecond w) (pairFirst (pairFirst w)) (pairSecond (pairFirst w))))
                      weighed))
        (spreadChanges (fold (fn [(acc (List String)) (w (Pair (Pair String c/GatewayRoute) (List (Pair String Int64))))] -> (List String)
                               (let [(prof (pairFirst (pairFirst w)))
                                     (r (pairSecond (pairFirst w)))
                                     (field (str "spread/" prof "/" r.intent))
                                     (moved (fold (fn [(a2 (List String)) (p (Pair String Int64))] -> (List String)
                                                    (let [(old (oldWeight r (pairFirst p)))
                                                          (new (stringFromInt64 (pairSecond p)))]
                                                      (if (= old new) a2 (listAppend a2 (list (change (pairFirst p) field old new))))))
                                                  (list) (pairSecond w)))
                                     (gone (map (fn [(a String)] -> String (change a (str "chain/" prof "/" r.intent) "member" "dropped"))
                                                (filter (fn [(a String)] -> Bool (or (listContains? drops a) (match (routeEditFor edits a (str prof "/" r.intent)) ((some e) (= e.weight 0)) ((none) false)))) r.chain)))]
                                 (listAppend acc (listAppend moved gone))))
                             (list) weighed))
        (aliases (kept drops (poolAliases table)))
        (ocDays (daysLeft today (subRenews subsText "opencodeGo")))
        (ocRem (subRemaining subsText "opencodeGo"))
        (ccDays (daysLeft today (subRenews subsText "commandCode")))
        (ccRem (subRemaining subsText "commandCode"))
        (wOf (fn [(a String)] -> Int64 (let [(pn (rowOf table a))] (spreadWeight multText scoresText calText a "" (pairFirst pn) (pairSecond pn)))))
        (ccAliases (filter (fn [(a String)] -> Bool (ccPlan? table a)) aliases))
        (ccTotal (fold (fn [(acc Int64) (a String)] -> Int64 (+ acc (wOf a))) 0 ccAliases))
        (ocRows (fold (fn [(acc (List RpmRow)) (a String)] -> (List RpmRow)
                        (let [(pn (rowOf table a))]
                          (if (!= (pairFirst pn) "opencodeGo") acc
                            (match (stringToFloat64 (entryToken multText "opencodeGo" (pairSecond pn) ":reqMonth"))
                              ((none) acc)
                              ((some rm) (listAppend acc (list (RpmRow :alias a :rpm (paceRpm rm ocRem ocDays)
                                                                       :why (str "opencodeGo " (pairSecond pn) ": monthly requests x remaining over " (stringFromInt64 ocDays) " days")))))))))
                      (list) aliases))
        (ccRows (if (= ccTotal 0) (list)
                  (map (fn [(a String)] -> RpmRow
                         (let [(share (/ (int64ToFloat64 (wOf a)) (int64ToFloat64 ccTotal)))]
                           (RpmRow :alias a :rpm (* share (paceRpm ccPoolMonth ccRem ccDays)) :why (str "commandCode plan pool share " (fixed3 share)))))
                       ccAliases)))
        (rpmRows (listAppend ocRows ccRows))
        (rpmText (map (fn [(x RpmRow)] -> String (str "(" x.alias " :rpm " (fixed3 x.rpm) " :why " (q x.why) ")")) rpmRows))
        (rpmChanges (filter (fn [(s String)] -> Bool (not (stringEmpty? s)))
                            (map (fn [(x RpmRow)] -> String (let [(old (oldRpm table x.alias))] (if (= old (fixed3 x.rpm)) "" (change x.alias ":rpm" old (fixed3 x.rpm))))) rpmRows)))
        (setText (map (fn [(s PaceSet)] -> String (str "(:set :model " s.alias " " s.key " " s.value ")")) sets))
        (setChanges (map (fn [(s PaceSet)] -> String (change s.alias s.key (oldParam table s.alias s.key) s.value)) sets))
        (remText (fn [(r (Option Float64))] -> String (match r ((some v) (fixed3 v)) ((none) "unknown"))))]
    (str "(:patch :id " (q (str "SUB-PACE-" today)) " :host " host " :apply \"by the lead; replaces each named route's :spread, removes the :drops aliases from every chain and applies the :decisions route edits, sets :rpm and the :models fields on the named model rows; :changes lists (alias field old new)\"\n"
         "  :spreads (" (stringJoin spreads "\n            ") ")\n"
         "  :rpm (" (stringJoin rpmText "\n        ") ")\n"
         "  :models (" (stringJoin setText "\n           ") ")\n"
         "  :drops (" (stringJoin drops " ") ")\n"
         "  :decisions (" (stringJoin (map routeEditRow edits) "\n              ") ")\n"
         "  :budgets ((:budget :provider opencodeGo :renews " (q (subRenews subsText "opencodeGo")) " :remainingPercent " (remText ocRem) " :daysLeft " (stringFromInt64 ocDays) ")\n"
         "             (:budget :provider commandCode :renews " (q (subRenews subsText "commandCode")) " :remainingPercent " (remText ccRem) " :daysLeft " (stringFromInt64 ccDays) " :poolRequestsMonth " (fixed3 ccPoolMonth) "))\n"
         "  :changes (" (stringJoin (listAppend spreadChanges (listAppend rpmChanges setChanges)) "\n            ") "))\n"))

fn oldRpm table: c/GatewayTable alias: String -> String
  (match (mapGet table.models alias) ((some m) (optFixed m.params.rpm)) ((none) "none"))

fn argAfter args: (List String) flag: String d: String -> String
  (match (listHead args)
    ((none) d)
    ((some a) (if (= a flag) (optionOr (listGet args 1) d) (argAfter (optionOr (listTail args) (list)) flag d))))

; (:m :do "every value after each occurrence of flag")
fn argsAll args: (List String) flag: String -> (List String)
  (match (listHead args)
    ((none) (list))
    ((some a) (if (and (= a flag) (>= (listLength args) 2))
                (cons (optionOr (listGet args 1) "") (argsAll (listDrop args 2) flag))
                (argsAll (listDrop args 1) flag))))

; (:m :do "every --set ALIAS :key VALUE triple")
fn setsOf args: (List String) -> (List PaceSet)
  (match (listHead args)
    ((none) (list))
    ((some a) (if (and (= a "--set") (>= (listLength args) 4))
                (cons (PaceSet :alias (optionOr (listGet args 1) "") :key (optionOr (listGet args 2) "") :value (optionOr (listGet args 3) "")) (setsOf (listDrop args 4)))
                (setsOf (listDrop args 1)))))

; (:m :do "every --dropRoute ALIAS PROFILE/INTENT (weight 0) and --weight ALIAS PROFILE/INTENT N row; a weight that is not a whole number of at least 1 reads as -1 and fails validation")
fn routeEditsOf args: (List String) -> (List RouteEdit)
  (match (listHead args)
    ((none) (list))
    ((some a)
      (cond
        ((and (= a "--dropRoute") (>= (listLength args) 3))
          (cons (RouteEdit :alias (optionOr (listGet args 1) "") :route (optionOr (listGet args 2) "") :weight 0) (routeEditsOf (listDrop args 3))))
        ((and (= a "--weight") (>= (listLength args) 4))
          (cons (RouteEdit :alias (optionOr (listGet args 1) "") :route (optionOr (listGet args 2) "") :weight (let [(n (optionOr (stringToInt64 (optionOr (listGet args 3) "")) -1))] (if (< n 1) -1 n))) (routeEditsOf (listDrop args 4))))
        (else (routeEditsOf (listDrop args 1))))))

; (:m :do "why a route edit cannot apply: no such profile/intent route, the alias is not in that chain, or a --weight below 1")
fn routeEditErrors table: c/GatewayTable edits: (List RouteEdit) -> (List String)
  (fold (fn [(acc (List String)) (e RouteEdit)] -> (List String)
          (let [(parts (stringSplit e.route "/"))
                (route (listHead (filter (fn [(r c/GatewayRoute)] -> Bool (= r.intent (optionOr (listGet parts 1) ""))) (poolRoutes table (optionOr (listGet parts 0) "")))))]
            (match route
              ((none) (listAppend acc (list (str e.alias " " e.route ": no such freePool or paidCheap route"))))
              ((some r) (cond
                          ((not (listContains? r.chain e.alias)) (listAppend acc (list (str e.alias " " e.route ": not in that chain"))))
                          ((< e.weight 0) (listAppend acc (list (str "--weight " e.alias " " e.route ": weight must be a whole number of at least 1"))))
                          (else acc))))))
        (list) edits)

fn routeEditRow e: RouteEdit -> String
  (if (= e.weight 0) (str "(:dropRoute :model " e.alias " :route " e.route " :by lead)")
    (str "(:weight :model " e.alias " :route " e.route " :value " (stringFromInt64 e.weight) " :by lead)"))

; (:m :do "why the --set and --drop rows cannot form a patch: an alias with no model row, a key that is not a :keyword, an empty value; empty when they can")
fn editErrors table: c/GatewayTable sets: (List PaceSet) drops: (List String) -> (List String)
  (listAppend
    (fold (fn [(acc (List String)) (s PaceSet)] -> (List String)
            (cond
              ((none? (mapGet table.models s.alias)) (listAppend acc (list (str "--set " s.alias ": no model row"))))
              ((not (stringStartsWith? s.key ":")) (listAppend acc (list (str "--set " s.alias " " s.key ": key must be a :keyword"))))
              ((stringEmpty? s.value) (listAppend acc (list (str "--set " s.alias " " s.key ": empty value"))))
              (else acc)))
          (list) sets)
    (map (fn [(a String)] -> String (str "--drop " a ": no model row")) (filter (fn [(a String)] -> Bool (none? (mapGet table.models a))) drops)))

fn ! readOr! path: String -> String
  (resultOr (fileReadString path) "")

; (:m :do "models pace --date YYYY-MM-DD [--config P] [--cal P] [--mult P] [--scores P] [--subs P] [--out FILE] [--host NAME] [--ccPool N] [--set ALIAS :key VALUE]... [--drop ALIAS]... [--dropRoute ALIAS PROFILE/INTENT]... [--weight ALIAS PROFILE/INTENT N]...: writes the patch to --out (default ~/.asl/run/gwsync/subMultipliers.patch); the config is only read")
fn ! modelsPaceCli! args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") "/tmp"))
        (root (optionOr (envGet "ASL_GATEWAY_ROOT") "."))
        (source (argAfter args "--config" (c/gatewayProfilesPath home)))
        (calDir (str root "/.asl/mem/work/CAL"))
        (today (argAfter args "--date" ""))
        (out (argAfter args "--out" (str home "/.asl/run/gwsync/subMultipliers.patch")))
        (ccPool (optionOr (stringToFloat64 (argAfter args "--ccPool" "75000")) 75000.0))
        (sets (setsOf args))
        (drops (argsAll args "--drop"))
        (edits (routeEditsOf args))]
    (if (stringEmpty? today)
      (do (sys/sayErr! "(:modelsPace :status :error :why \"--date YYYY-MM-DD is required\")") (ok 2))
      (match (fileReadString source)
        ((err e) (do (sys/sayErr! (str "(:modelsPace :status :error :why " (q (str "cannot read " source ": " e)) ")")) (ok 1)))
        ((ok text)
          (match (c/gatewayConfigParse! text source "")
            ((err e) (do (sys/sayErr! (str "(:modelsPace :status :error :why " (q e) ")")) (ok 1)))
            ((ok table)
              (let [(bad (listAppend (editErrors table sets drops) (routeEditErrors table edits)))]
                (if (not (listEmpty? bad))
                  (do (sys/sayErr! (str "(:modelsPace :status :error :why " (q (stringJoin bad "; ")) ")")) (ok 2))
                  (let [(patch (pacePatchText table (readOr! (argAfter args "--mult" (str calDir "/subMultipliers-20261028.asn")))
                                              (readOr! (argAfter args "--scores" (str calDir "/freeCal-20261028.asn")))
                                              (readOr! (argAfter args "--cal" (str calDir "/freeModels.asn")))
                                              (readOr! (argAfter args "--subs" (str home "/.asl/subscriptions.asn")))
                                              today (argAfter args "--host" "local") ccPool sets drops edits))
                        (wrote (fileWrite out patch))]
                    (do (sys/say! (str "(:modelsPace :status " (if (ok? wrote) ":ok" ":error") " :patch " (q out) " :configWritten false)"))
                        (ok (if (ok? wrote) 0 1))))))))))))
