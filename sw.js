// The old web version registered this service worker for offline play. The site is now the Godot build,
// which doesn't use one: this version clears the old caches and removes itself for returning players.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) await caches.delete(key);
    await self.registration.unregister();
  })());
});
