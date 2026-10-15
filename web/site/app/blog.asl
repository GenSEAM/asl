(module aslSite/app/blog
  :x [Post blogIndexPage postPage notFoundPage]
  :i [(asl-html/html :a h) (asl-html/markdown :a md) (aslSite/app/layout :a l)])

(schema Post (:f slug String) (:f title String) (:f date String) (:f author String) (:f category String) (:f readTime String) (:f excerpt String) (:f content String))

fn byline p: Post -> h/Node
  (h/div [(h/cls "byline")] [(h/time [(h/attr "datetime" p.date)] [(h/text p.date)]) (h/span [] [(h/text p.category)]) (h/span [] [(h/text p.readTime)])])

fn postItem p: Post -> h/Node
  (h/li [] [(h/a [(h/href (l/routePath (l/post p.slug)))] [(h/span [(h/cls "micro")] [(h/text (str p.date " · " p.category))]) (h/h3 [(h/cls "h3")] [(h/text p.title)]) (h/p [] [(h/text p.excerpt)])])])

fn blogIndexPage posts: (List Post) -> h/Node
  (l/document (l/blog) "AgentSlang blog" "Notes on AgentSlang (ASL): language design for model-written code, the wire protocol, the toolbelt and the WebAssembly target."
    [(h/div [(h/cls "shell page")]
      [(h/div [(h/cls "head")] [(l/eyebrow "BLOG" "Engineering notes") (h/h1 [(h/cls "h2")] [(h/text "Notes from building a language for models.")])])
       (h/ul [(h/cls "posts")] (map postItem posts))])])

fn metaLine? line: String -> Bool
  (or (stringStartsWith? line "*Published on") (stringStartsWith? line "*Canonical URL"))

fn postPage p: Post -> h/Node
  (l/document (l/post p.slug) (str p.title " · AgentSlang") p.excerpt
    [(h/div [(h/cls "shell page")]
      [(h/article [(h/cls "prose")]
        (listAppend
          [(h/a [(h/href "/blog") (h/cls "micro")] [(h/text "← All posts")]) (h/h1 [] [(h/text p.title)]) (byline p)]
          (md/blocks (filter (fn [(line String)] -> Bool (not (metaLine? line))) (stringLines p.content)))))])])

fn notFoundPage -> h/Node
  (l/document (l/missing) "Not found · AgentSlang" "This page does not exist."
    [(h/div [(h/cls "shell page")]
      [(h/div [(h/cls "head")]
        [(l/eyebrow "404" "Not found") (h/h1 [(h/cls "h2")] [(h/text "Nothing is defined at this address.")])
         (h/p [(h/cls "lead")] [(h/text "The page may have moved when the site was rebuilt in ASL. Start from the home page, the docs or the blog.")])])
       (h/ul [(h/cls "toc")] [(h/li [] [(h/a [(h/href "/")] [(h/text "Home")])]) (h/li [] [(h/a [(h/href "/docs")] [(h/text "Docs")])]) (h/li [] [(h/a [(h/href "/blog")] [(h/text "Blog")])])])])])
