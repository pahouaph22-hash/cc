-- =====================================================
-- CUSTOMER PORTAL — RubberLedger / KUBTHOR
-- ระบบสมาชิกลูกค้า + ข่าวสาร (ปลอดภัยด้วย RPC SECURITY DEFINER)
-- รันทั้งหมดใน Supabase → SQL Editor → Run
-- =====================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ══════════════════════════════════════
-- 1) ตารางบัญชีลูกค้า (สำหรับ login)
-- ══════════════════════════════════════
CREATE TABLE IF NOT EXISTS customer_accounts (
  id             BIGSERIAL PRIMARY KEY,
  customer_name  TEXT NOT NULL,              -- ตรงกับ orders.customer
  customer_code  TEXT UNIQUE NOT NULL,       -- รหัสลูกค้า เช่น CUS-123456
  username       TEXT UNIQUE,                -- ชื่อบัญชี (ไม่บังคับ)
  phone          TEXT UNIQUE,                -- เบอร์โทร (ใช้ login ได้)
  pin_hash       TEXT NOT NULL,              -- PIN เข้ารหัส bcrypt
  is_active      BOOLEAN DEFAULT true,
  failed_count   INT DEFAULT 0,              -- กัน brute force
  locked_until   TIMESTAMPTZ,
  last_login     TIMESTAMPTZ,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cust_acc_phone ON customer_accounts(phone);
CREATE INDEX IF NOT EXISTS idx_cust_acc_code  ON customer_accounts(customer_code);
CREATE INDEX IF NOT EXISTS idx_cust_acc_user  ON customer_accounts(username);
CREATE INDEX IF NOT EXISTS idx_cust_acc_name  ON customer_accounts(customer_name);

-- ══════════════════════════════════════
-- 2) ตาราง session (token)
-- ══════════════════════════════════════
CREATE TABLE IF NOT EXISTS customer_sessions (
  token       TEXT PRIMARY KEY,
  account_id  BIGINT REFERENCES customer_accounts(id) ON DELETE CASCADE,
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cust_sess_exp ON customer_sessions(expires_at);

-- ══════════════════════════════════════
-- 3) ตารางข่าวสาร / ประกาศ
-- ══════════════════════════════════════
CREATE TABLE IF NOT EXISTS news (
  id            BIGSERIAL PRIMARY KEY,
  title         TEXT NOT NULL,
  body          TEXT DEFAULT '',
  category      TEXT DEFAULT 'general',   -- general | price | urgent
  is_pinned     BOOLEAN DEFAULT false,
  is_published  BOOLEAN DEFAULT true,
  published_at  TIMESTAMPTZ DEFAULT NOW(),
  created_by    TEXT DEFAULT '',
  created_at    TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_news_pub ON news(is_published, published_at DESC);

-- ══════════════════════════════════════
-- 4) RLS — ปิดการเข้าถึงตรงทั้งหมด (ให้ผ่าน RPC เท่านั้น)
-- ══════════════════════════════════════
ALTER TABLE customer_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE news              ENABLE ROW LEVEL SECURITY;

-- ลบ policy เดิม
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT tablename, policyname FROM pg_policies
             WHERE schemaname='public' AND tablename IN ('customer_accounts','customer_sessions','news')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
  END LOOP;
END $$;

-- customer_accounts / customer_sessions: ห้าม anon แตะตรง (ไม่มี policy = เข้าไม่ได้)
REVOKE ALL ON public.customer_accounts FROM anon;
REVOKE ALL ON public.customer_sessions FROM anon;

-- news: anon อ่านได้เฉพาะที่เผยแพร่ / แอดมินจัดการผ่านตารางตรง (ใช้ระบบพนักงาน)
CREATE POLICY "news_read_published" ON public.news
  FOR SELECT USING (is_published = true);
CREATE POLICY "news_admin_all" ON public.news
  FOR ALL USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.news TO anon;

-- ══════════════════════════════════════
-- 5) HELPER — สร้างรหัสลูกค้า
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

