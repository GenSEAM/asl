import React from 'react';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { Playground } from './components/Playground';
import { GraphVisualizer } from './components/GraphVisualizer';
import { VectorClassifier } from './components/VectorClassifier';
import { TargetMatrix } from './components/TargetMatrix';
import { TokenCalculator } from './components/TokenCalculator';
import { ParadigmBridge } from './components/ParadigmBridge';
import { Ecosystem } from './components/Ecosystem';
import { Footer } from './components/Footer';

export const App: React.FC = () => {
  return (
    <div className="min-h-screen bg-craft-950 text-craft-100 flex flex-col">
      <Navbar />
      <main className="flex-1">
        <Hero />
        <Playground />
        <GraphVisualizer />
        <VectorClassifier />
        <ParadigmBridge />
        <TargetMatrix />
        <TokenCalculator />
        <Ecosystem />
      </main>
      <Footer />
    </div>
  );
};

export default App;
