-- =====================================================================
-- RubberLedger — ขั้นที่ 0: โครงสร้างฐานข้อมูลหลัก (สร้างใหม่ทั้งหมด)
-- วันที่: 2026-10-21
--
-- ⚠ ไฟล์นี้ลบตารางหลักเดิมและข้อมูลทั้งหมดในนั้น — ใช้เฉพาะตอนตั้งระบบใหม่
--
-- ลำดับการรันบนโปรเจกต์ใหม่:
--   00-base-schema.sql → setup-remaining.sql → สร้างบัญชีแอดมิน (ดูท้ายไฟล์)
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DROP TABLE IF EXISTS public.order_items   CASCADE;
DROP TABLE IF EXISTS public.receipts      CASCADE;
DROP TABLE IF EXISTS public.orders        CASCADE;
DROP TABLE IF EXISTS public.customers     CASCADE;
DROP TABLE IF EXISTS public.app_data      CASCADE;
DROP TABLE IF EXISTS public.activity_logs CASCADE;
DROP TABLE IF EXISTS public.staff_sessions CASCADE;
DROP TABLE IF EXISTS public.accounts      CASCADE;

-- ── พนักงาน ─────────────────────────────────────────────────────────
CREATE TABLE public.accounts (
  username       TEXT PRIMARY KEY,
  password       TEXT,                       -- เลิกใช้ (01 จะล้างเป็น NULL)
  pass_hash      TEXT,                       -- bcrypt
  role           TEXT NOT NULL DEFAULT 'staff_biller'
                 CHECK (role IN ('admin','staff_biller','staff_cashier','staff')),
  display_name   TEXT,
  is_active      BOOLEAN NOT NULL DEFAULT true,
  deactivated_at TIMESTAMPTZ,
  deactivated_by TEXT,
  failed_count   INT DEFAULT 0,
  locked_until   TIMESTAMPTZ,
  last_login     TIMESTAMPTZ,
  loc_village    TEXT,
  loc_district   TEXT,
  loc_city       TEXT,
  loc_province   TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── ลูกค้า ─────────────────────────────────────────────────────────
CREATE TABLE public.customers (
  id           TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  phone        TEXT DEFAULT '',
  house        TEXT DEFAULT '',
  subdistrict  TEXT DEFAULT '',
  district     TEXT DEFAULT '',
  province     TEXT DEFAULT '',
  auto_created BOOLEAN DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_customers_name ON public.customers (LOWER(TRIM(name)));

-- ── ใบเก็บซื้อ (บิล) ───────────────────────────────────────────────
CREATE TABLE public.orders (
  id            TEXT PRIMARY KEY,
  po_no         TEXT NOT NULL,
  customer      TEXT NOT NULL,
  date          DATE,
  note          TEXT DEFAULT '',
  status        TEXT NOT NULL DEFAULT 'draft'
                CHECK (status IN ('draft','sent','paid','cancelled')),
  subtotal      NUMERIC(14,2) DEFAULT 0,
  total_qty     NUMERIC(14,2) DEFAULT 0,
  grand_total   NUMERIC(14,2) DEFAULT 0,
  created_by    TEXT DEFAULT '',
  paid_by       TEXT,
  paid_at       TIMESTAMPTZ,
  sent_at       TIMESTAMPTZ,
  cancel_reason TEXT,
  cancelled_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT orders_po_no_key UNIQUE (po_no)
);
CREATE INDEX idx_orders_customer   ON public.orders (LOWER(TRIM(customer)));
CREATE INDEX idx_orders_status     ON public.orders (status);
CREATE INDEX idx_orders_updated_at ON public.orders (updated_at DESC);
CREATE INDEX idx_orders_created_at ON public.orders (created_at DESC);

-- updated_at ตั้งจากเวลาเซิร์ฟเวอร์เสมอ (ไม่พึ่งนาฬิกาเครื่องพนักงาน) → การซิงก์ไม่ตกหล่น
CREATE OR REPLACE FUNCTION public._touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END $$;
CREATE TRIGGER trg_orders_touch
  BEFORE INSERT OR UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._touch_updated_at();

-- ── รายการในบิล ──────────────────────────────────────────────────
CREATE TABLE public.order_items (
  id         BIGSERIAL PRIMARY KEY,
  order_id   TEXT NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL DEFAULT 'RUBBER',
  qty        NUMERIC(14,2),
  price      NUMERIC(14,2) DEFAULT 0,
  sort_order INT DEFAULT 0
);
CREATE INDEX idx_order_items_order ON public.order_items (order_id);

-- ── ใบเสร็จ ─────────────────────────────────────────────────────
CREATE TABLE public.receipts (
  id             BIGSERIAL PRIMARY KEY,
  receipt_no     TEXT NOT NULL,
  order_id       TEXT REFERENCES public.orders(id) ON DELETE SET NULL,
  po_no          TEXT,
  customer       TEXT,
  amount         NUMERIC(14,2) DEFAULT 0,
  total_qty      NUMERIC(14,2) DEFAULT 0,
  pay_method     TEXT DEFAULT 'cash',
  issued_by      TEXT,
  issued_by_name TEXT,
  issued_role    TEXT,
  work_location  TEXT DEFAULT '',
  note           TEXT DEFAULT '',
  issued_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT receipts_receipt_no_key UNIQUE (receipt_no)
);
CREATE INDEX idx_receipts_issued_at ON public.receipts (issued_at DESC);
CREATE INDEX idx_receipts_order     ON public.receipts (order_id);

-- ── ค่าตั้งระบบ (ราคา, ตัวนับ PO) ─────────────────────────────────
CREATE TABLE public.app_data (
  key        TEXT PRIMARY KEY,
  value      TEXT,
  updated_at TIMESTAMPTZ DEFAULT now()
);
INSERT INTO public.app_data(key, value) VALUES
  ('rubber_prices', '{"RUBBER":62.5,"SHIPPING":62.5}'),
  ('rubber_po_counter', '1');

-- ── บันทึกกิจกรรม ─────────────────────────────────────────────────
CREATE TABLE public.activity_logs (
  id            BIGSERIAL PRIMARY KEY,
  action        TEXT NOT NULL,
  actor         TEXT,
  actor_role    TEXT,
  target_id     TEXT,
  target_ref    TEXT,
  detail        TEXT,
  work_location TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_activity_created ON public.activity_logs (created_at DESC);

-- ── RLS เปิดไว้ก่อน (02 จะใส่ policy ตาม staff token) ─────────────────
ALTER TABLE public.accounts      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipts      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_data      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.accounts FROM anon, authenticated;

-- Realtime สำหรับตารางบิล
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (SELECT 1 FROM pg_publication_tables
                     WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='orders') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- สร้างบัญชีแอดมินแรก (รันแยก หลังรัน 01 แล้ว) — เปลี่ยน <รหัสผ่าน>
--   INSERT INTO accounts(username, pass_hash, role, display_name)
--   VALUES ('admin', crypt('<รหัสผ่าน>', gen_salt('bf')), 'admin', 'Admin');
-- ─────────────────────────────────────────────────────────────────────
