// RubberLedger Service Worker
// ⬆️ เปลี่ยนเลขนี้ทุกครั้งที่ deploy เพื่อล้างแคชเก่า
const CACHE = 'rubberledger-2026.10.27-1700';

// ไฟล์ที่ต้องมีเพื่อเปิดแอปได้ตอนออฟไลน์
const PRECACHE = [
  './',
  './rubber-ledger.html',
  './customer-portal.html',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.118.0/dist/umd/supabase.js',
  'https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js',
  'https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js'
];

const SCOPE_PATH = new URL(self.registration.scope).pathname;   // เช่น /cc/
const OWN_FILES = ['', 'index.html', 'rubber-ledger.html', 'customer-portal.html', 'manifest.json'];
const CDN_LIBS = [
  '/npm/@supabase/supabase-js@2.118.0/',
  '/npm/qrcode-generator@1.4.4/',
  '/npm/chart.js@4.4.0/'
];
function isOwnRequest(url) {
  if (url.origin === self.location.origin) {
    if (!url.pathname.startsWith(SCOPE_PATH)) return false;
    const rest = url.pathname.slice(SCOPE_PATH.length);
    return OWN_FILES.includes(rest) || rest.startsWith('icons/');
  }
  if (url.hostname === 'cdn.jsdelivr.net') return CDN_LIBS.some((p) => url.pathname.startsWith(p));
  return false;
}

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((cache) =>
      // ใส่ทีละไฟล์ — ไฟล์ไหนโหลดไม่ได้ก็ข้าม ไม่ทำให้ติดตั้งล้มทั้งหมด
      Promise.all(PRECACHE.map((u) => cache.add(new Request(u, { cache: 'reload' })).catch(() => {})))
    ).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // ไม่แคช Supabase / API — ข้อมูลต้องสดเสมอ (คิวออฟไลน์ในแอปจัดการเอง)
  if (url.hostname.includes('supabase')) return;

  // ดูแลเฉพาะไฟล์ของ RubberLedger — เว็บอื่นในโฟลเดอร์เดียวกัน (english/, chinese/, reminder/ ฯลฯ)
  // ปล่อยผ่านตามปกติ ไม่ถูกแคช
  if (!isOwnRequest(url)) return;

  // หน้า HTML → network-first (ได้เวอร์ชันล่าสุดเสมอ) ถ้าออฟไลน์ค่อยใช้แคช
  if (req.mode === 'navigate' || req.destination === 'document') {
    e.respondWith(
      fetch(req)
        .then((res) => {
          if (res && res.status === 200) {
            const copy = res.clone();
            caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
          }
          return res;
        })
        .catch(() =>
          caches.match(req, { ignoreSearch: true })
            .then((hit) => hit || (/\/(index\.html)?$/.test(url.pathname) ? caches.match('./rubber-ledger.html') : undefined))
        )
    );
    return;
  }

  // ไฟล์อื่น (ไลบรารี/ฟอนต์/รูป) → ใช้แคชก่อน แล้วอัปเดตเบื้องหลัง
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return;
  e.respondWith(
    caches.open(CACHE).then((cache) =>
      cache.match(req).then((hit) => {
        const net = fetch(req)
          .then((res) => {
            if (res && (res.status === 200 || res.type === 'opaque')) cache.put(req, res.clone()).catch(() => {});
            return res;
          })
          .catch(() => hit);
        return hit || net;
      })
    )
  );
});
