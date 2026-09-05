declare module "*.asl" {
  import React from "react";
  const component: React.ComponentType<any>;
  export default component;
}

declare module "*transpiler.js" {
  export function transpile(spec: any, target?: string, options?: any): string;
  export function compileToReact(spec: any, options?: any): string;
  export function compileToVue(spec: any, options?: any): string;
  export function compileToSvelte(spec: any, options?: any): string;
  export function compileToSSR(node: any): string;
}
