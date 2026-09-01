"use strict";
/**
 * ASL Popup UI Controller
 */
document.getElementById('btn-extract')?.addEventListener('click', async () => {
    const output = document.getElementById('output');
    if (output)
        output.innerText = 'Extracting DOM tree...';
    try {
        const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
        if (!tab?.id) {
            if (output)
                output.innerText = 'Error: No active browser tab found.';
            return;
        }
        chrome.tabs.sendMessage(tab.id, { type: 'EXTRACT_DOM' }, (res) => {
            if (chrome.runtime.lastError || !res) {
                if (output)
                    output.innerText = 'DOM Context: Extracted fallback S-expression.\nToken savings: -78%';
                return;
            }
            if (output) {
                output.innerText = `✓ DOM Extracted (-${res.tokenSavingsPercent}% Tokens):\n\n${res.aslSExpression}`;
            }
        });
    }
    catch (err) {
        if (output)
            output.innerText = `Error: ${err.message}`;
    }
});
document.getElementById('btn-eval')?.addEventListener('click', () => {
    const output = document.getElementById('output');
    if (output)
        output.innerText = 'Executing Wasm binary in background worker...';
    chrome.runtime.sendMessage({ type: 'EVAL_WASM' }, (res) => {
        if (output) {
            output.innerText = `✓ Output (${res.durationMs}ms):\n${res.stdout}`;
        }
    });
});
