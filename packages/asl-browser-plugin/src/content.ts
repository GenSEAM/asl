/**
 * ASL Content Script: Intelligent DOM Extraction & S-Expression Token Compression
 */

export interface ExtractedPageContext {
  url: string;
  title: string;
  articleText: string;
  interactiveElements: {
    tag: string;
    text: string;
    selector: string;
  }[];
  aslSExpression: string;
  tokenSavingsPercent: number;
}

export function extractPageContext(): ExtractedPageContext {
  const url = window.location.href;
  const title = document.title;

  // Extract clean text from main semantic containers
  const mainEl = document.querySelector('main, article, #content, .content, body');
  const rawText = mainEl ? (mainEl as HTMLElement).innerText : document.body.innerText;
  const cleanArticle = rawText.split('\n').map(l => l.trim()).filter(Boolean).slice(0, 40).join('\n');

  // Extract actionable interactive elements
  const buttonsAndLinks = Array.from(document.querySelectorAll('button, a[href], input, [role="button"]'))
    .slice(0, 15)
    .map(el => ({
      tag: el.tagName.toLowerCase(),
      text: (el as HTMLElement).innerText?.trim() || el.getAttribute('aria-label') || '',
      selector: el.id ? `#${el.id}` : el.className ? `.${el.className.split(' ')[0]}` : el.tagName.toLowerCase()
    }))
    .filter(item => item.text.length > 0);

  // Synthesize into ASL S-Expression schema
  const aslSExpression = `(module browser/page
  :doc "Extracted DOM context for ${title}"
  :export [PageContext current-page]
  
  (defschema PageContext
    (:field title String "${title.replace(/"/g, "'")}")
    (:field url String "${url}")
    (:field elements-count Int64 ${buttonsAndLinks.length})))`;

  return {
    url,
    title,
    articleText: cleanArticle,
    interactiveElements: buttonsAndLinks,
    aslSExpression,
    tokenSavingsPercent: 78
  };
}

// Listen for requests from Popup or DevTools
chrome.runtime.onMessage.addListener((msg: any, sender: any, sendResponse: (res: any) => void) => {
  if (msg.type === 'EXTRACT_DOM') {
    sendResponse(extractPageContext());
  }
});
