import React, { useEffect } from 'react';
import SearchModalAsl from './SearchModal.asl';

export const SearchModal: React.FC<{ isOpen?: boolean; onClose?: () => void }> = ({ isOpen }) => {
  useEffect(() => {
    if (isOpen) {
      window.dispatchEvent(new CustomEvent('open-search'));
    }
  }, [isOpen]);

  return <SearchModalAsl />;
};

export default SearchModal;
