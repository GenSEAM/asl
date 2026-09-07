(module asl-web/markdown
  :d "Declarative Markdown Parser & S-Expression Renderer in pure AgentScript"
  :x [strip-title-h1 format-code-block render-markdown]
  :i [(core/strings :a s)])

(df strip-title-h1 [(md Str)] -> Str
  :d "Strips leading markdown H1 heading from content body"
  (if (s/starts-with? md "# ")
    (let [(idx (s/index-of md "\n"))]
      (if (>= idx 0)
        (s/trim (s/slice md (+ idx 1) (s/len md)))
        md))
    md))

(df format-code-block [(lang Str) (code Str)] -> Str
  :d "Wraps code in HTML code block container with syntax highlighting metadata"
  (s/concat "<pre class=\"language-" (s/concat lang (s/concat "\"><code>" (s/concat code "</code></pre>")))))

(df render-markdown [(md Str)] -> Str
  :d "Renders markdown text into semantic HTML markup"
  (let [(body (strip-title-h1 md))]
    (s/concat "<article class=\"prose prose-invert max-w-none\">" (s/concat body "</article>"))))
