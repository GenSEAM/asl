import * as RT from "./rt";

export type VNode =
  | { readonly tag: "element"; readonly _0: string; readonly _1: string; readonly _2: VNode[] }
  | { readonly tag: "text"; readonly _0: string };

export function element(_0: string, _1: string, _2: VNode[]): VNode {
    return { tag: "element", _0, _1, _2 };
}

export function text(_0: string): VNode {
    return { tag: "text", _0 };
}

export function renderStatBadge(label: string, value: string): VNode {
    return element("div", "p-3 rounded-lg bg-craft-950 border border-craft-800 flex items-center justify-between", [element("span", "text-craft-400 text-xs font-mono", [text(label)]), element("strong", "text-craft-accent text-xs font-mono font-bold", [text(value)])]);
}

export function renderCraftBanner(title: string, subtitle: string): VNode {
    return element("div", "p-6 rounded-xl border border-craft-accent/40 bg-craft-900/60 shadow-xl", [element("div", "inline-flex items-center gap-2 px-2.5 py-0.5 rounded bg-craft-950 border border-craft-700 text-[10px] text-craft-accent font-mono mb-3", [text("100% ASL S-Expression Component")]), element("h3", "text-lg font-bold text-craft-50 font-mono mb-1", [text(title)]), element("p", "text-xs text-craft-300 font-sans leading-relaxed mb-4", [text(subtitle)]), element("div", "grid grid-cols-1 sm:grid-cols-3 gap-3", [renderStatBadge("First-Run Accuracy", "99.4%"), renderStatBadge("Prompt Footprint", "~500 tokens"), renderStatBadge("Wasm Execution", "< 0.04 ms")])]);
}

export function calculateVdomStats(nodeCount: bigint): bigint {
    return RT.mul(nodeCount, 2n);
}

