-- =====================================================
-- CUSTOMER PORTAL v2 — RubberLedger / KUBTHOR
-- เข้าสู่ระบบด้วย: ชื่อลูกค้า + เลขที่บิลล่าสุด (ครั้งแรก)
--                → บังคับตั้งรหัสผ่านใหม่ทันที
-- รันทั้งหมดใน Supabase → SQL Editor → Run
-- =====================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ══════════════════════════════════════
-- 0) ล้างของเดิม (ถ้าเคยรัน v1)
-- ══════════════════════════════════════
DROP FUNCTION IF EXISTS customer_register(TEXT,TEXT,TEXT,TEXT);
DROP FUNCTION IF EXISTS customer_login(TEXT,TEXT);
DROP FUNCTION IF EXISTS customer_profile(TEXT);
DROP FUNCTION IF EXISTS customer_orders(TEXT,DATE,DATE,TEXT);
DROP FUNCTION IF EXISTS customer_news(INT);
DROP FUNCTION IF EXISTS customer_change_pin(TEXT,TEXT,TEXT);
DROP FUNCTION IF EXISTS customer_logout(TEXT);
DROP FUNCTION IF EXISTS _cust_by_token(TEXT);
DROP FUNCTION IF EXISTS admin_list_customer_accounts();
DROP FUNCTION IF EXISTS admin_set_customer_active(TEXT,BOOLEAN);
DROP FUNCTION IF EXISTS admin_reset_customer_pin(TEXT,TEXT);
DROP FUNCTION IF EXISTS admin_delete_customer_account(TEXT);

-- ══════════════════════════════════════
-- 1) ตารางบัญชีลูกค้า
--    pass_hash = NULL → ยังไม่เคยตั้งรหัส (ใช้เลขบิลล่าสุดเข้า)
-- ══════════════════════════════════════
CREATE TABLE IF NOT EXISTS customer_accounts (
  id                   BIGSERIAL PRIMARY KEY,
  customer_name        TEXT UNIQUE NOT NULL,      -- = Username (ตรงกับ orders.customer)
  customer_code        TEXT UNIQUE,
  phone                TEXT,
  pass_hash            TEXT,                      -- bcrypt (NULL = ยังไม่ตั้ง)
  has_logged_in        BOOLEAN     DEFAULT false,
  must_change_password BOOLEAN     DEFAULT true,
  first_login_at       TIMESTAMPTZ,
  password_changed_at  TIMESTAMPTZ,
  last_login           TIMESTAMPTZ,
  is_active            BOOLEAN     DEFAULT true,
  failed_count         INT         DEFAULT 0,
  locked_until         TIMESTAMPTZ,
  created_at           TIMESTAMPTZ DEFAULT NOW()
);

-- เผื่อกรณีเคยรัน v1 มาก่อน
ALTER TABLE customer_accounts
  ADD COLUMN IF NOT EXISTS pass_hash            TEXT,
  ADD COLUMN IF NOT EXISTS has_logged_in        BOOLEAN     DEFAULT false,
  ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN     DEFAULT true,
  ADD COLUMN IF NOT EXISTS first_login_at       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS password_changed_at  TIMESTAMPTZ;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name='customer_accounts' AND column_name='pin_hash') THEN
    ALTER TABLE customer_accounts ALTER COLUMN pin_hash DROP NOT NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_cust_acc_name  ON customer_accounts(LOWER(TRIM(customer_name)));
CREATE INDEX IF NOT EXISTS idx_cust_acc_code  ON customer_accounts(customer_code);
CREATE INDEX IF NOT EXISTS idx_cust_acc_phone ON customer_accounts(phone);

