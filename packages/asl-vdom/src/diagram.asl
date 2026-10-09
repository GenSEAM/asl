(module aslVdom/diagram :x [DiagramNode DiagramEdge DiagramSubgraph Diagram makeDiagramNode makeDiagramEdge makeDiagramSubgraph makeDiagram formatNode formatEdge formatSubgraph diagramToMermaid mermaidToHtml diagramToHtml] :i [])

(schema DiagramNode (:f id Str) (:f label Str) (:f shape Str))

(schema DiagramEdge (:f fromId Str) (:f toId Str) (:f label Str) (:f style Str))

(schema DiagramSubgraph (:f id Str) (:f title Str) (:f nodes (List DiagramNode)))

(schema Diagram (:f kind Str) (:f direction Str) (:f subgraphs (List DiagramSubgraph)) (:f edges (List DiagramEdge)))

fn makeDiagramNode id: Str label: Str shape: Str -> DiagramNode
  (DiagramNode :id id :label label :shape shape)

fn makeDiagramEdge fromId: Str toId: Str label: Str -> DiagramEdge
  (DiagramEdge :fromId fromId :toId toId :label label :style "arrow")

fn makeDiagramSubgraph id: Str title: Str nodes: (List DiagramNode) -> DiagramSubgraph
  (DiagramSubgraph :id id :title title :nodes nodes)

fn makeDiagram direction: Str subgraphs: (List DiagramSubgraph) edges: (List DiagramEdge) -> Diagram
  (Diagram :kind "flowchart" :direction direction :subgraphs subgraphs :edges edges)

fn formatNode node: DiagramNode -> Str
  (let [(s node.shape) (id node.id) (lbl node.label)] (if (= s "rounded") (str id "(\"" lbl "\")") (if (= s "stadium") (str id "([" lbl "])") (if (= s "circle") (str id "((\"" lbl "\"))") (if (= s "diamond") (str id "{\"" lbl "\"}") (str id "[\"" lbl "\"]"))))))

fn formatNodeListRec nodes: (List DiagramNode) acc: Str -> Str
  (if (listEmpty? nodes) acc (let [(head (optionOr (listHead nodes) (makeDiagramNode "" "" ""))) (tail (optionOr (listTail nodes) (list))) (line (str "        " (formatNode head) "\n"))] (formatNodeListRec tail (str acc line))))

fn formatSubgraph sub: DiagramSubgraph -> Str
  (let [(nodesStr (formatNodeListRec sub.nodes ""))] (str "    subgraph " sub.id "[\"" sub.title "\"]\n" nodesStr "    end\n"))

fn formatSubgraphsRec subs: (List DiagramSubgraph) acc: Str -> Str
  (if (listEmpty? subs) acc (let [(head (optionOr (listHead subs) (makeDiagramSubgraph "" "" (list)))) (tail (optionOr (listTail subs) (list))) (sgStr (formatSubgraph head))] (formatSubgraphsRec tail (str acc sgStr))))

fn formatEdge edge: DiagramEdge -> Str
  (let [(lbl edge.label)] (if (stringEmpty? lbl) (str "    " edge.fromId " --> " edge.toId "\n") (str "    " edge.fromId " -->|\"" lbl "\"| " edge.toId "\n")))

fn formatEdgesRec edges: (List DiagramEdge) acc: Str -> Str
  (if (listEmpty? edges) acc (let [(head (optionOr (listHead edges) (makeDiagramEdge "" "" ""))) (tail (optionOr (listTail edges) (list))) (eStr (formatEdge head))] (formatEdgesRec tail (str acc eStr))))

fn diagramToMermaid diag: Diagram -> Str
  (str "flowchart " diag.direction "\n" (formatSubgraphsRec diag.subgraphs "") (formatEdgesRec diag.edges ""))

