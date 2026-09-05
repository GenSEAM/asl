import React from 'react';
import Hero from '../../asl-src/components/Hero.asl';
import { Ecosystem } from '../components/Ecosystem';
import KeyCapabilities from '../../asl-src/components/KeyCapabilities.asl';
import TheAgentWay from '../../asl-src/components/TheAgentWay.asl';
import { InBrowserAgent } from '../components/InBrowserAgent';
import { AgentWireProtocol } from '../components/AgentWireProtocol';
import HarnessToolkit from '../../asl-src/components/HarnessToolkit.asl';
import { ModuleGraphVisualizer } from '../components/ModuleGraphVisualizer';
import { EngineeringBlog } from '../components/EngineeringBlog';

export const HomeView: React.FC = () => (
  <main className="flex-1">
    <Hero />
    <Ecosystem />
    <KeyCapabilities />
    <TheAgentWay />
    <AgentWireProtocol />
    <HarnessToolkit />
    <ModuleGraphVisualizer />
    <EngineeringBlog />
    <InBrowserAgent />
  </main>
);