-- ══════════════════════════════════════
-- 2) Session
-- ══════════════════════════════════════
CREATE TABLE IF NOT EXISTS customer_sessions (
  token       TEXT PRIMARY KEY,
  account_id  BIGINT REFERENCES customer_accounts(id) ON DELETE CASCADE,
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cust_sess_exp ON customer_sessions(expires_at);

-- ══════════════════════════════════════
-- 3) ข่าวสาร
-- ══════════════════════════════════════
CREATE TABLE IF NOT EXISTS news (
  id            BIGSERIAL PRIMARY KEY,
  title         TEXT NOT NULL,
  body          TEXT DEFAULT '',
  category      TEXT DEFAULT 'general',
  is_pinned     BOOLEAN DEFAULT false,
  is_published  BOOLEAN DEFAULT true,
  published_at  TIMESTAMPTZ DEFAULT NOW(),
  created_by    TEXT DEFAULT '',
  created_at    TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_news_pub ON news(is_published, published_at DESC);

-- ══════════════════════════════════════
-- 4) RLS
-- ══════════════════════════════════════
ALTER TABLE customer_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE news              ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT tablename, policyname FROM pg_policies
             WHERE schemaname='public' AND tablename IN ('customer_accounts','customer_sessions','news')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
  END LOOP;
END $$;

-- ลูกค้าห้ามแตะตารางบัญชีตรง (ต้องผ่าน RPC เท่านั้น)
REVOKE ALL ON public.customer_accounts FROM anon;
REVOKE ALL ON public.customer_sessions FROM anon;

CREATE POLICY "news_admin_all" ON public.news FOR ALL USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.news TO anon;

-- ══════════════════════════════════════
-- 5) HELPER
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION gen_customer_code()
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE code TEXT; ok BOOLEAN;
BEGIN
  LOOP
    code := 'CUS-' || LPAD((FLOOR(RANDOM()*900000)+100000)::TEXT, 6, '0');
    SELECT NOT EXISTS(SELECT 1 FROM customer_accounts WHERE customer_code = code) INTO ok;
    EXIT WHEN ok;
  END LOOP;
  RETURN code;
END $$;

