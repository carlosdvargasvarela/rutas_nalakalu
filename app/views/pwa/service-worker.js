// app/views/pwa/service-worker.js.erb
const CACHE_VERSION = "v2.0.0";
const STATIC_CACHE = `driver-static-${CACHE_VERSION}`;
const RUNTIME_CACHE = `driver-runtime-${CACHE_VERSION}`;
const OFFLINE_URL = "/offline";

const STATIC_ASSETS = ["/offline", "/manifest.json"];

// ============================================
// INSTALL
// ============================================
self.addEventListener("install", (event) => {
  console.log("[SW] Installing v2.0.0");
  event.waitUntil(
    caches
      .open(STATIC_CACHE)
      .then((cache) => cache.addAll(STATIC_ASSETS))
      .then(() => self.skipWaiting()),
  );
});

// ============================================
// ACTIVATE
// ============================================
self.addEventListener("activate", (event) => {
  console.log("[SW] Activating v2.0.0");
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((k) => k.startsWith("driver-"))
            .filter((k) => k !== STATIC_CACHE && k !== RUNTIME_CACHE)
            .map((k) => caches.delete(k)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

// ============================================
// FETCH
// ============================================
self.addEventListener("fetch", (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Solo mismo origen
  if (url.origin !== location.origin) return;

  // 🔥 NUNCA interceptar:
  // - /assets/* (importmap, CSS, JS compilado)
  // - /cable (ActionCable)
  // - /rails/* (ActiveStorage, etc.)
  if (
    url.pathname.startsWith("/assets/") ||
    url.pathname.startsWith("/cable") ||
    url.pathname.startsWith("/rails/")
  ) {
    return; // Navegador lo maneja directo
  }

  // Solo cachear dentro de /driver/*
  if (!url.pathname.startsWith("/driver/")) {
    return;
  }

  if (request.method !== "GET") {
    // Mutaciones: encolar si offline
    event.respondWith(handleMutation(request));
    return;
  }

  // GET dentro de /driver/*
  if (url.pathname.endsWith(".json")) {
    // JSON: stale-while-revalidate
    event.respondWith(staleWhileRevalidate(request));
  } else if (request.mode === "navigate") {
    // HTML: network-first con offline fallback
    event.respondWith(networkFirstWithOffline(request));
  } else {
    // Otros: network-first
    event.respondWith(networkFirst(request));
  }
});

// ============================================
// ESTRATEGIAS
// ============================================

async function networkFirst(request) {
  const cache = await caches.open(RUNTIME_CACHE);

  try {
    const response = await fetch(request);
    if (response.ok) cache.put(request, response.clone());
    return response;
  } catch (error) {
    const cached = await cache.match(request);
    if (cached) return cached;
    return new Response("Offline", { status: 503 });
  }
}

async function networkFirstWithOffline(request) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(RUNTIME_CACHE);
      cache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    const cached = await caches.match(request);
    if (cached) return cached;

    const offline = await caches.match(OFFLINE_URL);
    if (offline) return offline;

    throw error;
  }
}

async function staleWhileRevalidate(request) {
  const cache = await caches.open(RUNTIME_CACHE);
  const cached = await cache.match(request);

  const fetchPromise = fetch(request)
    .then((response) => {
      if (response && response.ok) cache.put(request, response.clone());
      return response;
    })
    .catch(() => null);

  const network = await fetchPromise;
  if (cached) return cached;
  if (network) return network;

  return new Response(JSON.stringify({ ok: false, offline: true }), {
    status: 503,
    headers: { "Content-Type": "application/json" },
  });
}

async function handleMutation(request) {
  try {
    return await fetch(request.clone());
  } catch (error) {
    console.log("[SW] Mutation offline, enqueueing:", request.url);
    await enqueuePendingAction(request);

    if ("sync" in self.registration) {
      await self.registration.sync.register("sync-actions");
    }

    return new Response(JSON.stringify({ ok: true, queued: true }), {
      status: 202,
      headers: { "Content-Type": "application/json" },
    });
  }
}

// ============================================
// BACKGROUND SYNC
// ============================================

self.addEventListener("sync", (event) => {
  if (event.tag === "sync-actions") {
    event.waitUntil(flushPendingActions());
  }
});

// ============================================
// INDEXEDDB
// ============================================

function openDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open("DriverAppDB", 3);
    req.onerror = () => reject(req.error);
    req.onsuccess = () => resolve(req.result);
    req.onupgradeneeded = (e) => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains("pending-actions")) {
        db.createObjectStore("pending-actions", {
          keyPath: "id",
          autoIncrement: true,
        });
      }
    };
  });
}

async function enqueuePendingAction(request) {
  const db = await openDB();
  const body = await request.clone().text();
  const action = {
    url: request.url,
    method: request.method,
    headers: Object.fromEntries([...request.headers.entries()]),
    body,
    timestamp: Date.now(),
    retries: 0,
  };

  return new Promise((resolve, reject) => {
    const tx = db.transaction(["pending-actions"], "readwrite");
    const req = tx.objectStore("pending-actions").add(action);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function flushPendingActions() {
  console.log("[SW] Flushing pending actions");
  const db = await openDB();
  const tx = db.transaction(["pending-actions"], "readonly");
  const actions = await new Promise((resolve, reject) => {
    const req = tx.objectStore("pending-actions").getAll();
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });

  for (const action of actions) {
    try {
      const response = await fetch(action.url, {
        method: action.method,
        headers: action.headers,
        body: action.body,
      });

      if (response.ok) {
        await deletePendingAction(action.id);
        await notifyClients({ type: "ACTION_SYNCED", actionId: action.id });
      }
    } catch (error) {
      console.error("[SW] Sync failed:", error);
    }
  }
}

async function deletePendingAction(id) {
  const db = await openDB();
  const tx = db.transaction(["pending-actions"], "readwrite");
  return new Promise((resolve) => {
    tx.objectStore("pending-actions").delete(id);
    tx.oncomplete = () => resolve();
  });
}

async function notifyClients(message) {
  const clients = await self.clients.matchAll({ type: "window" });
  clients.forEach((client) => client.postMessage(message));
}

console.log("[SW] Driver PWA v2.0.0 loaded");
