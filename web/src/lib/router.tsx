import React, { createContext, useContext, useEffect, useState } from 'react';

export type Route = '/' | '/playground' | '/ecosystem' | '/roadmap' | '/docs';

interface RouterContextType {
  currentPath: string;
  navigate: (to: string) => void;
}

const RouterContext = createContext<RouterContextType>({
  currentPath: '/',
  navigate: () => {},
});

export const RouterProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [currentPath, setCurrentPath] = useState<string>(() => {
    if (typeof window !== 'undefined') {
      return window.location.pathname || '/';
    }
    return '/';
  });

  useEffect(() => {
    const handlePopState = () => {
      setCurrentPath(window.location.pathname || '/');
    };
    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, []);

  const navigate = (to: string) => {
    if (to.startsWith('#')) {
      // Hash jump on current page
      const el = document.getElementById(to.slice(1));
      if (el) el.scrollIntoView({ behavior: 'smooth' });
      return;
    }

    if (to === currentPath) return;

    window.history.pushState({}, '', to);
    setCurrentPath(to);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  return (
    <RouterContext.Provider value={{ currentPath, navigate }}>
      {children}
    </RouterContext.Provider>
  );
};

export const useRouter = () => useContext(RouterContext);

export const Link: React.FC<{
  to: string;
  className?: string;
  activeClassName?: string;
  children: React.ReactNode;
  onClick?: () => void;
}> = ({ to, className = '', activeClassName = '', children, onClick }) => {
  const { currentPath, navigate } = useRouter();
  const isActive = currentPath === to;

  return (
    <a
      href={to}
      onClick={(e) => {
        e.preventDefault();
        navigate(to);
        if (onClick) onClick();
      }}
      className={`${className} ${isActive ? activeClassName : ''}`}
    >
      {children}
    </a>
  );
};
