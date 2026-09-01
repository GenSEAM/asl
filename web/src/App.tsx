import React from 'react';
import { ThemeProvider } from './lib/theme';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { TheAgentWay } from './components/TheAgentWay';
import { AgentWireProtocol } from './components/AgentWireProtocol';
import { Ecosystem } from './components/Ecosystem';
import { VoiceAssistant } from './components/VoiceAssistant';
import { Footer } from './components/Footer';

export const App: React.FC = () => (
  <ThemeProvider>
    <div className="min-h-screen bg-ground text-ink flex flex-col">
      <Navbar />
      <main className="flex-1">
        <Hero />
        <TheAgentWay />
        <AgentWireProtocol />
        <Ecosystem />
        <VoiceAssistant />
      </main>
      <Footer />
    </div>
  </ThemeProvider>
);

export default App;
