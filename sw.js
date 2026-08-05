/* FENLORA POS · Service Worker v3 — siempre lo último (network-first, sin caché viejo) + avisos push */
const CACHE = 'fenlora-pos-v3';
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

/* Push del servidor (Fase 2: requiere VAPID + emisor). Muestra el aviso aunque la app esté cerrada. */
self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { try { d = { body: e.data && e.data.text() }; } catch (__) { d = {}; } }
  const title = d.title || '🔔 ¡Pedido listo!';
  const body  = d.body  || 'Tienes un pedido listo para reclamar.';
  e.waitUntil(self.registration.showNotification(title, {
    body, tag: d.tag || 'listo', renotify: true, requireInteraction: true,
    icon: './icon-192.png', badge: './icon-192.png', data: d, vibrate: [220,110,220]
  }));
});

/* Al tocar la notificación: enfocar la app si está abierta, o abrirla. */
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  e.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of all) { if ('focus' in c) { try { await c.focus(); return; } catch (_) {} } }
    if (self.clients.openWindow) return self.clients.openWindow('./');
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
