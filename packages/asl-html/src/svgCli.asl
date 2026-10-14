(module asl-html/svgCli
  :x [! main]
  :i [(asl-html/asnSvg :a conv)])

fn ! main -> Int64
  (let [(input (optionOr (envGet "IN") ""))
        (output (optionOr (envGet "OUT") ""))]
    (if (stringEmpty? input)
      (do (eprintln "usage: IN=drawing.asn [OUT=drawing.svg] asl-host run asl/packages/asl-html/src/svgCli.asl") 2)
      (mt (fileRead input)
        ((err e) (do (eprintln (str "svg: cannot read " input)) 2))
        ((ok source)
          (mt (conv/asnToSvg source)
            ((err es) (do (eprintln (stringJoin (map (fn [(e String)] -> String (str "ERR_SVG " input ": " e)) es) "\n")) 1))
            ((ok svgText)
              (if (stringEmpty? output)
                (do (print svgText) 0)
                (mt (fileWrite output svgText)
                  ((ok _) (do (eprintln (str "wrote " output)) 0))
                  ((err e) (do (eprintln (str "svg: cannot write " output)) 2))))))))))
