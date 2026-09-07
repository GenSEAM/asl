import React, { useEffect, useState } from 'react';
import { Navbar as AslNavbar } from './Navbar.asl';
import { SearchModal } from './SearchModal';

export const Navbar: React.FC = () => {
  const [isSearchOpen, setIsSearchOpen] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setIsSearchOpen(false);
      }
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        setIsSearchOpen((prev) => !prev);
      }
    };
    const onOpenSearch = () => setIsSearchOpen(true);
    window.addEventListener('keydown', onKey);
    window.addEventListener('open-search', onOpenSearch);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('open-search', onOpenSearch);
    };
  }, []);

  return (
    <>
      <AslNavbar />
      <SearchModal isOpen={isSearchOpen} onClose={() => setIsSearchOpen(false)} />
    </>
  );
};

export default Navbar;
