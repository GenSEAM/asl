(module asl-web/theme-toggle
  :d "Declarative Theme Toggle Component with Sun and Moon SVGs in pure AgentScript"
  :x [render-theme-toggle theme-toggle]
  :i [(asl-text/string :a s)])

(df render-theme-toggle [] -> Str
  :d "Renders the theme toggle button with SVG icons and toggle click handler"
  "<button type=\"button\" onclick=\"(function(){var d=document.documentElement;var isDark=d.classList.contains('dark');if(isDark){d.classList.remove('dark');d.classList.add('light');localStorage.setItem('asl-theme','light');}else{d.classList.remove('light');d.classList.add('dark');localStorage.setItem('asl-theme','dark');}})()\" class=\"w-9 h-9 rounded-full border border-line text-ink-2 hover:text-ink hover:border-line-strong transition-colors flex items-center justify-center cursor-pointer\" title=\"Toggle theme\" aria-label=\"Toggle theme\"><svg class=\"w-4 h-4 dark:hidden\" fill=\"none\" stroke=\"currentColor\" viewBox=\"0 0 24 24\" xmlns=\"http://www.w3.org/2000/svg\"><circle cx=\"12\" cy=\"12\" r=\"4\" stroke-width=\"2\"/><path d=\"M12 2v2m0 16v2M4.93 4.93l1.41 1.41m11.32 11.32l1.41 1.41M2 12h2m16 0h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41\" stroke-width=\"2\" stroke-linecap=\"round\"/></svg><svg class=\"w-4 h-4 hidden dark:block\" fill=\"none\" stroke=\"currentColor\" viewBox=\"0 0 24 24\" xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg></button>")

(df theme-toggle [] -> Str
  :d "Theme toggle component alias"
  (render-theme-toggle))
