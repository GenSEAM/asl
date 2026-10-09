(module asl-engine/build
  :x [EngineBuild entrySuffix entryPath! toolRootOf hostBin! sourceVersion! makeBuild! parseMs]
  :i [])

(schema EngineBuild
  (:f entry String)
  (:f toolRoot String)
  (:f host String)
  (:f version String)
  (:f updates Int64)
  (:f updatedFrom String))

fn entrySuffix -> String
  "/asl/packages/asl-engine/src/cli.asl"

fn ! isFile? path: String -> Bool
  (mt (fileStat path) ((ok st) st.isFile) ((err _) false))

fn ! entryPath! -> String
  (let [(given (optionOr (envGet "ASL_ENGINE_ENTRY") ""))
        (local (str (resultOr (realPath ".") ".") (entrySuffix)))]
    (cond
      ((not (stringEmpty? given)) given)
      ((isFile? local) local)
      (else "")))

fn toolRootOf entry: String -> String
  (if (stringEndsWith? entry (entrySuffix))
    (optionOr (stringSlice entry 0 (- (stringLength entry) (stringLength (entrySuffix)))) "")
    "")

fn ! hostBin! toolRoot: String -> String
  (let [(given (optionOr (envGet "ASL_HOST") ""))
        (built (str toolRoot "/asl/host/out/asl-host"))]
    (cond
      ((and (not (stringEmpty? given)) (isFile? given)) (resultOr (realPath given) given))
      ((and (not (stringEmpty? toolRoot)) (isFile? built)) (resultOr (realPath built) built))
      (else "")))

fn srcDirOf entry: String -> String
  (mt (stringIndexOf (stringReverse entry) "/")
    ((none) ".")
    ((some i) (optionOr (stringSlice entry 0 (- (stringLength entry) (+ i 1))) ".")))

fn ! sourceVersion! entry: String -> String
  (let [(dir (srcDirOf entry))]
    (mt (dirList dir)
      ((err _) "absent")
      ((ok names)
        (let [(sources (listSort (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asl")) names)))
              (parts (map (fn [(n String)] -> String (str n "\n" (resultOr (fileReadString (str dir "/" n)) "") "\n")) sources))]
          (if (listEmpty? sources)
            "absent"
            (optionOr (stringSlice (bytesSha256 (stringToBytes (stringJoin parts ""))) 0 12) "absent"))))))

fn digitsOnly? s: String -> Bool
  (and (not (stringEmpty? s))
       (listAll? (fn [(c String)] -> Bool (and (>= c "0") (<= c "9"))) (stringChars s)))

fn parseMs raw: String fallbackMs: Int64 -> Int64
  (mt (stringToFloat64 (stringTrim raw))
    ((none) fallbackMs)
    ((some sec) (optionOr (float64ToInt64 (* sec 1000.0)) fallbackMs)))

fn ! makeBuild! entry: String -> EngineBuild
  (let [(root (toolRootOf entry))
        (updatesRaw (optionOr (envGet "ASL_ENGINE_UPDATES") "0"))]
    (EngineBuild :entry entry
                 :toolRoot root
                 :host (hostBin! root)
                 :version (sourceVersion! entry)
                 :updates (if (digitsOnly? updatesRaw) (optionOr (stringToInt64 updatesRaw) 0) 0)
                 :updatedFrom (optionOr (envGet "ASL_ENGINE_UPDATED_FROM") "")))
