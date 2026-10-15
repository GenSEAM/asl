(module aslSite/app/update
  :x [light? explicit? step formatMs measuredOps]
  :i [(aslSite/ui/bridge :a b) (aslSite/app/msg :a m) (aslSite/app/home :a home)])

fn light? model: Int64 -> Bool
  (= (mod model 2) 1)

fn explicit? model: Int64 -> Bool
  (= (mod (/ model 2) 2) 1)

fn themeName model: Int64 -> String
  (if (light? model) "light" "dark")

fn themeOps model: Int64 -> (List b/Op)
  [(b/attrOp "html" "data-theme" (themeName model))
   (b/attrOp "#theme-toggle" "aria-pressed" (if (light? model) "true" "false"))]

fn copyOps line: String buttonId: String -> (List b/Op)
  [(b/copyOp line) (b/textOp (str "#" buttonId) "Copied") (b/afterOp 1600 (m/msgCode (m/resetCopy)))]

fn step msg: m/Msg model: Int64 -> (Pair Int64 (List b/Op))
  (mt msg
    ((m/boot) (pair model (if (explicit? model) (themeOps model) [])))
    ((m/toggleTheme)
      (let [(next (+ 2 (if (light? model) 0 1)))]
        (pair next (listAppend (themeOps next) [(b/storeOp "theme" (themeName next))]))))
    ((m/copyInstall) (pair model (copyOps (home/installLine) "copy-install")))
    ((m/copyBatch) (pair model (copyOps (home/batchLine) "copy-batch")))
    ((m/resetCopy) (pair model [(b/textOp "#copy-install" "Copy") (b/textOp "#copy-batch" "Copy")]))
    ((m/unknown) (pair model [])))

fn pad3 n: Int64 -> String
  (let [(s (stringFromInt64 n))] (str (stringRepeat "0" (max 0 (- 3 (stringLength s)))) s))

fn formatMs ns: Int64 -> String
  (let [(us (/ ns 1000))] (str (stringFromInt64 (/ us 1000)) "." (optionOr (stringSlice (pad3 (mod us 1000)) 0 2) "00") " ms"))

fn measuredOps cold: Int64 warm: Int64 bytes: Int64 -> (List b/Op)
  [(b/textOp "#proof-render" (formatMs warm))
   (b/attrOp "#proof-render" "title" (str (stringFromInt64 bytes) " bytes of HTML; the first, cold pass took " (formatMs cold)))
   (b/textOp "#proof-render-note" (str "page re-rendered in wasm (cold: " (formatMs cold) ")"))]
