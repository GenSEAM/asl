(module asl-web/hydrate :x [HydrationMismatch parseInlineAsnState hydrateVNodeTree verifyHydrationParity] :i [(vdom :a v)])

(schema HydrationMismatch (:f kind String) (:f path String) (:f expected String) (:f actual String))

fn parseInlineAsnState html: String -> (Result String String)
  (let [(prefix "<script type=\"application/asn\" id=\"asl-state\">") (suffix "</script>") (pStart (optionOr (stringIndexOf html prefix) -1))] (if (< pStart 0) (err "ERR_HYDRATE_MISSING_STATE_SCRIPT") (let [(contentStart (+ pStart (stringLength prefix))) (rest (optionOr (stringSlice html contentStart (stringLength html)) "")) (pEnd (optionOr (stringIndexOf rest suffix) -1))] (if (< pEnd 0) (err "ERR_HYDRATE_UNTERMINATED_STATE_SCRIPT") (let [(rawPayload (optionOr (stringSlice rest 0 pEnd) "")) (unescaped (stringReplace rawPayload "<\\/script>" "</script>"))] (ok unescaped))))))

fn checkChildLoop idx: Int64 sRemaining: (List v/VNode) cRemaining: (List v/VNode) path: String sTag: String -> (Result String HydrationMismatch)
  (if (or (listEmpty? sRemaining) (listEmpty? cRemaining)) (ok "inSync") (let [(sCh (optionOr (listHead sRemaining) (v/text ""))) (cCh (optionOr (listHead cRemaining) (v/text ""))) (subPath (str path "/" sTag "[" (stringFromInt64 idx) "]")) (subRes (verifyNodesRecursive sCh cCh subPath))] (if (err? subRes) subRes (checkChildLoop (+ idx 1) (optionOr (listTail sRemaining) (list)) (optionOr (listTail cRemaining) (list)) path sTag))))

fn verifyNodesRecursive server: v/VNode client: v/VNode path: String -> (Result String HydrationMismatch)
  (mt server ((v/textNode sContent) (mt client ((v/textNode cContent) (if (= sContent cContent) (ok "inSync") (err (HydrationMismatch :kind "text" :path path :expected sContent :actual cContent)))) ((v/elementNode cTag _ _) (err (HydrationMismatch :kind "nodeType" :path path :expected "textNode" :actual cTag))))) ((v/elementNode sTag sAttrs sChildren) (mt client ((v/textNode _) (err (HydrationMismatch :kind "nodeType" :path path :expected sTag :actual "textNode"))) ((v/elementNode cTag cAttrs cChildren) (if (not (= sTag cTag)) (err (HydrationMismatch :kind "tag" :path path :expected sTag :actual cTag)) (let [(sLen (listLength sChildren)) (cLen (listLength cChildren))] (if (not (= sLen cLen)) (err (HydrationMismatch :kind "childCount" :path path :expected (stringFromInt64 sLen) :actual (stringFromInt64 cLen))) (checkChildLoop 0 sChildren cChildren path sTag))))))))

fn verifyHydrationParity server: v/VNode client: v/VNode -> (Result String HydrationMismatch)
  (verifyNodesRecursive server client "root")

fn hydrateVNodeTree client: v/VNode -> (Result v/VNode String)
  (ok client)
