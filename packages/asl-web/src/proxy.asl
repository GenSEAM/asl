(module asl-web/proxy
  :d "Pure AgentScript Binary PROXY Protocol v2 Parser and Reverse Proxy Header Middleware"
  :x [ProxyV2Header
      makeProxyV2Header
      encodeProxyV2Header
      parseProxyV2Header
      resolveClientIp
      resolveClientProto
      resolveClientHost]
  :i [(asl-http/http11 :a http)])

(dfs ProxyV2Header
  (:f version Int64)
  (:f command String)
  (:f family String)
  (:f protocol String)
  (:f srcIp String)
  (:f dstIp String)
  (:f srcPort Int64)
  (:f dstPort Int64))

(df makeProxyV2Header [(version Int64)
                       (command String)
                       (family String)
                       (protocol String)
                       (srcIp String)
                       (dstIp String)
                       (srcPort Int64)
                       (dstPort Int64)] -> ProxyV2Header
  :d "Constructs ProxyV2Header record"
  (ProxyV2Header :version version
                 :command command
                 :family family
                 :protocol protocol
                 :srcIp srcIp
                 :dstIp dstIp
                 :srcPort srcPort
                 :dstPort dstPort))

(df encodeProxyV2Header [(hdr ProxyV2Header)] -> String
  :d "Serializes PROXY v2 header with 12-byte magic prefix"
  (let [(src (if (and (= (.-family hdr) "AF_INET6") (not (string-starts-with? (.-srcIp hdr) "[")))
               (str "[" (.-srcIp hdr) "]")
               (.-srcIp hdr)))
        (dst (if (and (= (.-family hdr) "AF_INET6") (not (string-starts-with? (.-dstIp hdr) "[")))
               (str "[" (.-dstIp hdr) "]")
               (.-dstIp hdr)))]
    (str "PROXY2:\r\n\r\n\0\r\nQUIT\n:"
         (string-from-int64 (.-version hdr)) ":"
         (.-command hdr) ":"
         (.-family hdr) ":"
         (.-protocol hdr) ":"
         src ":"
         dst ":"
         (string-from-int64 (.-srcPort hdr)) ":"
         (string-from-int64 (.-dstPort hdr)))))

(df parseProxyV2Header [(raw String)] -> (Result ProxyV2Header String)
  :d "Parses and validates PROXY protocol v2 header"
  (let [(magicPrefix "PROXY2:\r\n\r\n\0\r\nQUIT\n:")]
    (if (not (string-starts-with? raw magicPrefix))
      (err "ERR_PROXY_V2_INVALID_MAGIC")
      (let [(payload (option-or (string-slice raw (string-length magicPrefix) (string-length raw)) ""))]
        (if (string-contains? payload "[")
          (let [(pTokens (string-split payload ":"))
                (ver (option-or (string-to-int64 (option-or (list-head pTokens) "")) -1))
                (tok1 (option-or (list-tail pTokens) (list)))
                (cmd (option-or (list-head tok1) ""))
                (tok2 (option-or (list-tail tok1) (list)))
                (fam (option-or (list-head tok2) ""))
                (tok3 (option-or (list-tail tok2) (list)))
                (proto (option-or (list-head tok3) ""))
                (b1Start (option-or (string-index-of payload "[") -1))
                (b1End (option-or (string-index-of payload "]") -1))
                (srcIp (if (and (>= b1Start 0) (> b1End b1Start))
                         (option-or (string-slice payload (+ b1Start 1) b1End) "")
                         ""))
                (rem1 (if (> b1End 0)
                        (option-or (string-slice payload (+ b1End 1) (string-length payload)) "")
                        ""))
                (b2Start (option-or (string-index-of rem1 "[") -1))
                (b2End (option-or (string-index-of rem1 "]") -1))
                (dstIp (if (and (>= b2Start 0) (> b2End b2Start))
                         (option-or (string-slice rem1 (+ b2Start 1) b2End) "")
                         ""))
                (rem2 (if (> b2End 0)
                        (option-or (string-slice rem1 (+ b2End 1) (string-length rem1)) "")
                        ""))
                (cleanRem2 (if (string-starts-with? rem2 ":")
                             (option-or (string-slice rem2 1 (string-length rem2)) "")
                             rem2))
                (tailTokens (string-split cleanRem2 ":"))
                (sPort (option-or (string-to-int64 (option-or (list-head tailTokens) "")) -1))
                (t2 (option-or (list-tail tailTokens) (list)))
                (dPort (option-or (string-to-int64 (option-or (list-head t2) "")) -1))]
            (if (not (= ver 2))
              (err "ERR_PROXY_UNSUPPORTED_VERSION")
              (if (and (not (= cmd "PROXY")) (not (= cmd "LOCAL")))
                (err "ERR_PROXY_INVALID_COMMAND")
                (ok (ProxyV2Header :version ver
                                   :command cmd
                                   :family fam
                                   :protocol proto
                                   :srcIp srcIp
                                   :dstIp dstIp
                                   :srcPort sPort
                                   :dstPort dPort)))))
          (let [(tokens (string-split payload ":"))]
            (if (< (list-length tokens) 8)
              (err "ERR_PROXY_TRUNCATED_HEADER")
              (let [(ver (option-or (string-to-int64 (option-or (list-head tokens) "")) -1))
                    (tok1 (option-or (list-tail tokens) (list)))
                    (cmd (option-or (list-head tok1) ""))
                    (tok2 (option-or (list-tail tok1) (list)))
                    (fam (option-or (list-head tok2) ""))
                    (tok3 (option-or (list-tail tok2) (list)))
                    (proto (option-or (list-head tok3) ""))
                    (tok4 (option-or (list-tail tok3) (list)))
                    (srcIp (option-or (list-head tok4) ""))
                    (tok5 (option-or (list-tail tok4) (list)))
                    (dstIp (option-or (list-head tok5) ""))
                    (tok6 (option-or (list-tail tok5) (list)))
                    (sPort (option-or (string-to-int64 (option-or (list-head tok6) "")) -1))
                    (tok7 (option-or (list-tail tok6) (list)))
                    (dPort (option-or (string-to-int64 (option-or (list-head tok7) "")) -1))]
                (if (not (= ver 2))
                  (err "ERR_PROXY_UNSUPPORTED_VERSION")
                  (if (and (not (= cmd "PROXY")) (not (= cmd "LOCAL")))
                    (err "ERR_PROXY_INVALID_COMMAND")
                    (ok (ProxyV2Header :version ver
                                       :command cmd
                                       :family fam
                                       :protocol proto
                                       :srcIp srcIp
                                       :dstIp dstIp
                                       :srcPort sPort
                                       :dstPort dPort))))))))))))

