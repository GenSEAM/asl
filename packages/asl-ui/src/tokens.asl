(module asl-ui/tokens
  :d "Pure AgentScript 8pt Spatial Grid Tokens and Typography Scale"
  :x [gridStep
      TypographyToken
      makeTypographyToken
      getTypographyToken])

(dfs TypographyToken
  (:f role String)
  (:f fontSize Int64)
  (:f lineHeight Int64)
  (:f fontWeight Int64))

(df makeTypographyToken [(role String)
                         (fontSize Int64)
                         (lineHeight Int64)
                         (fontWeight Int64)] -> TypographyToken
  :d "Constructs a typography token"
  (TypographyToken :role role
                   :fontSize fontSize
                   :lineHeight lineHeight
                   :fontWeight fontWeight))

(df gridStep [(step Int64)] -> Int64
  :d "Computes pixel size for canonical 8pt grid token step scaling with 4px sub-grid"
  (if (<= step 0)
    0
    (* step 4)))

(df getTypographyToken [(role String)] -> TypographyToken
  :d "Returns standard typography scale token for specified role"
  (if (= role "caption")
    (TypographyToken :role "caption" :fontSize 12 :lineHeight 16 :fontWeight 400)
    (if (= role "title")
      (TypographyToken :role "title" :fontSize 20 :lineHeight 28 :fontWeight 600)
      (if (= role "display")
        (TypographyToken :role "display" :fontSize 32 :lineHeight 40 :fontWeight 700)
        (TypographyToken :role "body" :fontSize 14 :lineHeight 20 :fontWeight 400)))))
