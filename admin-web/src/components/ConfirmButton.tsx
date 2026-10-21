'use client';

import type { ReactNode } from 'react';

/** A submit button that asks first (suspending, deactivating, sending to everyone). */
export function ConfirmButton({
  message,
  className = 'btn',
  name,
  value,
  children,
}: {
  message: string;
  className?: string;
  name?: string;
  value?: string;
  children: ReactNode;
}) {
  return (
    <button
      type="submit"
      className={className}
      name={name}
      value={value}
      onClick={(e) => {
        if (!window.confirm(message)) e.preventDefault();
      }}
    >
      {children}
    </button>
  );
}