(df resolveClientIp [(req http/HttpRequest) (proxyHdr (Option ProxyV2Header))] -> String
  :d "Resolves true client IP address evaluating PROXY v2 then standard reverse proxy headers"
  (let [(headerIp (let [(xffOpt (http/getHeader req "X-Forwarded-For"))]
                    (mt xffOpt
                      ((some xff)
                       (let [(parts (string-split xff ","))
                             (firstIp (string-trim (option-or (list-head parts) "")))]
                         (if (not (string-empty? firstIp))
                           firstIp
                           (let [(realOpt (http/getHeader req "X-Real-IP"))]
                             (mt realOpt
                               ((some realIp) (string-trim realIp))
                               ((none) "127.0.0.1"))))))
                      ((none)
                       (let [(realOpt (http/getHeader req "X-Real-IP"))]
                         (mt realOpt
                           ((some realIp) (string-trim realIp))
                           ((none) "127.0.0.1")))))))]
    (mt proxyHdr
      ((some hdr)
       (if (and (= (.-command hdr) "PROXY") (not (string-empty? (.-srcIp hdr))))
         (.-srcIp hdr)
         headerIp))
      ((none) headerIp))))

(df resolveClientProto [(req http/HttpRequest)] -> String
  :d "Resolves client protocol evaluating X-Forwarded-Proto header"
  (let [(protoOpt (http/getHeader req "X-Forwarded-Proto"))]
    (mt protoOpt
      ((some proto)
       (let [(parts (string-split proto ","))
             (cleanProto (string-trim (string-lower (option-or (list-head parts) ""))))]
         (if (not (string-empty? cleanProto))
           cleanProto
           "http")))
      ((none) "http"))))

(df resolveClientHost [(req http/HttpRequest)] -> String
  :d "Resolves virtual host evaluating X-Forwarded-Host then Host header"
  (let [(fHostOpt (http/getHeader req "X-Forwarded-Host"))]
    (mt fHostOpt
      ((some fHost)
       (let [(cleanFHost (string-trim fHost))]
         (if (not (string-empty? cleanFHost))
           cleanFHost
           (option-or (http/getHeader req "Host") ""))))
      ((none)
       (option-or (http/getHeader req "Host") "")))))
