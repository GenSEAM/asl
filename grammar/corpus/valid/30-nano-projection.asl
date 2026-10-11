(module sensor/nano :x [Sample Window Grade Trend readings meanOf sampleOf gradeOf labelOf trendOf trendLabel summarise widen blank] :i [(core/strings :a s)])

(schema Sample (:f id Str "Identifier the readings were taken under.") (:f count Int "How many readings the sample summarises.") (:f mean Num "Arithmetic mean of the readings.") (:f drift F32 "Spread between the extreme readings.") (:f settled Bool "Whether the sample held any reading at all."))

(schema Window (:f low F64 "Lower bound a settled mean must not fall below.") (:f high Float "Upper bound a settled mean must not exceed."))

(enum Grade (:c steady [] "Mean inside the window, spread small.") (:c drifting [(by F32)] "Mean inside the window, spread too large.") (:c outOfRange [(mean Num)] "Mean outside the window."))

(enum Trend (:c rising [] "The last reading exceeds the first.") (:c falling [] "The last reading falls below the first.") (:c flat [] "First and last readings agree."))

fn readings csv: Str -> (List Num)
  (map (fn [t] (optionOr (stringToFloat64 t) 0.0)) (filter (fn [t] (some? (stringToFloat64 t))) (stringSplit csv ",")))

fn meanOf xs: (List Num) -> Num
  (if (= (listLength xs) 0) 0.0 (/ (listSum xs) (int64ToFloat64 (listLength xs))))

fn sampleOf id: Str xs: (List F64) -> Sample
  (let [(m (meanOf xs))] (Sample :id (s/upper id) :count (listLength xs) :mean m :drift (- (optionOr (listMax xs) m) (optionOr (listMin xs) m)) :settled (not (listEmpty? xs))))

fn gradeOf w: Window sm: Sample -> Grade
  (cond ((or (< sm.mean w.low) (> sm.mean w.high)) (outOfRange sm.mean)) ((> sm.drift 1.0) (drifting sm.drift)) (else (steady)))

fn labelOf g: Grade -> Str
  (mt g ((steady) "steady") ((drifting by) (s/concat "drifting:" (stringFromFloat64 by))) ((outOfRange m) (s/concat "out:" (stringFromFloat64 m))))

fn trendOf xs: (List Float) -> Trend
  (do "Compare the first reading with the last." (let [(head (optionOr (listHead xs) 0.0)) (tail (optionOr (listHead (listReverse xs)) 0.0))] (cond ((> tail head) (rising)) ((< tail head) (falling)) (else (flat)))))

fn trendLabel t: Trend -> Str
  (do "A one-word label for a trend." (mt t ((rising) "rising") ((falling) "falling") ((flat) "flat")))

fn summarise id: Str csv: Str -> Str
  (let [(xs (readings csv)) (sm (sampleOf id xs)) (w (Window :low 0.0 :high 100.0))] (stringJoin (list sm.id (stringFromInt64 sm.count) (stringFromFloat64 sm.mean) (labelOf (gradeOf w sm)) (trendLabel (trendOf xs))) "|"))

fn widen n: I32 -> I64
  (int32ToInt64 n)

fn blank -> Unit
  ()
