// Installable-app shell only. Nothing from the signed-in pages is cached: every
// request goes to the network, so an update is live the moment it is deployed
// and no old page survives a sign-out.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
