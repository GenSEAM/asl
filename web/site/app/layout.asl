(module aslSite/app/layout
  :x [Route home docs blog post missing routePath siteUrl document topBar footBar eyebrow sectionHead markNode copyButton]
  :i [(aslSite/ui/html :a h) (aslSite/app/msg :a m) (aslSite/app/mascot :a mascot)])

(enum Route (:c home [] "landing page") (:c docs [] "the language on one page") (:c blog [] "post index") (:c post [(slug String)] "one article") (:c missing [] "the 404 page"))

fn siteUrl -> String
  "https://aslang.dev"

fn routePath r: Route -> String
  (mt r ((home) "/") ((docs) "/docs") ((blog) "/blog") ((post slug) (str "/blog/" slug)) ((missing) "/404"))

fn current? r: Route target: Route -> Bool
  (mt target
    ((home) (mt r ((home) true) (_ false)))
    ((docs) (mt r ((docs) true) (_ false)))
    ((blog) (mt r ((blog) true) ((post s) true) (_ false)))
    ((post s) false)
    ((missing) false))

fn markNode -> h/Node
  (mascot/chameleon false "small")

fn themeIcon -> h/Node
  (h/svg [(h/attr "viewBox" "0 0 24 24") (h/attr "aria-hidden" "true")]
    [(h/circle [(h/cls "ring") (h/attr "cx" "12") (h/attr "cy" "12") (h/attr "r" "9")])
     (h/path [(h/cls "sun") (h/attr "d" "M12 3a9 9 0 0 1 0 18z")])])

fn navLink here: Route target: Route label: String extra: String -> h/Node
  (h/a (listAppend [(h/href (routePath target)) (h/cls extra)] (if (current? here target) [(h/attr "aria-current" "page")] [])) [(h/text label)])

fn topBar here: Route -> h/Node
  (h/header [(h/cls "top")]
    [(h/div [(h/cls "shell")]
      [(h/a [(h/href "/") (h/cls "mark") (h/attr "aria-label" "AgentScript home")] [(markNode) (h/span [] [(h/text "AgentScript")])])
       (h/nav [(h/cls "links") (h/attr "aria-label" "Primary")]
         [(navLink here (docs) "Docs" "")
          (navLink here (blog) "Blog" "")
          (h/a [(h/href "https://github.com/GenSEAM/asl") (h/cls "wide")] [(h/text "GitHub")])
          (h/a [(h/href "/llms.txt") (h/cls "wide")] [(h/text "llms.txt")])
          (h/button [(h/cls "toggle") (h/id "theme-toggle") (m/onClick (m/toggleTheme)) (h/attr "aria-label" "Switch colour theme") (h/attr "title" "Switch colour theme")] [(themeIcon)])])])])

fn footCol heading: String links: (List (Pair String String)) -> h/Node
  (h/div []
    [(h/h4 [] [(h/text heading)])
     (h/ul [] (map (fn [(l (Pair String String))] -> h/Node (h/li [] [(h/a [(h/href (pairSecond l))] [(h/text (pairFirst l))])])) links))])

fn footBar -> h/Node
  (h/footer [(h/cls "foot")]
    [(h/div [(h/cls "shell")]
      [(h/div [(h/cls "stack")]
        [(h/a [(h/href "/") (h/cls "mark")] [(markNode) (h/span [] [(h/text "AgentScript")])])
         (h/p [] [(h/text "A language and data notation written by models, for models. Dual-licensed MIT or Apache-2.0.")])
         (h/p [(h/cls "micro") (h/id "built-with")] [(h/text "This site is an ASL program: markup, styles and event handlers compiled to WebAssembly.")])])
       (footCol "Language" [(pair "Docs" "/docs") (pair "llms.txt" "/llms.txt") (pair "Install script" "/install.sh")])
       (footCol "Project" [(pair "Source" "https://github.com/GenSEAM/asl") (pair "Blog" "/blog") (pair "RSS" "/rss.xml")])])])

fn eyebrow index: String label: String -> h/Node
  (h/span [(h/cls "eyebrow")] [(h/span [(h/cls "idx")] [(h/text index)]) (h/span [(h/cls "rule") (h/attr "aria-hidden" "true")] []) (h/text label)])

fn sectionHead index: String label: String title: String lead: String -> h/Node
  (h/div [(h/cls "head")] [(eyebrow index label) (h/h2 [(h/cls "h2")] [(h/text title)]) (h/p [(h/cls "lead")] [(h/text lead)])])

fn copyButton targetId: String msg: m/Msg -> h/Node
  (h/button [(h/cls "copy") (h/id targetId) (m/onClick msg)] [(h/text "Copy")])

fn headNodes here: Route pageTitle: String description: String -> (List h/Node)
  [(h/meta [(h/attr "charset" "utf-8")])
   (h/meta [(h/attr "name" "viewport") (h/attr "content" "width=device-width, initial-scale=1")])
   (h/title pageTitle)
   (h/meta [(h/attr "name" "description") (h/attr "content" description)])
   (mt here
     ((missing) (h/meta [(h/attr "name" "robots") (h/attr "content" "noindex")]))
     (_ (h/link [(h/attr "rel" "canonical") (h/href (str (siteUrl) (routePath here)))])))
   (h/meta [(h/attr "property" "og:type") (h/attr "content" (mt here ((post s) "article") (_ "website")))])
   (h/meta [(h/attr "property" "og:title") (h/attr "content" pageTitle)])
   (h/meta [(h/attr "property" "og:description") (h/attr "content" description)])
   (h/meta [(h/attr "property" "og:url") (h/attr "content" (str (siteUrl) (routePath here)))])
   (h/meta [(h/attr "property" "og:image") (h/attr "content" (str (siteUrl) "/logo.svg"))])
   (h/meta [(h/attr "name" "twitter:card") (h/attr "content" "summary")])
   (h/meta [(h/attr "name" "theme-color") (h/attr "content" "#121012")])
   (h/link [(h/attr "rel" "icon") (h/attr "type" "image/svg+xml") (h/href "/favicon.svg")])
   (h/link [(h/attr "rel" "alternate") (h/attr "type" "text/plain") (h/attr "title" "LLM entry") (h/href "/llms.txt")])
   (h/link [(h/attr "rel" "alternate") (h/attr "type" "application/rss+xml") (h/attr "title" "AgentScript blog") (h/href "/rss.xml")])
   (h/link [(h/attr "rel" "stylesheet") (h/href "/site.css")])
   (h/link [(h/attr "rel" "modulepreload") (h/href "/boot.js")])
   (h/link [(h/attr "rel" "preload") (h/href "/site.wasm") (h/attr "as" "fetch") (h/attr "type" "application/wasm") (h/attr "crossorigin" "anonymous")])
   (h/script [(h/attr "type" "module") (h/attr "src" "/boot.js")])]

fn document here: Route pageTitle: String description: String content: (List h/Node) -> h/Node
  (h/html [(h/attr "lang" "en")]
    [(h/head (headNodes here pageTitle description))
     (h/body []
       [(h/a [(h/href "#content") (h/cls "skip")] [(h/text "Skip to content")])
        (topBar here)
        (h/main [(h/id "content")] content)
        (footBar)])])
