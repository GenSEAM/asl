(module asl-cli/repairCmd
  :x [runRepairCommand!]
  :i [(asl-syntax/core/format :a fmt)
      (asl/packages/asl-cli/src/system :a sys)])

; (:m :do "asl repair [--check] FILE...: formats each .asl/.asn file with the asl-syntax formatter (fmt/formatFile!) and writes it back only when the text changed; one (:repair :file F :changed true|false) receipt per file; a file that does not parse prints (:repair :file F :error ...) and exits 1; --check writes nothing and exits 1 when any file would change")

fn quoted s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn repairHelp -> String
  (str "Usage: asl repair [--check] <file...>\n\n"
       "Repairs unbalanced delimiters of .asl and .asn files in place with the asl-syntax formatter (it does not re-indent); each file prints one (:repair :file F :changed true|false) line.\n"
       "  --check              write nothing and exit 1 when any file would change\n"
       "  -h, --help           print this help\n"
       "A file that does not parse prints (:repair :file F :error ...) and exits 1.\n")

fn changedLine path: String changed: Bool -> String
  (str "(:repair :file " (quoted path) " :changed " (if changed "true" "false") ")")

fn errorLine path: String e: String -> String
  (str "(:repair :file " (quoted path) " :error " (quoted e) ")")

fn decide path: String text: String out: String -> (Pair Bool String)
  (if (= out text)
    (pair false (changedLine path false))
    (pair true (changedLine path true)))

fn ! saved! path: String out: String p: (Pair Bool String) check: Bool -> (Result (Pair Bool String) String)
  (if (or check (not (pairFirst p)))
    (ok p)
    (match (fileWrite path out)
      ((err e) (err (errorLine path e)))
      ((ok _) (ok p))))

fn ! formatOne! path: String text: String check: Bool -> (Result (Pair Bool String) String)
  (match (fmt/formatFile! path)
    ((err e) (err (errorLine path e)))
    ((ok out) (saved! path out (decide path text out) check)))

fn ! processOne! path: String check: Bool -> (Result (Pair Bool String) String)
  (match (fileReadString path)
    ((err e) (err (errorLine path e)))
    ((ok text) (formatOne! path text check)))

fn failed? r: (Result (Pair Bool String) String) -> Bool
  (match r
    ((err _) true)
    ((ok _) false))

fn changedOf r: (Result (Pair Bool String) String) -> Bool
  (match r
    ((err _) false)
    ((ok (pair c _)) c))

fn receiptOf r: (Result (Pair Bool String) String) -> String
  (match r
    ((err e) e)
    ((ok (pair _ s)) s))

fn ! reportAll! results: (List (Result (Pair Bool String) String)) -> (Pair Bool Bool)
  (fold (fn [(a (Pair Bool Bool)) (r (Result (Pair Bool String) String))] -> (Pair Bool Bool)
          (let [(shown (sys/say! (receiptOf r)))]
            (pair (or (pairFirst a) (failed? r)) (or (pairSecond a) (changedOf r)))))
        (pair false false) results)

fn isFlag a: String -> Bool
  (stringStartsWith? a "-")

fn ! runRepairCommand! args: (List String) -> Int64
  (let [(check (listContains? args "--check"))
        (files (filter (fn [(a String)] -> Bool (not (isFlag a))) args))
        (help (or (listContains? args "-h") (listContains? args "--help")))]
    (cond
      (help (do (sys/say! (repairHelp)) 0))
      ((listEmpty? files) (do (sys/sayErr! "(:repair :status :failed :error ERR_MISSING_ARG :message \"usage: asl repair [--check] <file...>\")") 1))
      (else
        (let [(acc (reportAll! (map (fn [(p String)] -> (Result (Pair Bool String) String) (processOne! p check)) files)))]
          (if (or (pairFirst acc) (and check (pairSecond acc))) 1 0)))))
