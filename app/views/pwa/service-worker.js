const CACHE_VERSION = 'nalakalu-v1';
const CACHE_NAME = `${CACHE_VERSION}-static`;
const RUNTIME_CACHE = `${CACHE_VERSION}-runtime`;

// Assets críticos para precachear
const PRECACHE_URLS = [
    '/',
    '/offline',
    '<%= asset_path "application.css" %>',
    '<%= asset_path "application.js" %>',
    '<%= asset_path "icons/icon-192.png" %>',
    '<%= asset_path "icons/icon-512.png" %>'
];

// Instalación del Service Worker
self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then((cache) => cache.addAll(PRECACHE_URLS))
            .then(() => self.skipWaiting())
    );
});

// Activación y limpieza de cachés antiguos
self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((cacheNames) => {
            return Promise.all(
                cacheNames
                    .filter((name) => name.startsWith('nalakalu-') && name !== CACHE_NAME && name !== RUNTIME_CACHE)
                    .map((name) => caches.delete(name))
            );
        }).then(() => self.clients.claim())
    );
});

// Estrategia de fetch
self.addEventListener('fetch', (event) => {
    const { request } = event;
    const url = new URL(request.url);

    // Solo cachear requests del mismo origen
    if (url.origin !== location.origin) {
        return;
    }

    // Estrategia para navegación (HTML)
    if (request.mode === 'navigate') {
        event.respondWith(
            fetch(request)
                .then((response) => {
                    // Cachear la respuesta en runtime
                    const responseClone = response.clone();
                    caches.open(RUNTIME_CACHE).then((cache) => {
                        cache.put(request, responseClone);
                    });
                    return response;
                })
                .catch(() => {
                    // Si falla, intentar desde caché
                    return caches.match(request)
                        .then((cachedResponse) => {
                            if (cachedResponse) {
                                return cachedResponse;
                            }
                            // Si no hay caché, mostrar página offline
                            return caches.match('/offline');
                        });
                })
        );
        return;
    }

    // Estrategia para assets (CSS, JS, imágenes)
    if (request.destination === 'style' ||
        request.destination === 'script' ||
        request.destination === 'image' ||
        request.destination === 'font') {
        event.respondWith(
            caches.match(request)
                .then((cachedResponse) => {
                    if (cachedResponse) {
                        return cachedResponse;
                    }
                    return fetch(request).then((response) => {
                        // Cachear el nuevo asset
                        const responseClone = response.clone();
                        caches.open(CACHE_NAME).then((cache) => {
                            cache.put(request, responseClone);
                        });
                        return response;
                    });
                })
        );
        return;
    }

    // Para otros requests (API, POST, PATCH), intentar red primero
    event.respondWith(
        fetch(request)
            .catch(() => {
                // Si es GET, intentar desde caché
                if (request.method === 'GET') {
                    return caches.match(request);
                }
                // Si es POST/PATCH y falla, guardar en IndexedDB para sincronizar después
                return saveForSync(request);
            })
    );
});

// Background Sync para acciones pendientes
self.addEventListener('sync', (event) => {
    if (event.tag === 'sync-actions') {
        event.waitUntil(processPendingActions());
    }
});

// Guardar acción para sincronizar después
async function saveForSync(request) {
    const db = await openDB();
    const tx = db.transaction('pending-actions', 'readwrite');
    const store = tx.objectStore('pending-actions');

    const body = await request.clone().text();

    await store.add({
        url: request.url,
        method: request.method,
        headers: Object.fromEntries(request.headers.entries()),
        body: body,
        timestamp: Date.now()
    });

    // Retornar respuesta indicando que se guardó
    return new Response(
        JSON.stringify({ queued: true, message: 'Acción guardada para sincronizar' }),
        { status: 202, headers: { 'Content-Type': 'application/json' } }
    );
}

// Procesar acciones pendientes
async function processPendingActions() {
    const db = await openDB();
    const tx = db.transaction('pending-actions', 'readwrite');
    const store = tx.objectStore('pending-actions');
    const all = await store.getAll();

    for (const action of all) {
        try {
            const response = await fetch(action.url, {
                method: action.method,
                headers: action.headers,
                body: action.body,
                credentials: 'include'
            });

            if (response.ok) {
                // Eliminar de la cola si fue exitoso
                await store.delete(action.id);

                // Notificar a los clientes
                const clients = await self.clients.matchAll();
                clients.forEach(client => {
                    client.postMessage({
                        type: 'ACTION_SYNCED',
                        action: action
                    });
                });
            }
        } catch (error) {
            console.error('Error sincronizando acción:', error);
            // Mantener en la cola para reintentar
        }
    }
}

// Abrir/crear IndexedDB
function openDB() {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open('nalakalu-db', 1);

        request.onerror = () => reject(request.error);

        request.onupgradeneeded = (event) => {
            const db = event.target.result;
            if (!db.objectStoreNames.contains('pending-actions')) {
                db.createObjectStore('pending-actions', { keyPath: 'id', autoIncrement: true });
            }
        };

        request.onsuccess = () => resolve(request.result);
    });
}

// Escuchar mensajes de los clientes
self.addEventListener('message', (event) => {
    if (event.data && event.data.type === 'SKIP_WAITING') {
        self.skipWaiting();
    }

    if (event.data && event.data.type === 'PROCESS_PENDING') {
        event.waitUntil(processPendingActions());
    }
});