-- เลขที่บิลล่าสุดของลูกค้า = รหัสผ่านเริ่มต้น
CREATE OR REPLACE FUNCTION _latest_po(p_name TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v TEXT;
BEGIN
  SELECT o.po_no INTO v
  FROM orders o
  WHERE LOWER(TRIM(o.customer)) = LOWER(TRIM(p_name))
    AND o.status <> 'cancelled'
    AND o.po_no IS NOT NULL AND LENGTH(TRIM(o.po_no)) > 0
  ORDER BY COALESCE(o.created_at, o.date::TIMESTAMPTZ) DESC
  LIMIT 1;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION _cust_by_token(p_token TEXT)
RETURNS customer_accounts
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE a customer_accounts%ROWTYPE;
BEGIN
  SELECT ca.* INTO a
  FROM customer_sessions s JOIN customer_accounts ca ON ca.id = s.account_id
  WHERE s.token = p_token AND s.expires_at > NOW() AND ca.is_active = true
  LIMIT 1;
  RETURN a;
END $$;

-- ══════════════════════════════════════
-- 6) RPC: ตรวจสอบชื่อผู้ใช้
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION customer_check_user(p_username TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_exists BOOLEAN;
  a customer_accounts%ROWTYPE;
BEGIN
  SELECT EXISTS(SELECT 1 FROM customers WHERE LOWER(TRIM(name)) = LOWER(TRIM(p_username))) INTO v_exists;
  IF NOT v_exists THEN
    RETURN json_build_object('ok', false, 'error', 'ไม่พบชื่อนี้ในระบบ กรุณาติดต่อจุดรับซื้อ');
  END IF;
  SELECT * INTO a FROM customer_accounts WHERE LOWER(TRIM(customer_name)) = LOWER(TRIM(p_username)) LIMIT 1;
  RETURN json_build_object(
    'ok', true,
    'first_time', (a.id IS NULL OR a.pass_hash IS NULL),
    'has_bills', (_latest_po(p_username) IS NOT NULL)
  );
END $$;

-- ══════════════════════════════════════
-- 7) RPC: เข้าสู่ระบบ
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION customer_login(
  p_username TEXT,
  p_password TEXT
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a        customer_accounts%ROWTYPE;
  c        customers%ROWTYPE;
  v_name   TEXT := TRIM(p_username);
  v_po     TEXT;
  v_token  TEXT;
  v_code   TEXT;
  v_ok     BOOLEAN := false;
  v_first  BOOLEAN := false;
BEGIN
  IF v_name IS NULL OR LENGTH(v_name) = 0 OR p_password IS NULL OR LENGTH(p_password) = 0 THEN
    RETURN json_build_object('ok', false, 'error', 'กรุณากรอกชื่อและรหัสผ่าน');
  END IF;

  -- หาบัญชี: ตามชื่อ / เบอร์โทร / รหัสลูกค้า
  SELECT * INTO a FROM customer_accounts
  WHERE LOWER(TRIM(customer_name)) = LOWER(v_name)
     OR phone = v_name
     OR UPPER(customer_code) = UPPER(v_name)
  LIMIT 1;

  IF a.id IS NOT NULL THEN
    v_name := a.customer_name;
  END IF;

  -- ต้องมีชื่อในตาราง customers (เคยขายยาง)
  SELECT * INTO c FROM customers WHERE LOWER(TRIM(name)) = LOWER(TRIM(v_name)) LIMIT 1;
  IF c.id IS NULL AND a.id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'ไม่พบชื่อนี้ในระบบ กรุณาติดต่อจุดรับซื้อ');
  END IF;

  -- ถูกล็อก / ระงับ
  IF a.id IS NOT NULL THEN
    IF a.locked_until IS NOT NULL AND a.locked_until > NOW() THEN
      RETURN json_build_object('ok', false, 'error', 'พยายามเข้าระบบผิดหลายครั้ง กรุณารอ 10 นาที');
    END IF;
    IF NOT a.is_active THEN
      RETURN json_build_object('ok', false, 'error', 'บัญชีของคุณถูกระงับ กรุณาติดต่อผู้ดูแลระบบ');
    END IF;
  END IF;

  -- ตรวจรหัสผ่าน
  IF a.id IS NULL OR a.pass_hash IS NULL THEN
    -- ครั้งแรก → ใช้เลขที่บิลล่าสุด
    v_po := _latest_po(v_name);
    IF v_po IS NULL THEN
      RETURN json_build_object('ok', false, 'error', 'ยังไม่มีประวัติการขาย กรุณาติดต่อจุดรับซื้อ');
    END IF;
    IF UPPER(TRIM(p_password)) = UPPER(TRIM(v_po)) THEN
      v_ok := true; v_first := true;
    END IF;
  ELSE
    IF a.pass_hash = crypt(p_password, a.pass_hash) THEN
      v_ok := true;
      v_first := COALESCE(a.must_change_password, false);
    END IF;
  END IF;

  -- ผิด → นับ + ล็อก
  IF NOT v_ok THEN
    IF a.id IS NOT NULL THEN
      UPDATE customer_accounts
        SET failed_count = COALESCE(failed_count,0) + 1,
            locked_until = CASE WHEN COALESCE(failed_count,0) + 1 >= 5
                                THEN NOW() + INTERVAL '10 minutes' ELSE NULL END
        WHERE id = a.id;
    END IF;
    RETURN json_build_object('ok', false, 'error', 'รหัสผ่านไม่ถูกต้อง');
  END IF;

  -- สำเร็จ → สร้างบัญชีถ้ายังไม่มี
  IF a.id IS NULL THEN
    v_code := gen_customer_code();
    INSERT INTO customer_accounts(customer_name, customer_code, phone, has_logged_in,
                                  must_change_password, first_login_at, last_login)
    VALUES (TRIM(v_name), v_code, NULLIF(TRIM(COALESCE(c.phone,'')),''), true, true, NOW(), NOW())
    RETURNING * INTO a;
  ELSE
    UPDATE customer_accounts
      SET failed_count = 0, locked_until = NULL, last_login = NOW(),
          has_logged_in = true,
          first_login_at = COALESCE(first_login_at, NOW()),
          customer_code = COALESCE(customer_code, gen_customer_code())
      WHERE id = a.id
      RETURNING * INTO a;
  END IF;

  v_token := encode(gen_random_bytes(32), 'hex');
  DELETE FROM customer_sessions WHERE expires_at < NOW();
  INSERT INTO customer_sessions(token, account_id, expires_at)
  VALUES (v_token, a.id, NOW() + INTERVAL '7 days');

  RETURN json_build_object(
    'ok', true,
    'token', v_token,
    'name', a.customer_name,
    'customer_code', a.customer_code,
    'phone', COALESCE(a.phone,''),
    'must_change_password', COALESCE(a.must_change_password, v_first)
  );
END $$;

