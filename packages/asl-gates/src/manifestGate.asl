(module asl-gates/manifestGate :x [ManifestRecord makeManifestRecord parsePackageId verifyManifestRecord isValidPkgName?] :i [])

(schema ManifestRecord (:f path Str) (:f packageName Str) (:f version Str) (:f entry Str) (:f isValid Bool))

fn isValidPkgName? name: Str -> Bool
  (and (not (stringContains? name "@")) (> (stringLength name) 2))

fn makeManifestRecord path: Str pkgName: Str version: Str entry: Str -> ManifestRecord
  (let [(valid (and (isValidPkgName? pkgName) (and (> (stringLength version) 0) (> (stringLength entry) 0))))] (ManifestRecord :path path :packageName pkgName :version version :entry entry :isValid valid))

fn parsePackageId content: Str -> Str
  (let [(trimmed (stringTrim content))] (if (stringStartsWith? trimmed "(:package") (let [(after (stringTrim (optionOr (stringSlice trimmed 9 (stringLength trimmed)) ""))) (words (stringSplit after " "))] (stringTrim (optionOr (listHead words) ""))) ""))

fn verifyManifestRecord record: ManifestRecord -> Bool
  record.isValid
