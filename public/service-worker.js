// public/service-worker.js
const CACHE_VERSION = 'v1.1.0';
const STATIC_CACHE = `static-${CACHE_VERSION}`;
const RUNTIME_CACHE = `runtime-${CACHE_VERSION}`;
const OFFLINE_URL = '/offline';

const STATIC_ASSETS = [
    '/',
    '/offline',
    '/manifest.json',
    // Agrega aquí tus assets compilados (CSS, JS, íconos)
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
        // JSON de driver: Stale-While-Revalidate + Snapshot
        else if (isDriverJSON(url.pathname)) {
            event.respondWith(staleWhileRevalidateWithSnapshot(request));
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
// BACKGROUND SYNC: Vaciar colas
// ============================================
self.addEventListener('sync', (event) => {
    console.log('[SW] Background sync triggered:', event.tag);

    if (event.tag === 'sync-actions') {
        event.waitUntil(flushPendingActions());
    } else if (event.tag === 'sync-positions') {
        event.waitUntil(flushPendingPositions());
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

// Stale-While-Revalidate + Snapshot en IndexedDB
async function staleWhileRevalidateWithSnapshot(request) {
    const cache = await caches.open(RUNTIME_CACHE);
    const cached = await cache.match(request);

    const fetchPromise = fetch(request).then(async (response) => {
        if (response.ok) {
            cache.put(request, response.clone());
            // Guardar snapshot en IndexedDB
            const body = await response.clone().text();
            await saveSnapshot(request.url, body);
        }
        return response;
    }).catch(async (error) => {
        console.error('[SW] SWR fetch failed, trying snapshot:', error);
        // Si falla fetch y no hay caché, intentar snapshot
        if (!cached) {
            const snapshot = await getSnapshot(request.url);
            if (snapshot) {
                return new Response(snapshot.body, {
                    status: 200,
                    headers: { 'Content-Type': 'application/json' }
                });
            }
        }
        return null;
    });

    return cached || fetchPromise;
}

// ============================================
// MANEJO DE MUTACIONES OFFLINE
// ============================================

async function handleMutation(request) {
    const url = new URL(request.url);

    try {
        // Intentar enviar directamente
        const response = await fetch(request.clone());
        return response;
    } catch (error) {
        console.log('[SW] Mutation failed, enqueueing:', request.url);

        // Determinar tipo de cola
        if (url.pathname.includes('/update_position')) {
            await enqueuePendingPosition(request);
            if ('sync' in self.registration) {
                await self.registration.sync.register('sync-positions');
            }
        } else {
            await enqueuePendingAction(request);
            if ('sync' in self.registration) {
                await self.registration.sync.register('sync-actions');
            }
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
// INDEXEDDB: Gestión de base de datos
// ============================================

function openDB() {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open('DriverAppDB', 2);

        request.onerror = () => reject(request.error);
        request.onsuccess = () => resolve(request.result);

        request.onupgradeneeded = (event) => {
            const db = event.target.result;

            if (!db.objectStoreNames.contains('pending-actions')) {
                const store = db.createObjectStore('pending-actions', { keyPath: 'id', autoIncrement: true });
                store.createIndex('timestamp', 'timestamp', { unique: false });
            }

            if (!db.objectStoreNames.contains('pending-positions')) {
                const store = db.createObjectStore('pending-positions', { keyPath: 'id', autoIncrement: true });
                store.createIndex('timestamp', 'timestamp', { unique: false });
                store.createIndex('planId', 'planId', { unique: false });
            }

            if (!db.objectStoreNames.contains('driver-snapshots')) {
                db.createObjectStore('driver-snapshots', { keyPath: 'key' });
            }
        };
    });
}

// ============================================
// COLA DE ACCIONES PENDIENTES
// ============================================

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

                await notifyClients({
                    type: 'ACTION_SYNCED',
                    actionId: action.id,
                    url: action.url,
                    method: action.method
                });
            } else if (response.status === 409 || response.status === 422) {
                console.warn('[SW] Action conflict:', action.url, response.status);
                await markActionAsConflict(action.id);

                await notifyClients({
                    type: 'ACTION_CONFLICT',
                    actionId: action.id,
                    url: action.url,
                    status: response.status
                });
            } else {
                await incrementActionRetries(action.id);
            }
        } catch (error) {
            console.error('[SW] Failed to sync action:', action.url, error);
            await incrementActionRetries(action.id);
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

async function incrementActionRetries(id) {
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

// ============================================
// COLA DE POSICIONES GPS
// ============================================

async function enqueuePendingPosition(request) {
    const db = await openDB();
    const body = await request.clone().text();
    const parsedBody = JSON.parse(body);

    // Extraer planId de la URL
    const url = new URL(request.url);
    const planId = url.pathname.match(/\/driver\/delivery_plans\/(\d+)\//)?.[1];

    const position = {
        planId: planId,
        lat: parsedBody.latitude,
        lng: parsedBody.longitude,
        speed: parsedBody.speed,
        heading: parsedBody.heading,
        accuracy: parsedBody.accuracy,
        at: parsedBody.timestamp || new Date().toISOString(),
        timestamp: Date.now(),
        retries: 0
    };

    return new Promise((resolve, reject) => {
        const tx = db.transaction(['pending-positions'], 'readwrite');
        const store = tx.objectStore('pending-positions');
        const req = store.add(position);

        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });
}

async function flushPendingPositions() {
    console.log('[SW] Flushing pending positions...');

    const db = await openDB();
    const tx = db.transaction(['pending-positions'], 'readonly');
    const store = tx.objectStore('pending-positions');

    const positions = await new Promise((resolve, reject) => {
        const req = store.getAll();
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });

    console.log(`[SW] Found ${positions.length} pending positions`);

    // Agrupar por planId
    const groupedByPlan = positions.reduce((acc, pos) => {
        if (!acc[pos.planId]) acc[pos.planId] = [];
        acc[pos.planId].push(pos);
        return acc;
    }, {});

    for (const [planId, planPositions] of Object.entries(groupedByPlan)) {
        // Enviar en lotes de 30
        const batchSize = 30;
        for (let i = 0; i < planPositions.length; i += batchSize) {
            const batch = planPositions.slice(i, i + batchSize);

            try {
                const payload = {
                    positions: batch.map(p => ({
                        lat: p.lat,
                        lng: p.lng,
                        speed: p.speed,
                        heading: p.heading,
                        accuracy: p.accuracy,
                        at: p.at
                    }))
                };

                const response = await fetch(`/driver/delivery_plans/${planId}/update_position_batch`, {
                    method: 'PATCH',
                    headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json'
                    },
                    body: JSON.stringify(payload)
                });

                if (response.ok) {
                    console.log(`[SW] Batch synced for plan ${planId}:`, batch.length);
                    // Eliminar posiciones sincronizadas
                    for (const pos of batch) {
                        await deletePendingPosition(pos.id);
                    }

                    await notifyClients({
                        type: 'POSITIONS_FLUSHED',
                        planId: planId,
                        count: batch.length
                    });
                } else {
                    console.warn(`[SW] Batch sync failed for plan ${planId}:`, response.status);
                    // Incrementar reintentos
                    for (const pos of batch) {
                        await incrementPositionRetries(pos.id);
                    }
                }
            } catch (error) {
                console.error(`[SW] Failed to sync positions for plan ${planId}:`, error);
                for (const pos of batch) {
                    await incrementPositionRetries(pos.id);
                }
            }
        }
    }
}

async function deletePendingPosition(id) {
    const db = await openDB();
    const tx = db.transaction(['pending-positions'], 'readwrite');
    const store = tx.objectStore('pending-positions');

    return new Promise((resolve, reject) => {
        const req = store.delete(id);
        req.onsuccess = () => resolve();
        req.onerror = () => reject(req.error);
    });
}

async function incrementPositionRetries(id) {
    const db = await openDB();
    const tx = db.transaction(['pending-positions'], 'readwrite');
    const store = tx.objectStore('pending-positions');

    const position = await new Promise((resolve, reject) => {
        const req = store.get(id);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });

    if (position) {
        position.retries = (position.retries || 0) + 1;

        if (position.retries > 5) {
            // Descartar posiciones muy antiguas
            await deletePendingPosition(id);
            return;
        }

        await new Promise((resolve, reject) => {
            const req = store.put(position);
            req.onsuccess = () => resolve();
            req.onerror = () => reject(req.error);
        });
    }
}

// ============================================
// SNAPSHOTS DE JSON
// ============================================

async function saveSnapshot(url, body) {
    const db = await openDB();
    const snapshot = {
        key: url,
        body: body,
        fetchedAt: Date.now()
    };

    return new Promise((resolve, reject) => {
        const tx = db.transaction(['driver-snapshots'], 'readwrite');
        const store = tx.objectStore('driver-snapshots');
        const req = store.put(snapshot);

        req.onsuccess = () => resolve();
        req.onerror = () => reject(req.error);
    });
}

async function getSnapshot(url) {
    const db = await openDB();

    return new Promise((resolve, reject) => {
        const tx = db.transaction(['driver-snapshots'], 'readonly');
        const store = tx.objectStore('driver-snapshots');
        const req = store.get(url);

        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });
}

// ============================================
// NOTIFICACIONES A CLIENTES
// ============================================

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
        pathname.match(/\.(css|js|png|jpg|jpeg|svg|woff|woff2|ttf|ico|webmanifest)$/);
}

function isDriverJSON(pathname) {
    return pathname.startsWith('/driver/') && pathname.endsWith('.json');
}

console.log('[SW] Service Worker loaded');