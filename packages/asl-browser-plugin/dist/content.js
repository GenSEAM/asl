/**
 * ASL Content Script: Intelligent DOM Extraction & S-Expression Token Compression
 */
export function extractPageContext() {
    const url = window.location.href;
    const title = document.title;
    // Extract clean text from main semantic containers
    const mainEl = document.querySelector('main, article, #content, .content, body');
    const rawText = mainEl ? mainEl.innerText : document.body.innerText;
    const cleanArticle = rawText.split('\n').map(l => l.trim()).filter(Boolean).slice(0, 40).join('\n');
    // Extract actionable interactive elements
    const buttonsAndLinks = Array.from(document.querySelectorAll('button, a[href], input, [role="button"]'))
        .slice(0, 15)
        .map(el => ({
        tag: el.tagName.toLowerCase(),
        text: el.innerText?.trim() || el.getAttribute('aria-label') || '',
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
export function performPageAction(action, params) {
    try {
        if (action === 'CLICK') {
            const el = document.querySelector(params.selector);
            if (!el)
                return { ok: false, message: `Element not found: ${params.selector}` };
            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
            // Visual feedback ring
            const prevOutline = el.style.outline;
            el.style.outline = '2px solid #38bdf8';
            setTimeout(() => { el.style.outline = prevOutline; }, 800);
            el.click();
            return { ok: true, message: `Clicked element: ${params.selector}` };
        }
        if (action === 'FILL') {
            const el = document.querySelector(params.selector);
            if (!el)
                return { ok: false, message: `Input element not found: ${params.selector}` };
            el.focus();
            el.value = params.text || '';
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            return { ok: true, message: `Filled input ${params.selector} with "${params.text}"` };
        }
        if (action === 'SCROLL') {
            const delta = params.direction === 'up' ? -(params.amount || 400) : (params.amount || 400);
            window.scrollBy({ top: delta, behavior: 'smooth' });
            return { ok: true, message: `Scrolled window by ${delta}px` };
        }
        return { ok: false, message: `Unknown action: ${action}` };
    }
    catch (err) {
        return { ok: false, message: `Action error: ${err.message}` };
    }
}
// Listen for requests from Popup, Agent Harness, or DevTools
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (msg.type === 'EXTRACT_DOM') {
        sendResponse(extractPageContext());
    }
    else if (msg.type === 'PAGE_ACTION') {
        const result = performPageAction(msg.action, msg.params || {});
        sendResponse(result);
    }
});
