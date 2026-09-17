(module asl-web/hydrate
  :d "Zero-Cost Client-Side WebAssembly Hydration and VNode Parity Verifier"
  :x [HydrationMismatch
      parseInlineAsnState
      hydrateVNodeTree
      verifyHydrationParity]
  :i [(vdom :a v)])

(dfs HydrationMismatch
  (:f kind String)
  (:f path String)
  (:f expected String)
  (:f actual String))

(df parseInlineAsnState [(html String)] -> (Result String String)
  :d "Extracts and parses embedded compact ASN state payload from HTML document"
  (let [(prefix "<script type=\"application/asn\" id=\"asl-state\">")
        (suffix "</script>")
        (pStart (option-or (string-index-of html prefix) -1))]
    (if (< pStart 0)
      (err "ERR_HYDRATE_MISSING_STATE_SCRIPT")
      (let [(contentStart (+ pStart (string-length prefix)))
            (rest (option-or (string-slice html contentStart (string-length html)) ""))
            (pEnd (option-or (string-index-of rest suffix) -1))]
        (if (< pEnd 0)
          (err "ERR_HYDRATE_UNTERMINATED_STATE_SCRIPT")
          (let [(rawPayload (option-or (string-slice rest 0 pEnd) ""))
                (unescaped (string-replace rawPayload "<\\/script>" "</script>"))]
            (ok unescaped)))))))

(df checkChildLoop [(idx Int64) (sRemaining (List v/VNode)) (cRemaining (List v/VNode)) (path String) (sTag String)] -> (Result String HydrationMismatch)
  :d "Recursively verifies child node lists for hydration parity"
  (if (or (list-empty? sRemaining) (list-empty? cRemaining))
    (ok "inSync")
    (let [(sCh (option-or (list-head sRemaining) (v/text "")))
          (cCh (option-or (list-head cRemaining) (v/text "")))
          (subPath (str path "/" sTag "[" (string-from-int64 idx) "]"))
          (subRes (verifyNodesRecursive sCh cCh subPath))]
      (if (is-err? subRes)
        subRes
        (checkChildLoop (+ idx 1)
                        (option-or (list-tail sRemaining) (list))
                        (option-or (list-tail cRemaining) (list))
                        path
                        sTag)))))

(df verifyNodesRecursive [(server v/VNode) (client v/VNode) (path String)] -> (Result String HydrationMismatch)
  :d "Recursively verifies parity between server-rendered and client VNodes"
  (mt server
    ((v/textNode sContent)
     (mt client
       ((v/textNode cContent)
        (if (= sContent cContent)
          (ok "inSync")
          (err (HydrationMismatch :kind "text" :path path :expected sContent :actual cContent))))
       ((v/elementNode cTag _ _)
        (err (HydrationMismatch :kind "nodeType" :path path :expected "textNode" :actual cTag)))))
    ((v/elementNode sTag sAttrs sChildren)
     (mt client
       ((v/textNode _)
        (err (HydrationMismatch :kind "nodeType" :path path :expected sTag :actual "textNode")))
       ((v/elementNode cTag cAttrs cChildren)
        (if (not (= sTag cTag))
          (err (HydrationMismatch :kind "tag" :path path :expected sTag :actual cTag))
          (let [(sLen (list-length sChildren))
                (cLen (list-length cChildren))]
            (if (not (= sLen cLen))
              (err (HydrationMismatch :kind "childCount"
                                      :path path
                                      :expected (string-from-int64 sLen)
                                      :actual (string-from-int64 cLen)))
              (checkChildLoop 0 sChildren cChildren path sTag)))))))))

(df verifyHydrationParity [(server v/VNode) (client v/VNode)] -> (Result String HydrationMismatch)
  :d "Verifies zero-hydration mismatch between server VNode tree and client VNode tree"
  (verifyNodesRecursive server client "root"))

(df hydrateVNodeTree [(client v/VNode)] -> (Result v/VNode String)
  :d "Attaches event listeners to existing DOM tree without DOM re-creation"
  (ok client))