fn mermaidToHtml mermaidCode: Str pageTitle: Str -> Str
  (str "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title>" pageTitle "</title>\n  <style>\n    :root {\n      --bg-primary: #090d16;\n      --bg-secondary: #0f172a;\n      --border-color: #1e293b;\n      --accent-color: #38bdf8;\n      --text-main: #f1f5f9;\n      --text-muted: #94a3b8;\n    }\n    * { box-sizing: border-box; margin: 0; padding: 0; }\n    body {\n      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;\n      background-color: var(--bg-primary);\n      color: var(--text-main);\n      display: flex;\n      flex-direction: column;\n      height: 100vh;\n      overflow: hidden;\n    }\n    header {\n      background: var(--bg-secondary);\n      border-bottom: 1px solid var(--border-color);\n      padding: 12px 24px;\n      display: flex;\n      align-items: center;\n      justify-content: space-between;\n      z-index: 10;\n    }\n    .title {\n      font-size: 16px;\n      font-weight: 600;\n      letter-spacing: -0.01em;\n      display: flex;\n      align-items: center;\n      gap: 10px;\n    }\n    .badge {\n      font-size: 11px;\n      text-transform: uppercase;\n      background: rgba(56, 189, 248, 0.15);\n      color: var(--accent-color);\n      padding: 2px 8px;\n      border-radius: 4px;\n      font-weight: 700;\n    }\n    .toolbar {\n      display: flex;\n      gap: 8px;\n    }\n    button {\n      background: #1e293b;\n      color: var(--text-main);\n      border: 1px solid #334155;\n      padding: 6px 14px;\n      border-radius: 6px;\n      cursor: pointer;\n      font-size: 13px;\n      font-weight: 500;\n      transition: all 0.15s ease;\n    }\n    button:hover {\n      background: #334155;\n      border-color: var(--accent-color);\n      color: #fff;\n    }\n    #viewport {\n      flex: 1;\n      position: relative;\n      overflow: hidden;\n      display: flex;\n      align-items: center;\n      justify-content: center;\n      background: radial-gradient(circle at center, #111827 0%, var(--bg-primary) 100%);\n      cursor: grab;\n    }\n    #viewport:active {\n      cursor: grabbing;\n    }\n    #diagram-container {\n      transform-origin: center center;\n      transition: transform 0.05s ease-out;\n      user-select: none;\n      padding: 40px;\n    }\n    .mermaid {\n      display: flex;\n      justify-content: center;\n    }\n    .mermaid svg {\n      max-width: none !important;\n      height: auto;\n    }\n  </style>\n  <script type=\"module\">\n    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';\n    mermaid.initialize({\n      startOnLoad: true,\n      theme: 'dark',\n      themeVariables: {\n        darkMode: true,\n        background: '#090d16',\n        primaryColor: '#1e293b',\n        primaryBorderColor: '#38bdf8',\n        primaryTextColor: '#f8fafc',\n        lineColor: '#60a5fa',\n        secondaryColor: '#0f172a',\n        tertiaryColor: '#1e293b'\n      }\n    });\n\n    let scale = 1;\n    let pointX = 0;\n    let pointY = 0;\n    let start = { x: 0, y: 0 };\n    let panning = false;\n\n    const viewport = document.getElementById('viewport');\n    const container = document.getElementById('diagram-container');\n\n    function setTransform() {\n      container.style.transform = 'translate(' + pointX + 'px, ' + pointY + 'px) scale(' + scale + ')';\n    }\n\n    viewport.onmousedown = function (e) {\n      if (e.target.tagName === 'BUTTON') return;\n      e.preventDefault();\n      start = { x: e.clientX - pointX, y: e.clientY - pointY };\n      panning = true;\n    };\n\n    window.onmouseup = function () { panning = false; };\n\n    viewport.onmousemove = function (e) {\n      if (!panning) return;\n      e.preventDefault();\n      pointX = (e.clientX - start.x);\n      pointY = (e.clientY - start.y);\n      setTransform();\n    };\n\n    viewport.onwheel = function (e) {\n      e.preventDefault();\n      const xs = (e.clientX - pointX) / scale;\n      const ys = (e.clientY - pointY) / scale;\n      const delta = -e.deltaY;\n      if (delta > 0) {\n        scale *= 1.12;\n      } else {\n        scale /= 1.12;\n      }\n      scale = Math.min(Math.max(0.2, scale), 5);\n      pointX = e.clientX - xs * scale;\n      pointY = e.clientY - ys * scale;\n      setTransform();\n    };\n\n    window.zoomIn = () => { scale *= 1.25; setTransform(); };\n    window.zoomOut = () => { scale /= 1.25; setTransform(); };\n    window.resetZoom = () => { scale = 1; pointX = 0; pointY = 0; setTransform(); };\n    window.exportSvg = () => {\n      const svg = container.querySelector('svg');\n      if (!svg) return;\n      const blob = new Blob([svg.outerHTML], { type: 'image/svg+xml' });\n      const url = URL.createObjectURL(blob);\n      const a = document.createElement('a');\n      a.href = url;\n      a.download = 'diagram.svg';\n      a.click();\n      URL.revokeObjectURL(url);\n    };\n  </script>\n</head>\n<body>\n  <header>\n    <div class=\"title\">\n      <span>" pageTitle "</span>\n      <span class=\"badge\">ASL Native Visual</span>\n    </div>\n    <div class=\"toolbar\">\n      <button onclick=\"window.zoomIn()\">+ Zoom In</button>\n      <button onclick=\"window.zoomOut()\">- Zoom Out</button>\n      <button onclick=\"window.resetZoom()\">Reset</button>\n      <button onclick=\"window.exportSvg()\">Download SVG</button>\n    </div>\n  </header>\n  <div id=\"viewport\">\n    <div id=\"diagram-container\">\n      <pre class=\"mermaid\">\n" mermaidCode "\n      </pre>\n    </div>\n  </div>\n</body>\n</html>")

fn diagramToHtml diag: Diagram pageTitle: Str -> Str
  (mermaidToHtml (diagramToMermaid diag) pageTitle)
