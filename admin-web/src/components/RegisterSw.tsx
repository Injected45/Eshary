'use client';

import { useEffect } from 'react';

/** Makes the platform installable on a phone's home screen (PWA). */
export function RegisterSw() {
  useEffect(() => {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js').catch(() => {});
    }
  }, []);
  return null;
}