-- ══════════════════════════════════════
-- 6) RPC: สมัครสมาชิก
--    ต้องมีชื่อลูกค้าอยู่ในระบบแล้ว (เคยขายยาง) จึงสมัครได้
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION customer_register(
  p_name  TEXT,
  p_phone TEXT,
  p_pin   TEXT,
  p_username TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_exists  BOOLEAN;
  v_code    TEXT;
  v_id      BIGINT;
BEGIN
  IF p_name IS NULL OR LENGTH(TRIM(p_name)) = 0 THEN
    RETURN json_build_object('ok', false, 'error', 'กรุณากรอกชื่อ');
  END IF;
  IF p_pin IS NULL OR LENGTH(p_pin) < 4 THEN
    RETURN json_build_object('ok', false, 'error', 'PIN ต้องมีอย่างน้อย 4 หลัก');
  END IF;

  -- ต้องเป็นลูกค้าที่มีในระบบ (เคยขายยาง)
  SELECT EXISTS(SELECT 1 FROM customers WHERE LOWER(TRIM(name)) = LOWER(TRIM(p_name))) INTO v_exists;
  IF NOT v_exists THEN
    RETURN json_build_object('ok', false, 'error', 'ไม่พบชื่อนี้ในระบบ กรุณาติดต่อจุดรับซื้อเพื่อลงทะเบียนก่อน');
  END IF;

  -- สมัครซ้ำ?
  IF EXISTS(SELECT 1 FROM customer_accounts WHERE LOWER(TRIM(customer_name)) = LOWER(TRIM(p_name))) THEN
    RETURN json_build_object('ok', false, 'error', 'ชื่อนี้สมัครแล้ว กรุณาเข้าสู่ระบบ');
  END IF;
  IF p_phone IS NOT NULL AND LENGTH(TRIM(p_phone))>0
     AND EXISTS(SELECT 1 FROM customer_accounts WHERE phone = TRIM(p_phone)) THEN
    RETURN json_build_object('ok', false, 'error', 'เบอร์โทรนี้ถูกใช้แล้ว');
  END IF;
  IF p_username IS NOT NULL AND LENGTH(TRIM(p_username))>0
     AND EXISTS(SELECT 1 FROM customer_accounts WHERE username = TRIM(p_username)) THEN
    RETURN json_build_object('ok', false, 'error', 'ชื่อบัญชีนี้ถูกใช้แล้ว');
  END IF;

  v_code := gen_customer_code();
  INSERT INTO customer_accounts(customer_name, customer_code, username, phone, pin_hash)
  VALUES (TRIM(p_name), v_code,
          NULLIF(TRIM(COALESCE(p_username,'')),''),
          NULLIF(TRIM(COALESCE(p_phone,'')),''),
          crypt(p_pin, gen_salt('bf')))
  RETURNING id INTO v_id;

  RETURN json_build_object('ok', true, 'customer_code', v_code, 'name', TRIM(p_name));
END $$;

-- ══════════════════════════════════════
-- 7) RPC: เข้าสู่ระบบ (เบอร์โทร / รหัสลูกค้า / ชื่อบัญชี)
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION customer_login(
  p_identifier TEXT,
  p_pin        TEXT
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a         customer_accounts%ROWTYPE;
  v_token   TEXT;
  v_ident   TEXT := TRIM(p_identifier);
BEGIN
  SELECT * INTO a FROM customer_accounts
  WHERE phone = v_ident
     OR UPPER(customer_code) = UPPER(v_ident)
     OR LOWER(username) = LOWER(v_ident)
     OR LOWER(TRIM(customer_name)) = LOWER(v_ident)
  LIMIT 1;

  IF a.id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'ไม่พบบัญชีนี้');
  END IF;

  -- ถูกล็อกชั่วคราว?
  IF a.locked_until IS NOT NULL AND a.locked_until > NOW() THEN
    RETURN json_build_object('ok', false, 'error', 'พยายามเข้าระบบผิดหลายครั้ง กรุณารอสักครู่');
  END IF;

  IF NOT a.is_active THEN
    RETURN json_build_object('ok', false, 'error', 'บัญชีของคุณถูกระงับ กรุณาติดต่อผู้ดูแลระบบ');
  END IF;

  -- ตรวจ PIN
  IF a.pin_hash <> crypt(p_pin, a.pin_hash) THEN
    UPDATE customer_accounts
      SET failed_count = failed_count + 1,
          locked_until = CASE WHEN failed_count + 1 >= 5 THEN NOW() + INTERVAL '10 minutes' ELSE NULL END
      WHERE id = a.id;
    RETURN json_build_object('ok', false, 'error', 'PIN ไม่ถูกต้อง');
  END IF;

  -- สำเร็จ → รีเซ็ตตัวนับ + ออก token
  v_token := encode(gen_random_bytes(32), 'hex');
  UPDATE customer_accounts
    SET failed_count = 0, locked_until = NULL, last_login = NOW()
    WHERE id = a.id;

  DELETE FROM customer_sessions WHERE expires_at < NOW();
  INSERT INTO customer_sessions(token, account_id, expires_at)
  VALUES (v_token, a.id, NOW() + INTERVAL '7 days');

  RETURN json_build_object(
    'ok', true,
    'token', v_token,
    'name', a.customer_name,
    'customer_code', a.customer_code,
    'phone', COALESCE(a.phone,''),
    'username', COALESCE(a.username,'')
  );
