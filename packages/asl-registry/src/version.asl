(module asl-registry/version
  :d "Semantic version parsing, comparison, and outdated upgrade classification."
  :x [clean-version parse-semver-triplet compare-semver evaluate-outdated]
  :i [(regtypes :a ty)])

(df clean-version [(raw Str)] -> Str
  :d "Strips leading 'v' and whitespace from semantic version strings."
  (let [(trimmed (string-trim raw))]
    (if (string-starts-with? trimmed "v")
        (option-or (string-slice trimmed 1 (string-length trimmed)) trimmed)
        trimmed)))

(df parse-semver-triplet [(v Str)] -> (List I64)
  :d "Extracts major, minor, patch integers from semantic version string."
  (let [(cv (clean-version v))
        (parts (string-split cv "."))
        (p0 (string-to-int64 (option-or (list-get parts 0) "0")))
        (p1 (string-to-int64 (option-or (list-get parts 1) "0")))
        (p2-raw (option-or (list-get parts 2) "0"))
        (p2-clean (option-or (list-head (string-split p2-raw "-")) "0"))
        (p2 (string-to-int64 p2-clean))
        (maj (mt p0 ((some n) n) ((none) 0)))
        (min (mt p1 ((some n) n) ((none) 0)))
        (pat (mt p2 ((some n) n) ((none) 0)))]
    (list maj min pat)))

(df compare-semver [(v1 Str) (v2 Str)] -> I64
  :d "Returns 1 if v1 > v2, -1 if v1 < v2, 0 if equal."
  (let [(t1 (parse-semver-triplet v1))
        (t2 (parse-semver-triplet v2))
        (maj1 (option-or (list-get t1 0) 0))
        (min1 (option-or (list-get t1 1) 0))
        (pat1 (option-or (list-get t1 2) 0))
        (maj2 (option-or (list-get t2 0) 0))
        (min2 (option-or (list-get t2 1) 0))
        (pat2 (option-or (list-get t2 2) 0))]
    (cond
      ((> maj1 maj2) 1)
      ((< maj1 maj2) -1)
      ((> min1 min2) 1)
      ((< min1 min2) -1)
      ((> pat1 pat2) 1)
      ((< pat1 pat2) -1)
      (:else 0))))

(df evaluate-outdated [(pkg-name Str) (curr Str) (latest Str)] -> ty/OutdatedReport
  :d "Compares declared vs latest version and classifies upgrade severity."
  (let [(cmp (compare-semver curr latest))]
    (if (>= cmp 0)
        (ty/OutdatedReport
          :package-name pkg-name
          :current-version curr
          :latest-version latest
          :outdated false
          :severity "current")
        (let [(t1 (parse-semver-triplet curr))
              (t2 (parse-semver-triplet latest))
              (maj1 (option-or (list-get t1 0) 0))
              (min1 (option-or (list-get t1 1) 0))
              (maj2 (option-or (list-get t2 0) 0))
              (min2 (option-or (list-get t2 1) 0))
              (sev (cond
                     ((< maj1 maj2) "major")
                     ((< min1 min2) "minor")
                     (:else "patch")))]
          (ty/OutdatedReport
            :package-name pkg-name
            :current-version curr
            :latest-version latest
            :outdated true
            :severity sev)))))
