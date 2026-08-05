/* FENLORA POS · Service Worker v2 — siempre lo último (network-first, sin caché viejo) */
const CACHE = 'fenlora-pos-v2';
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
  // Solo mismo origen. Supabase, fuentes y CDNs pasan directo (NO se tocan).
  if (url.origin !== location.origin) return;

  const esNavegacion = req.mode === 'navigate' || (req.headers.get('accept') || '').includes('text/html');

  e.respondWith((async () => {
    try {
      // Para el HTML: forzamos traer del servidor (sin caché del navegador) → siempre lo último
      const fresh = esNavegacion ? await fetch(req, { cache: 'no-store' }) : await fetch(req);
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
