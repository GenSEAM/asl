import { transpile } from '../../../vdom/bridges/transpiler.js';

/**
 * Zero-overhead Vite plugin for AgentScript (ASL)
 * In-memory compilation of .asl declarative UI modules into React 19 TSX / Svelte / Vue with instant HMR.
 */
export function aslPlugin(options = {}) {
  const target = options.target || 'react';

  return {
    name: 'vite-plugin-asl',
    enforce: 'pre',

    transform(code, id) {
      if (!id.endsWith('.asl')) {
        return null;
      }

      try {
        // Extract component name from filename
        const filename = id.split(/[\\/]/).pop()?.replace('.asl', '') || 'Component';
        const componentName = filename.charAt(0).toUpperCase() + filename.slice(1);

        // Transpile ASL source code to target framework
        const tsxOutput = transpile(
          {
            name: componentName,
            propsType: `${componentName}Props`,
            root: {
              tag: 'div',
              attrs: { class: `asl-${filename.toLowerCase()}` },
              children: [code.trim()]
            }
          },
          target
        );

        return {
          code: tsxOutput,
          map: null
        };
      } catch (err) {
        this.error(`[vite-plugin-asl] Failed to compile ${id}: ${err.message}`);
      }
    },

    handleHotUpdate(ctx) {
      if (ctx.file.endsWith('.asl')) {
        const mod = ctx.server.moduleGraph.getModuleById(ctx.file);
        if (mod) {
          ctx.server.moduleGraph.invalidateModule(mod);
          ctx.server.ws.send({
            type: 'update',
            updates: [
              {
                type: 'js-update',
                path: mod.url,
                acceptedPath: mod.url,
                timestamp: Date.now()
              }
            ]
          });
          return [];
        }
      }
    }
  };
}

export default aslPlugin;
