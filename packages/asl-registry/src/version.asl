(module asl-registry/version :x [cleanVersion parseSemverTriplet compareSemver evaluateOutdated] :i [(regtypes :a ty)])

fn cleanVersion raw: Str -> Str
  (let [(trimmed (stringTrim raw))] (if (stringStartsWith? trimmed "v") (optionOr (stringSlice trimmed 1 (stringLength trimmed)) trimmed) trimmed))

fn parseSemverTriplet v: Str -> (List I64)
  (let [(cv (cleanVersion v)) (parts (stringSplit cv ".")) (p0 (stringToInt64 (optionOr (listGet parts 0) "0"))) (p1 (stringToInt64 (optionOr (listGet parts 1) "0"))) (p2Raw (optionOr (listGet parts 2) "0")) (p2Clean (optionOr (listHead (stringSplit p2Raw "-")) "0")) (p2 (stringToInt64 p2Clean)) (maj (mt p0 ((some n) n) ((none) 0))) (min (mt p1 ((some n) n) ((none) 0))) (pat (mt p2 ((some n) n) ((none) 0)))] (list maj min pat))

fn compareSemver v1: Str v2: Str -> I64
  (let [(t1 (parseSemverTriplet v1)) (t2 (parseSemverTriplet v2)) (maj1 (optionOr (listGet t1 0) 0)) (min1 (optionOr (listGet t1 1) 0)) (pat1 (optionOr (listGet t1 2) 0)) (maj2 (optionOr (listGet t2 0) 0)) (min2 (optionOr (listGet t2 1) 0)) (pat2 (optionOr (listGet t2 2) 0))] (cond ((> maj1 maj2) 1) ((< maj1 maj2) -1) ((> min1 min2) 1) ((< min1 min2) -1) ((> pat1 pat2) 1) ((< pat1 pat2) -1) (else 0)))

fn evaluateOutdated pkgName: Str curr: Str latest: Str -> ty/OutdatedReport
  (let [(cmp (compareSemver curr latest))] (if (>= cmp 0) (ty/OutdatedReport :packageName pkgName :currentVersion curr :latestVersion latest :outdated false :severity "current") (let [(t1 (parseSemverTriplet curr)) (t2 (parseSemverTriplet latest)) (maj1 (optionOr (listGet t1 0) 0)) (min1 (optionOr (listGet t1 1) 0)) (maj2 (optionOr (listGet t2 0) 0)) (min2 (optionOr (listGet t2 1) 0)) (sev (cond ((< maj1 maj2) "major") ((< min1 min2) "minor") (else "patch")))] (ty/OutdatedReport :packageName pkgName :currentVersion curr :latestVersion latest :outdated true :severity sev))))
