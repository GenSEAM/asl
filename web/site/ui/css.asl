(module aslSite/ui/css
  :x [Rule Decl rule media decl tokenVar renderRule renderSheet]
  :i [])

(enum Decl (:c declPair [(prop String) (value String)] "property: value"))

(enum Rule (:c ruleNode [(selector String) (decls (List Decl))] "selector block") (:c mediaNode [(query String) (rules (List Rule))] "@media block"))

fn decl prop: String value: String -> Decl
  (declPair prop value)

fn rule selector: String decls: (List Decl) -> Rule
  (ruleNode selector decls)

fn media query: String rules: (List Rule) -> Rule
  (mediaNode query rules)

fn tokenVar name: String -> String
  (str "var(--" name ")")

fn declOut d: Decl -> String
  (mt d ((declPair prop value) (str prop ":" value)))

fn renderRule r: Rule -> String
  (mt r
    ((ruleNode selector decls) (str selector "{" (stringJoin (map declOut decls) ";") "}"))
    ((mediaNode query rules) (str "@media " query "{" (stringJoin (map renderRule rules) "") "}")))

fn renderSheet rules: (List Rule) -> String
  (stringJoin (map renderRule rules) "\n")
