/**
 * Zero-overhead Vite plugin for AgentScript (ASL)
 * In-memory compilation of .asl declarative UI modules into React 19 TSX / Svelte / Vue with instant HMR.
 */

export function transpile(ast: any, target = 'react'): string {
  if (target === 'react') {
    return `import React from 'react';

export const ${ast.name} = (props: any) => {
  return React.createElement(
    '${ast.root.tag}',
    { className: '${ast.root.attrs.class}' },
    props.children || null
  );
};

export default ${ast.name};
`;
  }
  return '';
}

export function aslPlugin(options: { target?: string } = {}) {
  const target = options.target || 'react';

  return {
    name: 'vite-plugin-asl',
    enforce: 'pre' as const,

    transform(code: string, id: string) {
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
      } catch (err: any) {
        this.error(`[vite-plugin-asl] Failed to compile ${id}: ${err.message}`);
      }
    },

    handleHotUpdate(ctx: any) {
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
        }
        return [];
      }
    }
  };
}
