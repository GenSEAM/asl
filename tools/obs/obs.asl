(module ws/asl/tools/obs/obs
  :x [Obs blankObs renderObs parseObs obsId dayOf dayToMs familyOf]
  :i [(ws/asl/tools/obs/sx :a sx)])

; (:m :ref OBSCORPUS :do "the one observation row type; every source normalises into it, text fields are already filtered, :id is a digest of the identifying fields so a row seen twice is stored once")
(schema Obs
  (:f at Int64)
  (:f host String)
  (:f source String)
  (:f run String)
  (:f unitId String)
  (:f caseId String)
  (:f model String)
  (:f family String)
  (:f intent String)
  (:f card String)
  (:f temperature String)
  (:f turn Int64)
  (:f tokensIn Int64)
  (:f tokensOut Int64)
  (:f ms Int64)
  (:f outcome String)
  (:f failClass String)
  (:f sig String)
  (:f gate String)
  (:f exitCode Int64)
  (:f asserts Int64))

fn blankObs -> Obs
  (Obs :at 0 :host "" :source "" :run "" :unitId "" :caseId "" :model "" :family "" :intent "" :card "" :temperature ""
       :turn 0 :tokensIn 0 :tokensOut 0 :ms 0 :outcome "" :failClass "none" :sig "" :gate "" :exitCode -1 :asserts -1)

fn stripEffort m: String -> String
  (let [(sfx (list "-low" "-medium" "-high" ":low" ":medium" ":high" ".low" ".medium" ".high"))]
    (match (listFind (fn [(s String)] -> Bool (stringEndsWith? m s)) sfx)
      ((some s) (optionOr (stringSlice m 0 (- (stringLength m) (stringLength s))) m))
      ((none) m)))

fn lastSegment m: String -> String
  (optionOr (listLast (stringSplit m "/")) m)

fn familyOf m: String -> String
  (stripEffort (lastSegment (stringLower m)))

fn q t: String -> String
  (sx/quoteText t)

fn n v: Int64 -> String
  (stringFromInt64 v)

fn obsId o: Obs -> String
  (optionOr (stringSlice (bytesSha256 (stringToBytes (str o.source "|" (n o.at) "|" o.run "|" o.unitId "|" o.caseId "|" o.model "|" (n o.turn) "|" (n o.ms) "|" (n o.tokensIn) "|" o.card "|" o.sig))) 0 16) "")

fn renderObs o: Obs -> String
  (str "(:obs :id " (q (obsId o)) " :at " (n o.at) " :host " (q o.host) " :source " (q o.source) " :run " (q o.run) " :unit " (q o.unitId)
       " :case " (q o.caseId) " :model " (q o.model) " :family " (q o.family) " :intent " (q o.intent) " :card " (q o.card)
       " :temperature " (q o.temperature) " :turn " (n o.turn) " :tokensIn " (n o.tokensIn) " :tokensOut " (n o.tokensOut) " :ms " (n o.ms)
       " :outcome " (q o.outcome) " :failClass " (q o.failClass) " :sig " (q o.sig) " :gate " (q o.gate) " :exit " (n o.exitCode) " :asserts " (n o.asserts) ")")

fn parseObs line: String -> Obs
  (let [(f (sx/topFields line))
        (s (fn [(k String)] -> String (optionOr (sx/field f k) "")))
        (i (fn [(k String)] -> Int64 (sx/intField f k)))]
    (Obs :at (i ":at") :host (s ":host") :source (s ":source") :run (s ":run") :unitId (s ":unit") :caseId (s ":case")
         :model (s ":model") :family (s ":family") :intent (s ":intent") :card (s ":card") :temperature (s ":temperature")
         :turn (i ":turn") :tokensIn (i ":tokensIn") :tokensOut (i ":tokensOut") :ms (i ":ms")
         :outcome (s ":outcome") :failClass (s ":failClass") :sig (s ":sig") :gate (s ":gate") :exitCode (i ":exit") :asserts (i ":asserts")))

fn pad2 v: Int64 -> String
  (if (< v 10) (str "0" (n v)) (n v))

fn dayOf ms: Int64 -> String
  (let [(z (+ (/ ms 86400000) 719468))
        (era (/ z 146097))
        (doe (- z (* era 146097)))
        (yoe (/ (- (+ (- doe (/ doe 1460)) (/ doe 36524)) (/ doe 146096)) 365))
        (doy (- doe (- (+ (* 365 yoe) (/ yoe 4)) (/ yoe 100))))
        (mp (/ (+ (* 5 doy) 2) 153))
        (d (+ (- doy (/ (+ (* 153 mp) 2) 5)) 1))
        (m (if (< mp 10) (+ mp 3) (- mp 9)))
        (y (+ (+ yoe (* era 400)) (if (<= m 2) 1 0)))]
    (str (n y) "-" (pad2 m) "-" (pad2 d)))

fn dayToMs day: String -> Int64
  (let [(p (stringSplit day "-"))
        (y0 (optionOr (stringToInt64 (optionOr (listGet p 0) "1970")) 1970))
        (m (optionOr (stringToInt64 (optionOr (listGet p 1) "1")) 1))
        (d (optionOr (stringToInt64 (optionOr (listGet p 2) "1")) 1))
        (y (if (<= m 2) (- y0 1) y0))
        (era (/ y 400))
        (yoe (- y (* era 400)))
        (mp (if (> m 2) (- m 3) (+ m 9)))
        (doy (+ (/ (+ (* 153 mp) 2) 5) (- d 1)))
        (doe (+ (- (+ (* yoe 365) (/ yoe 4)) (/ yoe 100)) doy))
        (days (- (+ (* era 146097) doe) 719468))]
    (* days 86400000))
