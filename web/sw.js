// Dojuboga offline cache, written by DojubogaWeb.export_site.
// The version changes whenever any cached file changes, so the browser
// installs the new copy and removes the old one on the next visit.
const VERSION = "__VERSION__";
const FILES = __FILES__;
const CACHE = "dojuboga-" + VERSION;

self.addEventListener("install", event => {
  event.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k.startsWith("dojuboga-") && k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim()));
});

// Cache first: everything the game needs is stored at install time.
self.addEventListener("fetch", event => {
  const req = event.request;
  if (req.method !== "GET" || new URL(req.url).origin !== self.location.origin) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const hit = await cache.match(req, {ignoreSearch: true});
    if (hit) return hit;
    if (req.mode === "navigate") {
      const page = await cache.match("./");
      if (page) return page;
    }
    return fetch(req);
  })());
});
