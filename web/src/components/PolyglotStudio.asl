(module asl-web/polyglot-studio
  :d "Universal Polyglot UI Transpiler Studio in pure AgentScript."
  :x [polyglot-studio render-polyglot-studio]
  :i [])

(df render-polyglot-studio [] -> Str
  :d "Renders the interactive polyglot studio transpiler interface."
  "<div class=\"w-full flex flex-col gap-6 bg-surface border border-line rounded-2xl p-6 shadow-xl\" id=\"polyglot-studio-root\">
    <div class=\"flex flex-wrap items-center justify-between gap-4 border-b border-line pb-4\">
      <div>
        <h3 class=\"text-lg font-bold text-ink flex items-center gap-2\">
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5 text-signal\"><path d=\"m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z\"></path><path d=\"m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65\"></path><path d=\"m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65\"></path></svg>
          Universal Polyglot UI Transpiler Studio
        </h3>
        <p class=\"text-xs text-ink-muted mt-1\">
          Write declarative AgentScript once &mdash; compile directly to React 19, Vue 3, Svelte 5, or zero-overhead SSR HTML.
        </p>
      </div>

      <!-- Framework Target Tabs -->
      <div class=\"flex items-center bg-surface-2 p-1 rounded-xl border border-line\" id=\"ps-tabs\">
        <button type=\"button\" data-target=\"react\" class=\"ps-tab-btn px-3 py-1.5 text-xs font-semibold rounded-lg transition-all capitalize bg-signal text-ground font-bold shadow-sm\">
          React 19 (TSX)
        </button>
        <button type=\"button\" data-target=\"vue\" class=\"ps-tab-btn px-3 py-1.5 text-xs font-semibold rounded-lg transition-all capitalize text-ink-muted hover:text-ink\">
          Vue 3 (SFC)
        </button>
        <button type=\"button\" data-target=\"svelte\" class=\"ps-tab-btn px-3 py-1.5 text-xs font-semibold rounded-lg transition-all capitalize text-ink-muted hover:text-ink\">
          Svelte 5 (Runes)
        </button>
        <button type=\"button\" data-target=\"html\" class=\"ps-tab-btn px-3 py-1.5 text-xs font-semibold rounded-lg transition-all capitalize text-ink-muted hover:text-ink\">
          SSR HTML
        </button>
      </div>
    </div>

    <div class=\"grid grid-cols-1 lg:grid-cols-2 gap-6\">
      <!-- Source Input -->
      <div class=\"flex flex-col gap-2\">
        <div class=\"flex items-center justify-between text-xs font-mono text-ink-muted px-1\">
          <span>Declarative ASL Source</span>
          <span class=\"text-[10px] bg-signal/10 text-signal px-2 py-0.5 rounded border border-signal/20 font-mono\">AgentScript VNode</span>
        </div>
        <textarea
          id=\"ps-asl-source\"
          class=\"w-full h-80 bg-black/80 border border-line/80 rounded-xl p-4 font-mono text-xs text-purple-200 leading-relaxed resize-none focus:outline-none focus:border-signal/70 focus:ring-1 focus:ring-signal/30 selection:bg-signal/40 shadow-inner\"
          spellcheck=\"false\"
        >(div (:class \"p-6 rounded-2xl bg-surface border border-line shadow-lg\")
  (div (:class \"flex items-center gap-3 mb-4\")
    (span (:class \"w-3 h-3 rounded-full bg-signal\") \"\")
    (h2 (:class \"text-xl font-bold text-ink\") \"AgentScript Polyglot VNode\"))
  (p (:class \"text-sm text-ink-muted mb-6 leading-relaxed\")
    \"Single declarative AST compiled natively across modern web targets.\")
  (button (:class \"px-4 py-2 rounded-xl bg-signal text-ground font-semibold\" :onclick \"handleAction\")
    \"Execute Action\"))</textarea>
      </div>

      <!-- Transpiled Output -->
      <div class=\"flex flex-col gap-2 relative\">
        <div class=\"flex items-center justify-between text-xs font-mono text-ink-muted px-1\">
          <span id=\"ps-target-label\">Target Output: REACT</span>
          <button
            type=\"button\"
            id=\"ps-copy-btn\"
            class=\"flex items-center gap-1 text-[11px] text-ink hover:text-signal transition-colors bg-surface-2 px-2 py-0.5 rounded border border-line\"
          >
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\"><rect width=\"14\" height=\"14\" x=\"8\" y=\"8\" rx=\"2\" ry=\"2\"></rect><path d=\"M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2\"></path></svg>
            <span id=\"ps-copy-text\">Copy</span>
          </button>
        </div>
        <pre class=\"w-full h-80 bg-black/80 border border-line/80 rounded-xl p-4 font-mono text-xs text-emerald-400/95 leading-relaxed overflow-auto shadow-inner\"><code id=\"ps-output-code\">import React, { useState } from 'react';

export interface PolyglotCardProps {
  title?: string;
}

export const PolyglotCard: React.FC&lt;PolyglotCardProps&gt; = ({ title }) =&gt; {
  const [isActive, setIsActive] = useState(false);

  const handleAction = () =&gt; {
    setIsActive(!isActive);
  };

  return (
    &lt;div className=\"p-6 rounded-2xl bg-surface border border-line shadow-lg\"&gt;
      &lt;div className=\"flex items-center gap-3 mb-4\"&gt;
        &lt;span className=\"w-3 h-3 rounded-full bg-signal\" /&gt;
        &lt;h2 className=\"text-xl font-bold text-ink\"&gt;{title || \"AgentScript Polyglot VNode\"}&lt;/h2&gt;
      &lt;/div&gt;
      &lt;p className=\"text-sm text-ink-muted mb-6 leading-relaxed\"&gt;
        Single declarative AST compiled natively across modern web targets.
      &lt;/p&gt;
      &lt;button 
        onClick={handleAction}
        className=\"px-4 py-2 rounded-xl bg-signal text-ground font-semibold hover:opacity-90 transition\"
      &gt;
        {isActive ? \"Active State\" : \"Execute Action\"}
      &lt;/button&gt;
    &lt;/div&gt;
  );
};

export default PolyglotCard;</code></pre>
      </div>
    </div>
  </div>

  <script>
    (function() {
      function init() {
        var targets = {
          'react': `import React, { useState } from 'react';

export interface PolyglotCardProps {
  title?: string;
}

export const PolyglotCard: React.FC<PolyglotCardProps> = ({ title }) => {
  const [isActive, setIsActive] = useState(false);

  const handleAction = () => {
    setIsActive(!isActive);
  };

  return (
    <div className=\"p-6 rounded-2xl bg-surface border border-line shadow-lg\">
      <div className=\"flex items-center gap-3 mb-4\">
        <span className=\"w-3 h-3 rounded-full bg-signal\" />
        <h2 className=\"text-xl font-bold text-ink\">{title || \"AgentScript Polyglot VNode\"}</h2>
      </div>
      <p className=\"text-sm text-ink-muted mb-6 leading-relaxed\">
        Single declarative AST compiled natively across modern web targets.
      </p>
      <button 
        onClick={handleAction}
        className=\"px-4 py-2 rounded-xl bg-signal text-ground font-semibold hover:opacity-90 transition\"
      >
        {isActive ? \"Active State\" : \"Execute Action\"}
      </button>
    </div>
  );
};

export default PolyglotCard;`,

          'vue': `<template>
  <div class=\"p-6 rounded-2xl bg-surface border border-line shadow-lg\">
    <div class=\"flex items-center gap-3 mb-4\">
      <span class=\"w-3 h-3 rounded-full bg-signal\" />
      <h2 class=\"text-xl font-bold text-ink\">{{ title || 'AgentScript Polyglot VNode' }}</h2>
    </div>
    <p class=\"text-sm text-ink-muted mb-6 leading-relaxed\">
      Single declarative AST compiled natively across modern web targets.
    </p>
    <button 
      @click=\"handleAction\"
      class=\"px-4 py-2 rounded-xl bg-signal text-ground font-semibold hover:opacity-90 transition\"
    >
      {{ isActive ? 'Active State' : 'Execute Action' }}
    </button>
  </div>
</template>

<script setup lang=\"ts\">
import { ref } from 'vue';

defineProps<{
  title?: string;
}>();

const isActive = ref(false);

const handleAction = () => {
  isActive.value = !isActive.value;
};
</script>`,

          'svelte': `<script lang=\"ts\">
  export let title: string = 'AgentScript Polyglot VNode';
  let isActive: boolean = false;

  function handleAction() {
    isActive = !isActive;
  }
</script>

<div class=\"p-6 rounded-2xl bg-surface border border-line shadow-lg\">
  <div class=\"flex items-center gap-3 mb-4\">
    <span class=\"w-3 h-3 rounded-full bg-signal\" />
    <h2 class=\"text-xl font-bold text-ink\">{title}</h2>
  </div>
  <p class=\"text-sm text-ink-muted mb-6 leading-relaxed\">
    Single declarative AST compiled natively across modern web targets.
  </p>
  <button 
    on:click={handleAction}
    class=\"px-4 py-2 rounded-xl bg-signal text-ground font-semibold hover:opacity-90 transition\"
  >
    {isActive ? 'Active State' : 'Execute Action'}
  </button>
</div>`,

          'html': `<!-- Pure HTML Target -->
<div class=\"p-6 rounded-2xl bg-surface border border-line shadow-lg\">
  <div class=\"flex items-center gap-3 mb-4\">
    <span class=\"w-3 h-3 rounded-full bg-signal\"></span>
    <h2 class=\"text-xl font-bold text-ink\">AgentScript Polyglot VNode</h2>
  </div>
  <p class=\"text-sm text-ink-muted mb-6 leading-relaxed\">
    Single declarative AST compiled natively across modern web targets.
  </p>
  <button class=\"px-4 py-2 rounded-xl bg-signal text-ground font-semibold\">
    Execute Action
  </button>
</div>`
        };

        var currentTarget = 'react';
        var tabBtns = document.querySelectorAll('.ps-tab-btn');
        var outputEl = document.getElementById('ps-output-code');
        var targetLabel = document.getElementById('ps-target-label');
        var copyBtn = document.getElementById('ps-copy-btn');
        var copyText = document.getElementById('ps-copy-text');

        function updateOutput(t) {
          currentTarget = t;
          tabBtns.forEach(function(btn) {
            if (btn.getAttribute('data-target') === t) {
              btn.className = 'ps-tab-btn px-3 py-1.5 text-xs font-semibold rounded-lg transition-all capitalize bg-signal text-ground font-bold shadow-sm';
            } else {
              btn.className = 'ps-tab-btn px-3 py-1.5 text-xs font-semibold rounded-lg transition-all capitalize text-ink-muted hover:text-ink';
            }
          });
          if (targetLabel) targetLabel.textContent = 'Target Output: ' + t.toUpperCase();
          if (outputEl) outputEl.textContent = targets[t] || '';
        }

        tabBtns.forEach(function(btn) {
          btn.addEventListener('click', function() {
            var t = btn.getAttribute('data-target');
            if (t) updateOutput(t);
          });
        });

        if (copyBtn) {
          copyBtn.addEventListener('click', function() {
            var text = outputEl ? outputEl.textContent : '';
            if (navigator.clipboard) {
              navigator.clipboard.writeText(text);
              if (copyText) copyText.textContent = 'Copied';
              setTimeout(function() {
                if (copyText) copyText.textContent = 'Copy';
              }, 2000);
            }
          });
        }
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
      } else {
        init();
      }
    })();
  </script>")

(df polyglot-studio [] -> Str
  :d "Alias for render-polyglot-studio."
  (render-polyglot-studio))