END $$;

-- ══════════════════════════════════════
-- 8) HELPER: ตรวจ token → คืน account
-- ══════════════════════════════════════
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
  IF a.id IS NULL THEN RETURN json_build_object('ok', false, 'error', 'session หมดอายุ'); END IF;

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
    'username', COALESCE(a.username,''),
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
-- 10) RPC: ประวัติการขาย (เฉพาะของตัวเอง)
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION customer_orders(
  p_token TEXT,
  p_from  DATE DEFAULT NULL,
  p_to    DATE DEFAULT NULL,
  p_status TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a customer_accounts%ROWTYPE;
  v_rows JSON;
BEGIN
  a := _cust_by_token(p_token);
  IF a.id IS NULL THEN RETURN json_build_object('ok', false, 'error', 'session หมดอายุ'); END IF;

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
-- 11) RPC: ข่าวสาร (เปิดสาธารณะ)
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
-- 12) RPC: เปลี่ยน PIN / ออกจากระบบ
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION customer_change_pin(p_token TEXT, p_old TEXT, p_new TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE a customer_accounts%ROWTYPE;
BEGIN
  a := _cust_by_token(p_token);
  IF a.id IS NULL THEN RETURN json_build_object('ok', false, 'error', 'session หมดอายุ'); END IF;
  IF a.pin_hash <> crypt(p_old, a.pin_hash) THEN
    RETURN json_build_object('ok', false, 'error', 'PIN เดิมไม่ถูกต้อง');
  END IF;
  IF LENGTH(p_new) < 4 THEN
    RETURN json_build_object('ok', false, 'error', 'PIN ใหม่ต้องมีอย่างน้อย 4 หลัก');
  END IF;
  UPDATE customer_accounts SET pin_hash = crypt(p_new, gen_salt('bf')) WHERE id = a.id;
  RETURN json_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION customer_logout(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM customer_sessions WHERE token = p_token;
  RETURN json_build_object('ok', true);
END $$;

-- ══════════════════════════════════════
-- 13) RPC สำหรับ ADMIN (ระบบพนักงาน)
-- ══════════════════════════════════════
CREATE OR REPLACE FUNCTION admin_list_customer_accounts()
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v JSON;
BEGIN
  SELECT COALESCE(json_agg(x ORDER BY x.created_at DESC), '[]'::json) INTO v
  FROM (SELECT id, customer_name, customer_code, username, phone, is_active, last_login, created_at
        FROM customer_accounts) x;
  RETURN json_build_object('ok', true, 'accounts', v);
END $$;

CREATE OR REPLACE FUNCTION admin_set_customer_active(p_code TEXT, p_active BOOLEAN)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  UPDATE customer_accounts SET is_active = p_active WHERE customer_code = p_code;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN json_build_object('ok', false, 'error', 'ไม่พบบัญชี'); END IF;
  RETURN json_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION admin_reset_customer_pin(p_code TEXT, p_new_pin TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  IF LENGTH(p_new_pin) < 4 THEN RETURN json_build_object('ok', false, 'error', 'PIN ต้องมีอย่างน้อย 4 หลัก'); END IF;
  UPDATE customer_accounts SET pin_hash = crypt(p_new_pin, gen_salt('bf')), failed_count=0, locked_until=NULL
   WHERE customer_code = p_code;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN json_build_object('ok', false, 'error', 'ไม่พบบัญชี'); END IF;
  RETURN json_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION admin_delete_customer_account(p_code TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  DELETE FROM customer_accounts WHERE customer_code = p_code;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN json_build_object('ok', false, 'error', 'ไม่พบบัญชี'); END IF;
  RETURN json_build_object('ok', true);
END $$;

-- ══════════════════════════════════════
-- 14) สิทธิ์เรียก RPC
-- ══════════════════════════════════════
GRANT EXECUTE ON FUNCTION customer_register(TEXT,TEXT,TEXT,TEXT)  TO anon;
GRANT EXECUTE ON FUNCTION customer_login(TEXT,TEXT)               TO anon;
GRANT EXECUTE ON FUNCTION customer_profile(TEXT)                  TO anon;
GRANT EXECUTE ON FUNCTION customer_orders(TEXT,DATE,DATE,TEXT)    TO anon;
GRANT EXECUTE ON FUNCTION customer_news(INT)                      TO anon;
GRANT EXECUTE ON FUNCTION customer_change_pin(TEXT,TEXT,TEXT)     TO anon;
GRANT EXECUTE ON FUNCTION customer_logout(TEXT)                   TO anon;
GRANT EXECUTE ON FUNCTION admin_list_customer_accounts()          TO anon;
GRANT EXECUTE ON FUNCTION admin_set_customer_active(TEXT,BOOLEAN) TO anon;
GRANT EXECUTE ON FUNCTION admin_reset_customer_pin(TEXT,TEXT)     TO anon;
GRANT EXECUTE ON FUNCTION admin_delete_customer_account(TEXT)     TO anon;

-- ไม่ให้เรียก helper ภายในโดยตรง
REVOKE EXECUTE ON FUNCTION _cust_by_token(TEXT) FROM anon, public;

-- ══════════════════════════════════════
-- 15) ข่าวตัวอย่าง
-- ══════════════════════════════════════
INSERT INTO news(title, body, category, is_pinned, created_by)
SELECT 'ยินดีต้อนรับสู่ระบบสมาชิก KUBTHOR',
       'ท่านสามารถตรวจสอบประวัติการขายยางพารา ยอดเงิน และใบเสร็จของท่านได้ที่นี่ตลอด 24 ชั่วโมง หากมีข้อสงสัยกรุณาติดต่อจุดรับซื้อ',
       'general', true, 'system'
WHERE NOT EXISTS (SELECT 1 FROM news);

-- ══════════════════════════════════════
-- 16) ตรวจสอบผลลัพธ์
-- ══════════════════════════════════════
SELECT 'customer_accounts' AS tbl, COUNT(*) FROM customer_accounts
UNION ALL SELECT 'customer_sessions', COUNT(*) FROM customer_sessions
UNION ALL SELECT 'news', COUNT(*) FROM news;

SELECT routine_name FROM information_schema.routines
WHERE routine_schema='public' AND routine_name LIKE 'customer%' OR routine_name LIKE 'admin_%'
ORDER BY routine_name;
