const CACHE_VERSION = 'v1.0.0';
const STATIC_CACHE = `static-${CACHE_VERSION}`;
const RUNTIME_CACHE = `runtime-${CACHE_VERSION}`;
const OFFLINE_URL = '/offline';

const STATIC_ASSETS = [
    '/',
    '/offline',
    '/manifest.json',
    // Agrega aquí tus assets compilados (CSS, JS, íconos)
    // Ejemplo: '/assets/application-[hash].css'
];

// ============================================
// INSTALL: Precache de assets estáticos
// ============================================
self.addEventListener('install', (event) => {
    console.log('[SW] Installing service worker...');

    event.waitUntil(
        caches.open(STATIC_CACHE)
            .then((cache) => {
                console.log('[SW] Precaching static assets');
                return cache.addAll(STATIC_ASSETS);
            })
            .then(() => self.skipWaiting())
    );
});

// ============================================
// ACTIVATE: Limpiar cachés antiguas
// ============================================
self.addEventListener('activate', (event) => {
    console.log('[SW] Activating service worker...');

    event.waitUntil(
        caches.keys()
            .then((cacheNames) => {
                return Promise.all(
                    cacheNames
                        .filter((name) => name.startsWith('static-') || name.startsWith('runtime-'))
                        .filter((name) => name !== STATIC_CACHE && name !== RUNTIME_CACHE)
                        .map((name) => {
                            console.log('[SW] Deleting old cache:', name);
                            return caches.delete(name);
                        })
                );
            })
            .then(() => self.clients.claim())
    );
});

// ============================================
// FETCH: Estrategias de caché
// ============================================
self.addEventListener('fetch', (event) => {
    const { request } = event;
    const url = new URL(request.url);

    // Solo manejar requests del mismo origen
    if (url.origin !== location.origin) {
        return;
    }

    // Estrategia según tipo de request
    if (request.method === 'GET') {
        // Assets estáticos: Cache First
        if (isStaticAsset(url.pathname)) {
            event.respondWith(cacheFirst(request));
        }
        // JSON de driver: Stale-While-Revalidate
        else if (isDriverJSON(url.pathname)) {
            event.respondWith(staleWhileRevalidate(request));
        }
        // HTML de navegación: Network First con fallback
        else if (request.mode === 'navigate') {
            event.respondWith(networkFirstWithOffline(request));
        }
        // Otros GET: Network First
        else {
            event.respondWith(networkFirst(request));
        }
    }
    // Mutaciones (POST, PATCH, DELETE): Encolar si offline
    else if (['POST', 'PATCH', 'DELETE', 'PUT'].includes(request.method)) {
        event.respondWith(handleMutation(request));
    }
});

// ============================================
// BACKGROUND SYNC: Vaciar cola de acciones
// ============================================
self.addEventListener('sync', (event) => {
    console.log('[SW] Background sync triggered:', event.tag);

    if (event.tag === 'sync-actions') {
        event.waitUntil(flushPendingActions());
    }
});

// ============================================
// ESTRATEGIAS DE CACHÉ
// ============================================

// Cache First: Sirve de caché, si no existe busca en red
async function cacheFirst(request) {
    const cached = await caches.match(request);
    if (cached) {
        return cached;
    }

    try {
        const response = await fetch(request);
        if (response.ok) {
            const cache = await caches.open(STATIC_CACHE);
            cache.put(request, response.clone());
        }
        return response;
    } catch (error) {
        console.error('[SW] Cache First failed:', error);
        throw error;
    }
}

// Network First: Intenta red primero, fallback a caché
async function networkFirst(request) {
    try {
        const response = await fetch(request);
        if (response.ok) {
            const cache = await caches.open(RUNTIME_CACHE);
            cache.put(request, response.clone());
        }
        return response;
    } catch (error) {
        const cached = await caches.match(request);
        if (cached) {
            return cached;
        }
        throw error;
    }
}

// Network First con página offline para navegación
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
        if (cached) {
            return cached;
        }

        // Fallback a página offline
        const offlinePage = await caches.match(OFFLINE_URL);
        if (offlinePage) {
            return offlinePage;
        }

        throw error;
    }
}

// Stale-While-Revalidate: Sirve caché rápido y actualiza en background
async function staleWhileRevalidate(request) {
    const cache = await caches.open(RUNTIME_CACHE);
    const cached = await cache.match(request);

    const fetchPromise = fetch(request).then((response) => {
        if (response.ok) {
            cache.put(request, response.clone());
        }
        return response;
    }).catch((error) => {
        console.error('[SW] SWR fetch failed:', error);
        return null;
    });

    return cached || fetchPromise;
}

// ============================================
// MANEJO DE MUTACIONES OFFLINE
// ============================================

