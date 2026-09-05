import test from 'node:test';
import assert from 'node:assert/strict';
import { aslPlugin } from '../plugins/vite-plugin-asl.js';

test('aslPlugin - In-Memory ASL Component Transformation', () => {
  const plugin = aslPlugin({ target: 'react' });
  assert.equal(plugin.name, 'vite-plugin-asl');
  assert.equal(plugin.enforce, 'pre');

  const dummyAsl = `(div (:class "p-4 bg-surface") (h2 "Showcase") (p "Reactive Wasm"))`;
  const result = plugin.transform.call(
    { error: (msg) => { throw new Error(msg); } },
    dummyAsl,
    '/app/src/components/Banner.asl'
  );

  assert.ok(result !== null);
  assert.ok(typeof result.code === 'string');
  assert.match(result.code, /export const Banner = \(props: BannerProps\) => \{/);
  assert.match(result.code, /className="asl-banner"/);
  assert.match(result.code, /import React, \{ useState \} from "react";/);
});

test('aslPlugin - Non-ASL files pass-through', () => {
  const plugin = aslPlugin();
  const nonAslResult = plugin.transform.call({}, 'console.log("hello");', '/app/src/main.ts');
  assert.equal(nonAslResult, null);
});