-- ══════════════════════════════════════
-- 8) RPC: ตั้ง/เปลี่ยนรหัสผ่าน
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION customer_set_password(
  p_token TEXT,
  p_new   TEXT,
  p_old   TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE a customer_accounts%ROWTYPE;
BEGIN
  a := _cust_by_token(p_token);
  IF a.id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
  END IF;

  IF p_new IS NULL OR LENGTH(p_new) < 6 THEN
    RETURN json_build_object('ok', false, 'error', 'รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัว');
  END IF;

  -- ถ้าไม่ใช่การตั้งครั้งแรก → ต้องยืนยันรหัสเดิม
  IF NOT COALESCE(a.must_change_password,false) AND a.pass_hash IS NOT NULL THEN
    IF p_old IS NULL OR a.pass_hash <> crypt(p_old, a.pass_hash) THEN
      RETURN json_build_object('ok', false, 'error', 'รหัสผ่านเดิมไม่ถูกต้อง');
    END IF;
  END IF;

  UPDATE customer_accounts
    SET pass_hash = crypt(p_new, gen_salt('bf')),
        must_change_password = false,
        password_changed_at = NOW(),
        failed_count = 0, locked_until = NULL
    WHERE id = a.id;

  RETURN json_build_object('ok', true);
END $$;

-- ══════════════════════════════════════
-- 9) RPC: ข้อมูลบัญชี + สรุปยอด
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION customer_profile(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a customer_accounts%ROWTYPE;
  c customers%ROWTYPE;
  v_paid_cnt INT; v_paid_kg NUMERIC; v_paid_amt NUMERIC;
  v_pend_cnt INT; v_pend_amt NUMERIC;
  v_first DATE; v_last DATE;
BEGIN
  a := _cust_by_token(p_token);
  IF a.id IS NULL THEN RETURN json_build_object('ok', false, 'error', 'เซสชันหมดอายุ'); END IF;

  SELECT * INTO c FROM customers WHERE LOWER(TRIM(name)) = LOWER(TRIM(a.customer_name)) LIMIT 1;

  SELECT COUNT(*), COALESCE(SUM(total_qty),0), COALESCE(SUM(grand_total),0)
    INTO v_paid_cnt, v_paid_kg, v_paid_amt
    FROM orders WHERE LOWER(TRIM(customer)) = LOWER(TRIM(a.customer_name)) AND status='paid';

  SELECT COUNT(*), COALESCE(SUM(grand_total),0)
    INTO v_pend_cnt, v_pend_amt
    FROM orders WHERE LOWER(TRIM(customer)) = LOWER(TRIM(a.customer_name)) AND status='sent';

  SELECT MIN(date), MAX(date) INTO v_first, v_last
    FROM orders WHERE LOWER(TRIM(customer)) = LOWER(TRIM(a.customer_name)) AND status <> 'cancelled';

  RETURN json_build_object(
    'ok', true,
    'name', a.customer_name,
    'customer_code', a.customer_code,
    'phone', COALESCE(a.phone,''),
    'must_change_password', COALESCE(a.must_change_password,false),
    'first_login_at', a.first_login_at,
    'password_changed_at', a.password_changed_at,
    'address', json_build_object(
      'house', COALESCE(c.house,''), 'subdistrict', COALESCE(c.subdistrict,''),
      'district', COALESCE(c.district,''), 'province', COALESCE(c.province,'')
    ),
    'stats', json_build_object(
      'paid_count', v_paid_cnt, 'paid_kg', v_paid_kg, 'paid_amount', v_paid_amt,
      'pending_count', v_pend_cnt, 'pending_amount', v_pend_amt,
      'first_sale', v_first, 'last_sale', v_last
    )
  );
END $$;

-- ══════════════════════════════════════
-- 10) RPC: ประวัติการขาย
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION customer_orders(
  p_token  TEXT,
  p_from   DATE DEFAULT NULL,
  p_to     DATE DEFAULT NULL,
  p_status TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a customer_accounts%ROWTYPE;
  v_rows JSON;
BEGIN
  a := _cust_by_token(p_token);
  IF a.id IS NULL THEN RETURN json_build_object('ok', false, 'error', 'เซสชันหมดอายุ'); END IF;

  SELECT COALESCE(json_agg(x ORDER BY x.sort_key DESC), '[]'::json) INTO v_rows
  FROM (
    SELECT
      o.id, o.po_no, o.date, o.status,
      o.total_qty, o.grand_total, o.note,
      o.paid_at, o.created_at,
      COALESCE(o.paid_at::TEXT, o.date::TEXT) AS sort_key,
      (SELECT r.receipt_no FROM receipts r WHERE r.order_id = o.id LIMIT 1) AS receipt_no,
      (SELECT COALESCE(json_agg(json_build_object(
          'product', oi.product_id, 'qty', oi.qty, 'price', oi.price
        ) ORDER BY oi.sort_order), '[]'::json)
       FROM order_items oi WHERE oi.order_id = o.id) AS items
    FROM orders o
    WHERE LOWER(TRIM(o.customer)) = LOWER(TRIM(a.customer_name))
      AND o.status <> 'cancelled'
      AND (p_from IS NULL OR o.date >= p_from)
      AND (p_to   IS NULL OR o.date <= p_to)
      AND (p_status IS NULL OR p_status = '' OR o.status = p_status)
  ) x;

  RETURN json_build_object('ok', true, 'orders', v_rows);
END $$;

-- ══════════════════════════════════════
-- 11) RPC: ข่าวสาร
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION customer_news(p_limit INT DEFAULT 30)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rows JSON;
BEGIN
  SELECT COALESCE(json_agg(n ORDER BY n.is_pinned DESC, n.published_at DESC), '[]'::json) INTO v_rows
  FROM (
    SELECT id, title, body, category, is_pinned, published_at
    FROM news WHERE is_published = true
    ORDER BY is_pinned DESC, published_at DESC
    LIMIT p_limit
  ) n;
  RETURN json_build_object('ok', true, 'news', v_rows);
