(module asl-tools/renderTag
  :x [renderEntry importFiles renderTagIn!]
  :i [])

; (:m :ref NT-VERDICT-KEY-COVERS-RENDER :do "a cached checker verdict holds rendered text, so its key carries a digest of the renderer's source: asl-cli/verify and the files of its direct imports; a renderer edit then misses the old bodies with no hand-bumped tag")
fn renderEntry -> String
  "asl/packages/asl-cli/src/verify.asl"

; (:m :do "a module name maps to its file as the loader lays packages out: a path-form name asl/... is that path plus .asl, pkg/mod is asl/packages/pkg/src/mod.asl")
fn moduleFile name: String -> String
  (if (stringStartsWith? name "asl/")
    (str name ".asl")
    (match (stringIndexOf name "/")
      ((none) (str "asl/packages/" name "/src/" name ".asl"))
      ((some i) (str "asl/packages/" (optionOr (stringSlice name 0 i) "") "/src/" (optionOr (stringSlice name (+ i 1) (stringLength name)) "") ".asl"))))

fn importNames body: String -> (List String)
  (filter (fn [(n String)] -> Bool (not (stringEmpty? n)))
          (map (fn [(part String)] -> String (optionOr (listHead (stringSplit (stringTrim part) " ")) ""))
               (optionOr (listTail (stringSplit body "(")) (list))))

; (:m :do "the :i [...] list of the module header, read lexically; a header without one imports nothing")
fn importFiles text: String -> (List String)
  (match (stringIndexOf text ":i [")
    ((none) (list))
    ((some i)
      (let [(rest (optionOr (stringSlice text (+ i 4) (stringLength text)) ""))
            (body (optionOr (stringSlice rest 0 (optionOr (stringIndexOf rest "]") 0)) ""))]
        (map moduleFile (importNames body)))))

fn fileDigest! root: String rel: String -> String
  (match (fileReadBytes (str root "/" rel))
    ((ok b) (str rel "=" (bytesSha256 b)))
    ((err _) (str rel "=missing")))

fn renderTagIn! root: String -> String
  (let [(entry (renderEntry))
        (text (resultOr (fileReadString (str root "/" entry)) ""))
        (files (cons entry (listSort (importFiles text))))]
    (optionOr (stringSlice (bytesSha256 (stringToBytes (stringJoin (map (fn [(f String)] -> String (fileDigest! root f)) files) "\n"))) 0 16) ""))
