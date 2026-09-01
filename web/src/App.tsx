import React from 'react';
import { ThemeProvider } from './lib/theme';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { TheAgentWay } from './components/TheAgentWay';
import { AgentWireProtocol } from './components/AgentWireProtocol';
import { Ecosystem } from './components/Ecosystem';
import { Footer } from './components/Footer';

/*
  The public surface is deliberately the language and the wire protocol only. Observability,
  the essay hub and the skills registry are built but withheld until each stands on its own.
*/
export const App: React.FC = () => (
  <ThemeProvider>
    <div className="min-h-screen bg-ground text-ink flex flex-col">
      <Navbar />
      <main className="flex-1">
        <Hero />
        <TheAgentWay />
        <AgentWireProtocol />
        <Ecosystem />
      </main>
      <Footer />
    </div>
  </ThemeProvider>
);

export default App;
