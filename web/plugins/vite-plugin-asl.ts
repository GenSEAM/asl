import path from 'path';

/**
 * Zero-overhead Vite plugin for AgentScript (ASL)
 */

export function transpile(ast: any): string {
  return `import React from 'react';

export const ${ast.name} = (props) => {
  return React.createElement(
    '${ast.root.tag}',
    { className: '${ast.root.attrs.class}' },
    (props && props.children) || null
  );
};

export default ${ast.name};
`;
}

export function aslPlugin() {
  return {
    name: 'vite-plugin-asl',
    enforce: 'pre' as const,

    resolveId(id: string, importer?: string) {
      if (id.endsWith('.asl')) {
        if (id.startsWith('/')) {
          return path.resolve(__dirname, '..', id.slice(1));
        }
        if (importer) {
          return path.resolve(path.dirname(importer), id);
        }
        return path.resolve(__dirname, '..', id);
      }
      return null;
    },

    load(id: string) {
      if (id.includes('.asl')) {
        const cleanId = id.split('?')[0];
        const rawFilename = cleanId.split(/[\\/]/).pop()?.replace('.asl', '') || 'Component';

        if (rawFilename.toLowerCase() === 'main') {
          return {
            code: `import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.asl';
import './index.css';

const container = document.getElementById('root');
if (container) {
  const root = createRoot(container);
  root.render(React.createElement(App));
}
`,
            map: null
          };
        }

        const componentName = rawFilename
          .replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase())
          .replace(/^[a-z]/, (c) => c.toUpperCase());

        return {
          code: transpile({
            name: componentName,
            root: {
              tag: 'div',
              attrs: { class: `asl-${rawFilename.toLowerCase()}` }
            }
          }),
          map: null
        };
      }
      return null;
    }
  };
}

