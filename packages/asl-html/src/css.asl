(module asl-html/css
  :x [Decl Rule decl important rule ruleFor media supports layer layerOrder container keyframes fontFace importUrl atRule
      cssVar px rem em pct ms deg cssUrl cssString renderDecls renderRule renderSheet renderSheetPretty]
  :i [])

(enum Decl (:c declPair [(prop String) (value String)] "property: value") (:c declImportant [(prop String) (value String)] "property: value !important"))

(enum Rule (:c ruleNode [(selector String) (decls (List Decl))] "selector block") (:c atBlock [(name String) (prelude String) (rules (List Rule))] "@media, @supports, @layer, @container: a block of rules") (:c keyframesNode [(name String) (frames (List (Pair String (List Decl))))] "@keyframes name with its stops") (:c fontFaceNode [(decls (List Decl))] "@font-face") (:c atStatement [(name String) (prelude String)] "@import, @layer a, b: a statement ending in ;"))

fn decl prop: String value: String -> Decl
  (declPair prop value)

fn important prop: String value: String -> Decl
  (declImportant prop value)

fn rule selector: String decls: (List Decl) -> Rule
  (ruleNode selector decls)

fn ruleFor selectors: (List String) decls: (List Decl) -> Rule
  (ruleNode (stringJoin selectors ",") decls)

fn media query: String rules: (List Rule) -> Rule
  (atBlock "media" query rules)

fn supports condition: String rules: (List Rule) -> Rule
  (atBlock "supports" condition rules)

fn layer name: String rules: (List Rule) -> Rule
  (atBlock "layer" name rules)

fn layerOrder names: (List String) -> Rule
  (atStatement "layer" (stringJoin names ","))

fn container query: String rules: (List Rule) -> Rule
  (atBlock "container" query rules)

fn keyframes name: String frames: (List (Pair String (List Decl))) -> Rule
  (keyframesNode name frames)

fn fontFace decls: (List Decl) -> Rule
  (fontFaceNode decls)

fn importUrl url: String -> Rule
  (atStatement "import" (cssUrl url))

fn atRule name: String prelude: String rules: (List Rule) -> Rule
  (atBlock name prelude rules)

fn cssVar name: String -> String
  (str "var(--" name ")")

fn px n: Int64 -> String
  (str (stringFromInt64 n) "px")

fn rem x: Float64 -> String
  (str (stringFromFloat64 x) "rem")

fn em x: Float64 -> String
  (str (stringFromFloat64 x) "em")

fn pct n: Int64 -> String
  (str (stringFromInt64 n) "%")

fn ms n: Int64 -> String
  (str (stringFromInt64 n) "ms")

fn deg n: Int64 -> String
  (str (stringFromInt64 n) "deg")

fn cssString s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\a ") "\"")

fn cssUrl url: String -> String
  (str "url(" (cssString url) ")")

fn declOut d: Decl -> String
  (mt d
    ((declPair prop value) (str prop ":" value))
    ((declImportant prop value) (str prop ":" value " !important")))

fn renderDecls decls: (List Decl) -> String
  (stringJoin (map declOut decls) ";")

fn frameOut frame: (Pair String (List Decl)) -> String
  (str (pairFirst frame) "{" (renderDecls (pairSecond frame)) "}")

fn renderRule r: Rule -> String
  (mt r
    ((ruleNode selector decls) (str selector "{" (renderDecls decls) "}"))
    ((atBlock name prelude rules) (str "@" name (if (stringEmpty? prelude) "" (str " " prelude)) "{" (stringJoin (map renderRule rules) "") "}"))
    ((keyframesNode name frames) (str "@keyframes " name "{" (stringJoin (map frameOut frames) "") "}"))
    ((fontFaceNode decls) (str "@font-face{" (renderDecls decls) "}"))
    ((atStatement name prelude) (str "@" name " " prelude ";")))

fn renderSheet rules: (List Rule) -> String
  (stringJoin (map renderRule rules) "\n")

fn pad depth: Int64 -> String
  (stringRepeat "  " depth)

fn declsPretty depth: Int64 decls: (List Decl) -> String
  (stringJoin (map (fn [(d Decl)] -> String (str (pad depth) (declOut d) ";\n")) decls) "")

fn rulePretty depth: Int64 r: Rule -> String
  (mt r
    ((ruleNode selector decls) (str (pad depth) selector " {\n" (declsPretty (+ depth 1) decls) (pad depth) "}\n"))
    ((atBlock name prelude rules) (str (pad depth) "@" name (if (stringEmpty? prelude) "" (str " " prelude)) " {\n" (stringJoin (map (fn [(x Rule)] -> String (rulePretty (+ depth 1) x)) rules) "") (pad depth) "}\n"))
    ((keyframesNode name frames) (str (pad depth) "@keyframes " name " {\n" (stringJoin (map (fn [(f (Pair String (List Decl)))] -> String (str (pad (+ depth 1)) (pairFirst f) " {\n" (declsPretty (+ depth 2) (pairSecond f)) (pad (+ depth 1)) "}\n")) frames) "") (pad depth) "}\n"))
    ((fontFaceNode decls) (str (pad depth) "@font-face {\n" (declsPretty (+ depth 1) decls) (pad depth) "}\n"))
    ((atStatement name prelude) (str (pad depth) "@" name " " prelude ";\n")))

fn renderSheetPretty rules: (List Rule) -> String
  (stringJoin (map (fn [(r Rule)] -> String (rulePretty 0 r)) rules) "\n")