END $$;

-- ══════════════════════════════════════
-- 12) RPC: ออกจากระบบ
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION customer_logout(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM customer_sessions WHERE token = p_token;
  RETURN json_build_object('ok', true);
END $$;

-- ══════════════════════════════════════
-- 13) RPC สำหรับ ADMIN
--     ⚠ ไม่คืนรหัสผ่านจริง (เก็บเป็น hash เท่านั้น)
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION admin_list_customer_accounts()
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v JSON;
BEGIN
  SELECT COALESCE(json_agg(x ORDER BY x.customer_name), '[]'::json) INTO v
  FROM (
    SELECT ca.customer_name, ca.customer_code, ca.phone,
           ca.has_logged_in, ca.must_change_password,
           ca.first_login_at, ca.password_changed_at, ca.last_login,
           ca.is_active,
           (ca.pass_hash IS NOT NULL) AS has_password
    FROM customer_accounts ca
  ) x;
  RETURN json_build_object('ok', true, 'accounts', v);
END $$;

-- รายชื่อลูกค้าทั้งหมด + สถานะ + รหัสชั่วคราว (เลขบิลล่าสุด) สำหรับแจ้งลูกค้า
CREATE OR REPLACE FUNCTION admin_customer_login_info()
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v JSON;
BEGIN
  SELECT COALESCE(json_agg(x ORDER BY x.name), '[]'::json) INTO v
  FROM (
    SELECT c.name,
           c.phone,
           _latest_po(c.name)               AS temp_password,
           ca.customer_code,
           COALESCE(ca.has_logged_in,false) AS has_logged_in,
           (ca.pass_hash IS NOT NULL)       AS has_password,
           ca.first_login_at, ca.password_changed_at, ca.last_login,
           COALESCE(ca.is_active,true)      AS is_active
    FROM customers c
    LEFT JOIN customer_accounts ca ON LOWER(TRIM(ca.customer_name)) = LOWER(TRIM(c.name))
  ) x;
  RETURN json_build_object('ok', true, 'customers', v);
END $$;

CREATE OR REPLACE FUNCTION admin_set_customer_active(p_name TEXT, p_active BOOLEAN)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  UPDATE customer_accounts SET is_active = p_active
   WHERE LOWER(TRIM(customer_name)) = LOWER(TRIM(p_name)) OR customer_code = p_name;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN json_build_object('ok', false, 'error', 'ลูกค้ายังไม่เคยเข้าระบบ'); END IF;
  RETURN json_build_object('ok', true);