async function handleMutation(request) {
    try {
        // Intentar enviar directamente
        const response = await fetch(request.clone());
        return response;
    } catch (error) {
        console.log('[SW] Mutation failed, enqueueing:', request.url);

        // Si falla, encolar para Background Sync
        await enqueuePendingAction(request);

        // Registrar sync
        if ('sync' in self.registration) {
            await self.registration.sync.register('sync-actions');
        }

        // Responder con 202 Accepted (encolado)
        return new Response(
            JSON.stringify({
                ok: true,
                queued: true,
                message: 'Acción encolada para sincronizar'
            }),
            {
                status: 202,
                headers: { 'Content-Type': 'application/json' }
            }
        );
    }
}

// ============================================
// COLA DE ACCIONES PENDIENTES (IndexedDB)
// ============================================

function openDB() {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open('DriverAppDB', 1);

        request.onerror = () => reject(request.error);
        request.onsuccess = () => resolve(request.result);

        request.onupgradeneeded = (event) => {
            const db = event.target.result;

            if (!db.objectStoreNames.contains('pending-actions')) {
                const store = db.createObjectStore('pending-actions', { keyPath: 'id', autoIncrement: true });
                store.createIndex('timestamp', 'timestamp', { unique: false });
            }

            if (!db.objectStoreNames.contains('driver-snapshots')) {
                db.createObjectStore('driver-snapshots', { keyPath: 'key' });
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
        body: body,
        timestamp: Date.now(),
        retries: 0
    };

    return new Promise((resolve, reject) => {
        const tx = db.transaction(['pending-actions'], 'readwrite');
        const store = tx.objectStore('pending-actions');
        const req = store.add(action);

        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });
}

async function flushPendingActions() {
    console.log('[SW] Flushing pending actions...');

    const db = await openDB();
    const tx = db.transaction(['pending-actions'], 'readonly');
    const store = tx.objectStore('pending-actions');

    const actions = await new Promise((resolve, reject) => {
        const req = store.getAll();
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });

    console.log(`[SW] Found ${actions.length} pending actions`);

    for (const action of actions) {
        try {
            const response = await fetch(action.url, {
                method: action.method,
                headers: action.headers,
                body: action.body
            });

            if (response.ok) {
                console.log('[SW] Action synced successfully:', action.url);
                await deletePendingAction(action.id);

                // Notificar al cliente
                await notifyClients({ type: 'ACTION_SYNCED', action });
            } else if (response.status === 409 || response.status === 422) {
                // Conflicto o error de validación: marcar para atención manual
                console.warn('[SW] Action requires attention:', action.url, response.status);
                await markActionAsConflict(action.id);

                await notifyClients({
                    type: 'ACTION_CONFLICT',
                    action,
                    status: response.status
                });
            } else {
                // Otro error: incrementar reintentos
                await incrementRetries(action.id);
            }
        } catch (error) {
            console.error('[SW] Failed to sync action:', action.url, error);
            await incrementRetries(action.id);
        }
    }
}

async function deletePendingAction(id) {
    const db = await openDB();
    const tx = db.transaction(['pending-actions'], 'readwrite');
    const store = tx.objectStore('pending-actions');

    return new Promise((resolve, reject) => {
        const req = store.delete(id);
        req.onsuccess = () => resolve();
        req.onerror = () => reject(req.error);
    });
}

async function incrementRetries(id) {
    const db = await openDB();
    const tx = db.transaction(['pending-actions'], 'readwrite');
    const store = tx.objectStore('pending-actions');

    const action = await new Promise((resolve, reject) => {
        const req = store.get(id);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });

    if (action) {
        action.retries = (action.retries || 0) + 1;

        // Si supera 5 reintentos, marcar como conflicto
        if (action.retries > 5) {
            action.requires_attention = true;
        }

        await new Promise((resolve, reject) => {
            const req = store.put(action);
            req.onsuccess = () => resolve();
            req.onerror = () => reject(req.error);
        });
    }
}

async function markActionAsConflict(id) {
    const db = await openDB();
    const tx = db.transaction(['pending-actions'], 'readwrite');
    const store = tx.objectStore('pending-actions');

    const action = await new Promise((resolve, reject) => {
        const req = store.get(id);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });

    if (action) {
        action.requires_attention = true;

        await new Promise((resolve, reject) => {
            const req = store.put(action);
            req.onsuccess = () => resolve();
            req.onerror = () => reject(req.error);
        });
    }
}

async function notifyClients(message) {
    const clients = await self.clients.matchAll({ type: 'window' });
    clients.forEach((client) => {
        client.postMessage(message);
    });
}

// ============================================
// HELPERS
// ============================================

function isStaticAsset(pathname) {
    return pathname.startsWith('/assets/') ||
        pathname.startsWith('/packs/') ||
        pathname.match(/\.(css|js|png|jpg|jpeg|svg|woff|woff2|ttf)$/);
}

function isDriverJSON(pathname) {
    return pathname.startsWith('/driver/') && pathname.endsWith('.json');
}

console.log('[SW] Service Worker loaded');