import React from 'react';
import { ThemeProvider } from './lib/theme';
import { RouterProvider, useRouter } from './lib/router';
import { CosmicLandscapeBackground } from './components/CosmicLandscapeBackground';
import { Navbar } from './components/Navbar';
import { Footer } from './components/Footer';
import { HomeView } from './views/HomeView';
import { PlaygroundView } from './views/PlaygroundView';
import { EcosystemView } from './views/EcosystemView';
import { RoadmapView } from './views/RoadmapView';
import { DocsView } from './views/DocsView';
import { BlogView } from './views/BlogView';

const AppContent: React.FC = () => {
  const { currentPath } = useRouter();

  const renderView = () => {
    if (currentPath === '/playground') return <PlaygroundView />;
    if (currentPath === '/ecosystem') return <EcosystemView />;
    if (currentPath === '/roadmap') return <RoadmapView />;
    if (currentPath === '/docs') return <DocsView />;
    if (currentPath === '/blog' || currentPath.startsWith('/blog/')) return <BlogView />;
    return <HomeView />;
  };

  return (
    <div className="min-h-screen bg-ground text-ink flex flex-col relative w-full max-w-[100vw] overflow-x-hidden">
      <CosmicLandscapeBackground />
      <Navbar />
      <div className="relative z-10 flex-1 flex flex-col">
        {renderView()}
      </div>
      <Footer />
    </div>
  );
};

export const App: React.FC = () => (
  <ThemeProvider>
    <RouterProvider>
      <AppContent />
    </RouterProvider>
  </ThemeProvider>
);

export default App;