END $$;

-- รีเซ็ต → กลับไปใช้เลขบิลล่าสุด + บังคับตั้งรหัสใหม่
CREATE OR REPLACE FUNCTION admin_reset_customer_password(p_name TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT; v_po TEXT;
BEGIN
  v_po := _latest_po(p_name);
  UPDATE customer_accounts
    SET pass_hash = NULL, must_change_password = true,
        failed_count = 0, locked_until = NULL
   WHERE LOWER(TRIM(customer_name)) = LOWER(TRIM(p_name)) OR customer_code = p_name;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN json_build_object('ok', false, 'error', 'ลูกค้ายังไม่เคยเข้าระบบ'); END IF;
  RETURN json_build_object('ok', true, 'temp_password', v_po);
END $$;

CREATE OR REPLACE FUNCTION admin_delete_customer_account(p_name TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  DELETE FROM customer_accounts
   WHERE LOWER(TRIM(customer_name)) = LOWER(TRIM(p_name)) OR customer_code = p_name;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN json_build_object('ok', false, 'error', 'ไม่พบบัญชี'); END IF;
  RETURN json_build_object('ok', true);
END $$;

-- ══════════════════════════════════════
-- 14) สิทธิ์
-- ══════════════════════════════════════
GRANT EXECUTE ON FUNCTION customer_check_user(TEXT)               TO anon;
GRANT EXECUTE ON FUNCTION customer_login(TEXT,TEXT)               TO anon;
GRANT EXECUTE ON FUNCTION customer_set_password(TEXT,TEXT,TEXT)   TO anon;
GRANT EXECUTE ON FUNCTION customer_profile(TEXT)                  TO anon;
GRANT EXECUTE ON FUNCTION customer_orders(TEXT,DATE,DATE,TEXT)    TO anon;
GRANT EXECUTE ON FUNCTION customer_news(INT)                      TO anon;
GRANT EXECUTE ON FUNCTION customer_logout(TEXT)                   TO anon;
GRANT EXECUTE ON FUNCTION admin_list_customer_accounts()          TO anon;
GRANT EXECUTE ON FUNCTION admin_customer_login_info()             TO anon;
GRANT EXECUTE ON FUNCTION admin_set_customer_active(TEXT,BOOLEAN) TO anon;
GRANT EXECUTE ON FUNCTION admin_reset_customer_password(TEXT)     TO anon;
GRANT EXECUTE ON FUNCTION admin_delete_customer_account(TEXT)     TO anon;

REVOKE EXECUTE ON FUNCTION _cust_by_token(TEXT) FROM anon, public;
REVOKE EXECUTE ON FUNCTION _latest_po(TEXT)     FROM anon, public;

-- ══════════════════════════════════════
-- 15) ข่าวแนะนำวิธีเข้าระบบ
-- ══════════════════════════════════════
INSERT INTO news(title, body, category, is_pinned, created_by)
SELECT 'วิธีเข้าสู่ระบบครั้งแรก',
       E'1. ชื่อผู้ใช้ = ชื่อของท่านตามที่ลงทะเบียนไว้ที่จุดรับซื้อ\n2. รหัสผ่าน = เลขที่บิลการขายครั้งล่าสุดของท่าน\n3. เข้าสำเร็จแล้วระบบจะให้ตั้งรหัสผ่านใหม่ทันที\n\nหากมีข้อสงสัยกรุณาติดต่อจุดรับซื้อ',
       'general', true, 'system'
WHERE NOT EXISTS (SELECT 1 FROM news);

-- ══════════════════════════════════════
-- 16) ตรวจสอบผลลัพธ์
-- ══════════════════════════════════════
SELECT routine_name FROM information_schema.routines
WHERE routine_schema='public'
  AND (routine_name LIKE 'customer%' OR routine_name LIKE 'admin_%')
ORDER BY routine_name;

-- ดูข้อมูล login ของลูกค้าทุกคน (ชื่อผู้ใช้ + รหัสชั่วคราว)
SELECT * FROM json_to_recordset((admin_customer_login_info()->>'customers')::json)
AS x(name TEXT, phone TEXT, temp_password TEXT, has_logged_in BOOLEAN, has_password BOOLEAN);
