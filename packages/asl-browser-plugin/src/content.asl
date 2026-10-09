(module aslBrowserPlugin/content :x [PageContext makePageContext formatPageContext extractPageContext isValidActionType? isValidSelector? dispatchAction executeContentAction execInPageAgent] :i [(asl-text/escape :a esc)])

(schema PageContext (:f url Str) (:f title Str) (:f axNodes (List Str)) (:f isSecure Bool))

fn makePageContext url: Str title: Str axNodes: (List Str) isSecure: Bool -> PageContext
  (PageContext :url url :title title :axNodes axNodes :isSecure isSecure)

fn formatPageContext ctx: PageContext -> Str
  (str "(:ax-tree :url \"" (esc/escapeAsnStr ctx.url) "\" :title \"" (esc/escapeAsnStr ctx.title) "\" :secure " (if ctx.isSecure "true" "false") " :nodes [" (stringJoin ctx.axNodes " ") "])")

fn isValidActionType? actionType: Str -> Bool
  (let [(act (stringLower (stringTrim actionType)))]
    (or (= act "click") (or (= act ":click")
      (or (= act "fill") (or (= act ":fill")
        (or (= act "type") (or (= act ":type")
          (or (= act "hover") (or (= act ":hover")
            (or (= act "key") (or (= act ":key")
              (or (= act "scroll") (or (= act ":scroll")
                (or (= act "watchmedia") (or (= act ":watchmedia")
                  (or (= act "extractmedia") (or (= act ":extractmedia")
                    (or (= act "navigate") (or (= act ":navigate")
                      (or (= act "snapshot") (or (= act ":snapshot")
                        (or (= act "execasl") (or (= act ":execasl")
                          (or (= act "execinpageagent") (= act ":execinpageagent")))))))))))))))))))))))))

fn isValidSelector? selector: Str -> Bool
  (let [(clean (stringTrim selector))]
    (and (> (stringLength clean) 0)
      (or (stringStartsWith? clean "#")
        (or (stringStartsWith? clean ".")
          (or (stringStartsWith? clean "[")
            (or (stringStartsWith? clean "//")
              (or (= clean "body")
                (or (= clean "window")
                  (or (= clean "document")
                    (or (= clean "video")
                      (or (stringStartsWith? clean "button")
                        (or (stringStartsWith? clean "input")
                          (or (stringStartsWith? clean "a")
                            (or (stringStartsWith? clean "div")
                              (or (stringStartsWith? clean "span")
                                (or (stringStartsWith? clean "video")
                                  (or (stringStartsWith? clean "main")
                                    (stringStartsWith? clean "article"))))))))))))))))))

fn extractPageContext url: Str title: Str domTree: Str -> Str
  (let [(isSecure (stringStartsWith? url "https://")) (nodeStr (if (stringEmpty? (stringTrim domTree)) "(:node :role \"root\" :name \"empty\")" (str "(:node :role \"document\" :raw \"" (esc/escapeAsnStr domTree) "\")")))] (str "(:ax-tree :url \"" (esc/escapeAsnStr url) "\" :title \"" (esc/escapeAsnStr title) "\" :secure " (if isSecure "true" "false") " :nodes [" nodeStr "])"))

fn dispatchAction actionType: Str selector: Str -> Bool
  (let [(act (stringLower (stringTrim actionType)))]
    (if (or (= act "execinpageagent") (= act ":execinpageagent"))
      true
      (and (isValidActionType? actionType) (isValidSelector? selector))))

fn execInPageAgent script: Str -> Str
  (str "(:execInPageAgent :target \"window.__aslAgent\" :script \"" (esc/escapeAsnStr script) "\" :status :dispatched)")

fn executeContentAction actionType: Str selector: Str value: Str -> Str
  (let [(act (stringLower (stringTrim actionType)))]
    (cond
      ((or (= act "execinpageagent") (= act ":execinpageagent"))
        (execInPageAgent value))
      ((or (= act "extractmedia") (= act ":extractmedia"))
        (str "(:contentActionResult :action \"extractMedia\" :selector \"" (esc/escapeAsnStr selector) "\" :status :ok)"))
      ((dispatchAction actionType selector)
        (str "(:contentActionResult :action \"" (esc/escapeAsnStr actionType) "\" :selector \"" (esc/escapeAsnStr selector) "\" :status :ok)"))
      (else
        (str "(:contentActionResult :action \"" (esc/escapeAsnStr actionType) "\" :status :failed :reason \"invalid-action-or-selector\")"))))

