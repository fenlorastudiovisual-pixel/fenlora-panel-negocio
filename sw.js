/* FENLORA POS · Service Worker — network-first (siempre lo último, con respaldo offline) */
const CACHE = 'fenlora-pos-v1';
const SHELL = ['./', './index.html', './icon-192.png', './icon-512.png', './apple-touch-icon.png'];

self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL).catch(() => {})));
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  let url;
  try { url = new URL(req.url); } catch (_) { return; }
  // Solo manejamos el mismo origen. Supabase, fuentes y CDNs pasan directo (NO se tocan).
  if (url.origin !== location.origin) return;
  // Network-first: intenta la versión más nueva; si no hay internet, usa el caché.
  e.respondWith((async () => {
    try {
      const fresh = await fetch(req);
      const cache = await caches.open(CACHE);
      cache.put(req, fresh.clone()).catch(() => {});
      return fresh;
    } catch (err) {
      const cached = await caches.match(req);
      if (cached) return cached;
      const shell = await caches.match('./index.html');
      if (shell) return shell;
      throw err;
    }
  })());
});
