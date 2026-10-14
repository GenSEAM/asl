(module aslSite/tools/feeds
  :x [sitemapXml rssXml]
  :i [(asl-html/html :a h) (aslSite/app/layout :a l) (aslSite/app/blog :a blog)])

fn leaf tag: String s: String -> h/Node
  (h/el tag [] [(h/text s)])

fn xmlDocument root: h/Node -> String
  (str "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" (h/render root) "\n")

fn urlNode r: l/Route -> h/Node
  (h/el "url" [] [(leaf "loc" (str (l/siteUrl) (l/routePath r)))])

fn sitemapXml posts: (List blog/Post) -> String
  (xmlDocument
    (h/el "urlset" [(h/attr "xmlns" "http://www.sitemaps.org/schemas/sitemap/0.9")]
      (map urlNode (listAppend [(l/home) (l/docs) (l/blog)] (map (fn [(p blog/Post)] -> l/Route (l/post p.slug)) posts)))))

fn rfc822 date: String -> String
  (let [(parts (stringSplit date "-"))
        (month (optionOr (stringToInt64 (optionOr (listGet parts 1) "1")) 1))
        (name (optionOr (listGet ["Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"] (- month 1)) "Jan"))]
    (str (optionOr (listGet parts 2) "01") " " name " " (optionOr (listGet parts 0) "2026") " 00:00:00 GMT"))

fn itemNode p: blog/Post -> h/Node
  (let [(url (str (l/siteUrl) (l/routePath (l/post p.slug))))]
    (h/el "item" [] [(leaf "title" p.title) (leaf "link" url) (leaf "guid" url) (leaf "pubDate" (rfc822 p.date)) (leaf "category" p.category) (leaf "description" p.excerpt)]))

fn rssXml posts: (List blog/Post) -> String
  (xmlDocument
    (h/el "rss" [(h/attr "version" "2.0")]
      [(h/el "channel" []
        (listAppend
          [(leaf "title" "AgentSlang blog") (leaf "link" (str (l/siteUrl) "/blog")) (leaf "description" "Notes from building a language for models.") (leaf "language" "en")]
          (map itemNode posts)))]))
