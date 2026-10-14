(module asl-html/convert
  :x [kinds convertSource]
  :i [(asl-html/asnSvg :a svg) (asl-html/asnHtml :a ph) (asl-html/asnCss :a pc)])

fn kinds -> (List String)
  ["svg" "html" "css"]

fn convertSource kind: String source: String -> (Result String (List String))
  (cond
    ((= kind "svg") (svg/asnToSvg source))
    ((= kind "html") (ph/asnToHtml source))
    ((= kind "css") (pc/asnToCss source))
    (else (err [(str "unknown kind " kind "; known: svg html css")])))
