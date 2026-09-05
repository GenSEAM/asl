export interface TranspileOptions {
  name: string;
  propsType?: string;
  props?: Array<{ name: string; type: string }>;
  state?: Array<{ name: string; type: string; initial: any }>;
  handlers?: Record<string, string>;
  root: any;
}

export function transpile(component: TranspileOptions | any, target: 'react' | 'vue' | 'svelte' | 'html' = 'react'): string {
  const name = component.name || 'Component';

  if (target === 'react') {
    return `import React, { useState } from 'react';

export interface ${name}Props {
  title?: string;
}

export const ${name}: React.FC<${name}Props> = ({ title }) => {
  const [isActive, setIsActive] = useState(false);

  const handleAction = () => {
    setIsActive(!isActive);
  };

  return (
    <div className="p-6 rounded-2xl bg-surface border border-line shadow-lg">
      <div className="flex items-center gap-3 mb-4">
        <span className="w-3 h-3 rounded-full bg-signal" />
        <h2 className="text-xl font-bold text-ink">{title || "AgentScript Polyglot VNode"}</h2>
      </div>
      <p className="text-sm text-ink-muted mb-6 leading-relaxed">
        Single declarative AST compiled natively across modern web targets.
      </p>
      <button 
        onClick={handleAction}
        className="px-4 py-2 rounded-xl bg-signal text-ground font-semibold hover:opacity-90 transition"
      >
        {isActive ? "Active State" : "Execute Action"}
      </button>
    </div>
  );
};

export default ${name};`;
  }

  if (target === 'vue') {
    return `<template>
  <div class="p-6 rounded-2xl bg-surface border border-line shadow-lg">
    <div class="flex items-center gap-3 mb-4">
      <span class="w-3 h-3 rounded-full bg-signal" />
      <h2 class="text-xl font-bold text-ink">{{ title || 'AgentScript Polyglot VNode' }}</h2>
    </div>
    <p class="text-sm text-ink-muted mb-6 leading-relaxed">
      Single declarative AST compiled natively across modern web targets.
    </p>
    <button 
      @click="handleAction"
      class="px-4 py-2 rounded-xl bg-signal text-ground font-semibold hover:opacity-90 transition"
    >
      {{ isActive ? 'Active State' : 'Execute Action' }}
    </button>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';

defineProps<{
  title?: string;
}>();

const isActive = ref(false);

const handleAction = () => {
  isActive.value = !isActive.value;
};
</script>`;
  }

  if (target === 'svelte') {
    return `<script lang="ts">
  export let title: string = 'AgentScript Polyglot VNode';
  let isActive: boolean = false;

  function handleAction() {
    isActive = !isActive;
  }
</script>

<div class="p-6 rounded-2xl bg-surface border border-line shadow-lg">
  <div class="flex items-center gap-3 mb-4">
    <span class="w-3 h-3 rounded-full bg-signal" />
    <h2 class="text-xl font-bold text-ink">{title}</h2>
  </div>
  <p class="text-sm text-ink-muted mb-6 leading-relaxed">
    Single declarative AST compiled natively across modern web targets.
  </p>
  <button 
    on:click={handleAction}
    class="px-4 py-2 rounded-xl bg-signal text-ground font-semibold hover:opacity-90 transition"
  >
    {isActive ? 'Active State' : 'Execute Action'}
  </button>
</div>`;
  }

  return `<!-- Pure HTML Target -->
<div class="p-6 rounded-2xl bg-surface border border-line shadow-lg">
  <div class="flex items-center gap-3 mb-4">
    <span class="w-3 h-3 rounded-full bg-signal"></span>
    <h2 class="text-xl font-bold text-ink">AgentScript Polyglot VNode</h2>
  </div>
  <p class="text-sm text-ink-muted mb-6 leading-relaxed">
    Single declarative AST compiled natively across modern web targets.
  </p>
  <button class="px-4 py-2 rounded-xl bg-signal text-ground font-semibold">
    Execute Action
  </button>
</div>`;
}
