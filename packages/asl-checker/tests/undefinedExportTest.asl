(module asl-checker/undefinedExportTest
  :x [runTests]
  :i [(check :a c) (types :a ty) (asl-parser/ast :a a)])

; (:m :ref INBOX-UNDEFINED-EXPORT :do "an :x name the module never defines is an ERR_UNDEFINED_EXPORT error of asl check (it was dropped as a lint, so 30 listed functions could pass check before they were written); a defined fn, a defined schema and a defined enum stay clean")
fn probe src: String -> (List ty/Diagnostic)
  (match (a/parse src)
    ((err _) (list))
    ((ok forms) (c/checkModuleSource forms (mapEmpty) "undefinedExportProbe.asl" src)))

fn codes ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn ! runTests -> Bool
  (let [(missing (probe "(module probe :x [missingFn present] :i [])\n\nfn present -> Int64\n  1\n"))
        (clean (probe "(module probe :x [present] :i [])\n\nfn present -> Int64\n  1\n"))
        (types (probe "(module probe :x [Point Shade present] :i [])\n\n(schema Point (:f x Int64))\n\n(enum Shade (:c light [] \"l\"))\n\nfn present -> Int64\n  1\n"))
        (cases (probe "(module probe :x [light present] :i [])\n\n(enum Shade (:c light [] \"l\"))\n\nfn present -> Int64\n  1\n"))
        (missingType (probe "(module probe :x [Ghost present] :i [])\n\nfn present -> Int64\n  1\n"))]
    (do (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (and (= d.code "ERR_UNDEFINED_EXPORT") (stringContains? d.message "missingFn"))) missing) (str "an exported fn that is never defined is ERR_UNDEFINED_EXPORT: " (codes missing)))
        (assert (listEmpty? clean) (str "a module exporting only what it defines is clean: " (codes clean)))
        (assert (listEmpty? types) (str "an exported schema and enum that are defined stay clean: " (codes types)))
        (assert (listEmpty? cases) (str "an exported enum case is not an undefined export: " (codes cases)))
        (assert (listEmpty? missingType) (str "an exported Pascal name stays a silent lint: " (codes missingType)))
        true))
