-- =====================================================================
-- RubberLedger — ติดตั้งส่วนที่เหลือบนโปรเจกต์ใหม่ (kgiyiflrwgiflpqglqky)
-- รันหลัง 00-base-schema.sql (ตารางหลักสร้างแล้ว)
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run   (รันซ้ำได้)
-- =====================================================================

-- ───────────── ส่วนที่ 1: พอร์ทัลลูกค้า ─────────────
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS customer_accounts (
  id                   BIGSERIAL PRIMARY KEY,
  customer_name        TEXT UNIQUE NOT NULL,
  customer_code        TEXT UNIQUE,
  phone                TEXT,
  pass_hash            TEXT,
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

CREATE TABLE IF NOT EXISTS customer_sessions (
  token       TEXT PRIMARY KEY,
  account_id  BIGINT REFERENCES customer_accounts(id) ON DELETE CASCADE,
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cust_sess_exp ON customer_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_cust_sess_account ON customer_sessions(account_id);

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

ALTER TABLE customer_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE news              ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.customer_accounts FROM anon, authenticated;
REVOKE ALL ON public.customer_sessions FROM anon, authenticated;
REVOKE ALL ON public.news FROM anon, authenticated;

CREATE OR REPLACE FUNCTION gen_customer_code()
RETURNS TEXT LANGUAGE plpgsql SET search_path = public AS $$
DECLARE code TEXT; ok BOOLEAN;
BEGIN
  LOOP
    code := 'CUS-' || LPAD((FLOOR(RANDOM()*900000)+100000)::TEXT, 6, '0');
    SELECT NOT EXISTS(SELECT 1 FROM customer_accounts WHERE customer_code = code) INTO ok;
    EXIT WHEN ok;
  END LOOP;
  RETURN code;
END $$;

CREATE OR REPLACE FUNCTION _latest_po(p_name TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
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
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE a customer_accounts%ROWTYPE;
BEGIN
  SELECT ca.* INTO a
  FROM customer_sessions s JOIN customer_accounts ca ON ca.id = s.account_id
  WHERE s.token = p_token AND s.expires_at > NOW() AND ca.is_active = true
  LIMIT 1;
  RETURN a;
END $$;

CREATE OR REPLACE FUNCTION customer_check_user(p_username TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
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

CREATE OR REPLACE FUNCTION customer_login(
  p_username TEXT,
  p_password TEXT
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
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


  SELECT * INTO a FROM customer_accounts
  WHERE LOWER(TRIM(customer_name)) = LOWER(v_name)
     OR phone = v_name
     OR UPPER(customer_code) = UPPER(v_name)
  LIMIT 1;

  IF a.id IS NOT NULL THEN
    v_name := a.customer_name;
  END IF;


  SELECT * INTO c FROM customers WHERE LOWER(TRIM(name)) = LOWER(TRIM(v_name)) LIMIT 1;
  IF c.id IS NULL AND a.id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'ไม่พบชื่อนี้ในระบบ กรุณาติดต่อจุดรับซื้อ');
  END IF;


  IF a.id IS NOT NULL THEN
    IF a.locked_until IS NOT NULL AND a.locked_until > NOW() THEN
      RETURN json_build_object('ok', false, 'error', 'พยายามเข้าระบบผิดหลายครั้ง กรุณารอ 10 นาที');
    END IF;
    IF NOT a.is_active THEN
      RETURN json_build_object('ok', false, 'error', 'บัญชีของคุณถูกระงับ กรุณาติดต่อผู้ดูแลระบบ');
    END IF;
  END IF;


  IF a.id IS NULL OR a.pass_hash IS NULL THEN

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

CREATE OR REPLACE FUNCTION customer_set_password(
  p_token TEXT,
  p_new   TEXT,
  p_old   TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE a customer_accounts%ROWTYPE;
BEGIN
  a := _cust_by_token(p_token);
  IF a.id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
  END IF;

  IF p_new IS NULL OR LENGTH(p_new) < 6 THEN
    RETURN json_build_object('ok', false, 'error', 'รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัว');
  END IF;


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

CREATE OR REPLACE FUNCTION customer_profile(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
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

CREATE OR REPLACE FUNCTION customer_orders(
  p_token  TEXT,
  p_from   DATE DEFAULT NULL,
  p_to     DATE DEFAULT NULL,
  p_status TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
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

CREATE OR REPLACE FUNCTION customer_news(p_limit INT DEFAULT 30)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_rows JSON;
BEGIN
  SELECT COALESCE(json_agg(n ORDER BY n.is_pinned DESC, n.published_at DESC), '[]'::json) INTO v_rows
  FROM (
    SELECT id, title, body, category, is_pinned, published_at
    FROM news WHERE is_published = true
    ORDER BY is_pinned DESC, published_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit,30),1),100)
  ) n;
  RETURN json_build_object('ok', true, 'news', v_rows);
END $$;

CREATE OR REPLACE FUNCTION customer_logout(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  DELETE FROM customer_sessions WHERE token = p_token;
  RETURN json_build_object('ok', true);
END $$;

GRANT EXECUTE ON FUNCTION customer_check_user(TEXT)               TO anon;
GRANT EXECUTE ON FUNCTION customer_login(TEXT,TEXT)               TO anon;
GRANT EXECUTE ON FUNCTION customer_set_password(TEXT,TEXT,TEXT)   TO anon;
GRANT EXECUTE ON FUNCTION customer_profile(TEXT)                  TO anon;
GRANT EXECUTE ON FUNCTION customer_orders(TEXT,DATE,DATE,TEXT)    TO anon;
GRANT EXECUTE ON FUNCTION customer_news(INT)                      TO anon;
GRANT EXECUTE ON FUNCTION customer_logout(TEXT)                   TO anon;

REVOKE EXECUTE ON FUNCTION _cust_by_token(TEXT) FROM anon, public;
REVOKE EXECUTE ON FUNCTION _latest_po(TEXT)     FROM anon, public;

INSERT INTO news(title, body, category, is_pinned, created_by)
SELECT 'วิธีเข้าสู่ระบบครั้งแรก',
       E'1. ชื่อผู้ใช้ = ชื่อของท่านตามที่ลงทะเบียนไว้ที่จุดรับซื้อ\n2. รหัสผ่าน = เลขที่บิลการขายครั้งล่าสุดของท่าน\n3. เข้าสำเร็จแล้วระบบจะให้ตั้งรหัสผ่านใหม่ทันที\n\nหากมีข้อสงสัยกรุณาติดต่อจุดรับซื้อ',
       'general', true, 'system'
WHERE NOT EXISTS (SELECT 1 FROM news);

-- ───────────── ส่วนที่ 2: ความปลอดภัยบัญชีพนักงาน ─────────────
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS pass_hash      TEXT,
  ADD COLUMN IF NOT EXISTS is_active      BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deactivated_by TEXT,
  ADD COLUMN IF NOT EXISTS failed_count   INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS locked_until   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_login     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS loc_village    TEXT,
  ADD COLUMN IF NOT EXISTS loc_district   TEXT,
  ADD COLUMN IF NOT EXISTS loc_city       TEXT,
  ADD COLUMN IF NOT EXISTS loc_province   TEXT;

UPDATE public.accounts
   SET pass_hash = crypt(password, gen_salt('bf'))
 WHERE pass_hash IS NULL AND password IS NOT NULL AND password <> '';

ALTER TABLE public.accounts ALTER COLUMN password DROP NOT NULL;
UPDATE public.accounts SET password = NULL WHERE pass_hash IS NOT NULL;

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='accounts' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.accounts', pol.policyname);
  END LOOP;
END $$;
REVOKE ALL ON public.accounts FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.staff_sessions (
  token       TEXT PRIMARY KEY DEFAULT encode(gen_random_bytes(32), 'hex'),
  username    TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL DEFAULT now() + interval '14 days'
);
CREATE INDEX IF NOT EXISTS idx_staff_sess_user ON public.staff_sessions(username);
CREATE INDEX IF NOT EXISTS idx_staff_sess_exp  ON public.staff_sessions(expires_at);
ALTER TABLE public.staff_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.staff_sessions FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public._staff_public(a public.accounts)
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT (to_jsonb(a) - 'password' - 'pass_hash' - 'failed_count' - 'locked_until')
         || jsonb_build_object('has_password', a.pass_hash IS NOT NULL)
$$;

CREATE OR REPLACE FUNCTION public._staff_by_token(p_token TEXT)
RETURNS public.accounts
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE a public.accounts%ROWTYPE;
BEGIN
  IF p_token IS NULL OR p_token = '' THEN RETURN NULL; END IF;
  SELECT acc.* INTO a
    FROM public.staff_sessions s
    JOIN public.accounts acc ON acc.username = s.username
   WHERE s.token = p_token AND s.expires_at > now()
     AND COALESCE(acc.is_active, true)
   LIMIT 1;
  RETURN a;
END $$;

CREATE OR REPLACE FUNCTION public._require_staff(p_token TEXT)
RETURNS public.accounts
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE a public.accounts%ROWTYPE;
BEGIN
  a := public._staff_by_token(p_token);
  IF a.username IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;
  RETURN a;
END $$;

CREATE OR REPLACE FUNCTION public._require_admin(p_token TEXT)
RETURNS public.accounts
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE a public.accounts%ROWTYPE;
BEGIN
  a := public._require_staff(p_token);
  IF a.role <> 'admin' THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;
  RETURN a;
END $$;

CREATE OR REPLACE FUNCTION public.request_staff_ok()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT (public._staff_by_token(
            COALESCE(current_setting('request.headers', true)::json ->> 'x-staff-token', '')
          )).username IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.staff_login(p_username TEXT, p_password TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE a public.accounts%ROWTYPE; v_tok TEXT;
BEGIN
  SELECT * INTO a FROM public.accounts WHERE username = TRIM(p_username) LIMIT 1;
  IF a.username IS NULL THEN
    PERFORM pg_sleep(0.4);
    RETURN json_build_object('ok', false, 'error', 'invalid');
  END IF;
  IF a.locked_until IS NOT NULL AND a.locked_until > now() THEN
    RETURN json_build_object('ok', false, 'error', 'locked',
                             'retry_after', ceil(extract(epoch FROM a.locked_until - now())));
  END IF;
  IF a.pass_hash IS NULL OR a.pass_hash <> crypt(p_password, a.pass_hash) THEN
    UPDATE public.accounts
       SET failed_count = COALESCE(failed_count,0) + 1,
           locked_until = CASE WHEN COALESCE(failed_count,0) + 1 >= 5
                               THEN now() + interval '5 minutes' END
     WHERE username = a.username;
    RETURN json_build_object('ok', false, 'error', 'invalid');
  END IF;
  IF NOT COALESCE(a.is_active, true) THEN
    RETURN json_build_object('ok', false, 'error', 'inactive');
  END IF;
  UPDATE public.accounts SET failed_count = 0, locked_until = NULL, last_login = now()
   WHERE username = a.username;
  DELETE FROM public.staff_sessions WHERE expires_at < now();
  INSERT INTO public.staff_sessions(username) VALUES (a.username) RETURNING token INTO v_tok;
  RETURN json_build_object('ok', true, 'token', v_tok, 'user', public._staff_public(a));
END $$;

CREATE OR REPLACE FUNCTION public.staff_session(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE a public.accounts%ROWTYPE;
BEGIN
  a := public._staff_by_token(p_token);
  IF a.username IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'expired');
  END IF;
  RETURN json_build_object('ok', true, 'user', public._staff_public(a));
END $$;

CREATE OR REPLACE FUNCTION public.staff_logout(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  DELETE FROM public.staff_sessions WHERE token = p_token;
  RETURN json_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.staff_change_password(p_token TEXT, p_old TEXT, p_new TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE a public.accounts%ROWTYPE;
BEGIN
  a := public._require_staff(p_token);
  IF a.pass_hash IS NULL OR a.pass_hash <> crypt(p_old, a.pass_hash) THEN
    RETURN json_build_object('ok', false, 'error', 'wrong_old_password');
  END IF;
  IF length(COALESCE(p_new,'')) < 6 THEN
    RETURN json_build_object('ok', false, 'error', 'too_short');
  END IF;
  UPDATE public.accounts SET pass_hash = crypt(p_new, gen_salt('bf')), password = NULL
   WHERE username = a.username;
  -- ออกจากระบบเครื่องอื่นทั้งหมด ยกเว้นเครื่องนี้
  DELETE FROM public.staff_sessions WHERE username = a.username AND token <> p_token;
  RETURN json_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.staff_save_location(
  p_token TEXT, p_village TEXT, p_district TEXT, p_city TEXT, p_province TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE a public.accounts%ROWTYPE;
BEGIN
  a := public._require_staff(p_token);
  UPDATE public.accounts
     SET loc_village = p_village, loc_district = p_district,
         loc_city = p_city, loc_province = p_province
   WHERE username = a.username;
  RETURN json_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.admin_staff_list(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v JSONB;
BEGIN
  PERFORM public._require_admin(p_token);
  SELECT COALESCE(jsonb_agg(public._staff_public(a) ORDER BY a.username), '[]'::jsonb)
    INTO v FROM public.accounts a;
  RETURN json_build_object('ok', true, 'accounts', v);
END $$;

CREATE OR REPLACE FUNCTION public.admin_staff_add(
  p_token TEXT, p_username TEXT, p_password TEXT, p_role TEXT, p_display_name TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public._require_admin(p_token);
  IF COALESCE(TRIM(p_username),'') = '' OR length(COALESCE(p_password,'')) < 6 THEN
    RETURN json_build_object('ok', false, 'error', 'invalid_input');
  END IF;
  IF p_role NOT IN ('staff_biller','staff_cashier','staff') THEN
    RETURN json_build_object('ok', false, 'error', 'invalid_role');
  END IF;
  IF EXISTS (SELECT 1 FROM public.accounts WHERE username = TRIM(p_username)) THEN
    RETURN json_build_object('ok', false, 'error', 'username_taken');
  END IF;
  INSERT INTO public.accounts(username, pass_hash, role, display_name, is_active)
  VALUES (TRIM(p_username), crypt(p_password, gen_salt('bf')), p_role,
          COALESCE(NULLIF(TRIM(p_display_name),''), TRIM(p_username)), true);
  RETURN json_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.admin_staff_set_active(p_token TEXT, p_username TEXT, p_active BOOLEAN)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE me public.accounts%ROWTYPE; n INT;
BEGIN
  me := public._require_admin(p_token);
  IF p_username = me.username THEN
    RETURN json_build_object('ok', false, 'error', 'cannot_change_self');
  END IF;
  UPDATE public.accounts
     SET is_active = p_active,
         deactivated_at = CASE WHEN p_active THEN NULL ELSE now() END,
         deactivated_by = CASE WHEN p_active THEN NULL ELSE me.username END
   WHERE username = p_username AND role <> 'admin';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN json_build_object('ok', false, 'error', 'not_found'); END IF;
  IF NOT p_active THEN DELETE FROM public.staff_sessions WHERE username = p_username; END IF;
  RETURN json_build_object('ok', true, 'is_active', p_active);
END $$;

CREATE OR REPLACE FUNCTION public.admin_staff_set_password(p_token TEXT, p_username TEXT, p_new TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE n INT;
BEGIN
  PERFORM public._require_admin(p_token);
  IF length(COALESCE(p_new,'')) < 6 THEN
    RETURN json_build_object('ok', false, 'error', 'too_short');
  END IF;
  UPDATE public.accounts
     SET pass_hash = crypt(p_new, gen_salt('bf')), password = NULL,
         failed_count = 0, locked_until = NULL
   WHERE username = p_username;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN json_build_object('ok', false, 'error', 'not_found'); END IF;
  DELETE FROM public.staff_sessions WHERE username = p_username AND token <> p_token;
  RETURN json_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.admin_staff_delete(p_token TEXT, p_username TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE n INT;
BEGIN
  PERFORM public._require_admin(p_token);
  DELETE FROM public.accounts WHERE username = p_username AND role <> 'admin';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN json_build_object('ok', false, 'error', 'not_found'); END IF;
  DELETE FROM public.staff_sessions WHERE username = p_username;
  RETURN json_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.admin_customer_login_info(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v JSON;
BEGIN
  PERFORM public._require_admin(p_token);
  SELECT COALESCE(json_agg(x ORDER BY x.name), '[]'::json) INTO v
  FROM (
    SELECT c.name, c.phone,
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

CREATE OR REPLACE FUNCTION public.admin_set_customer_active(p_token TEXT, p_name TEXT, p_active BOOLEAN)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE n INT;
BEGIN
  PERFORM public._require_admin(p_token);
  UPDATE customer_accounts SET is_active = p_active
   WHERE LOWER(TRIM(customer_name)) = LOWER(TRIM(p_name)) OR customer_code = p_name;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN json_build_object('ok', false, 'error', 'ลูกค้ายังไม่เคยเข้าระบบ'); END IF;
  IF NOT p_active THEN
    DELETE FROM customer_sessions WHERE account_id IN (
      SELECT id FROM customer_accounts
       WHERE LOWER(TRIM(customer_name)) = LOWER(TRIM(p_name)) OR customer_code = p_name);
  END IF;
  RETURN json_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.admin_reset_customer_password(p_token TEXT, p_name TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE n INT; v_po TEXT;
BEGIN
  PERFORM public._require_admin(p_token);
  v_po := _latest_po(p_name);
  UPDATE customer_accounts
     SET pass_hash = NULL, must_change_password = true,
         failed_count = 0, locked_until = NULL
   WHERE LOWER(TRIM(customer_name)) = LOWER(TRIM(p_name)) OR customer_code = p_name;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN json_build_object('ok', false, 'error', 'ลูกค้ายังไม่เคยเข้าระบบ'); END IF;
  RETURN json_build_object('ok', true, 'temp_password', v_po);
END $$;

CREATE OR REPLACE FUNCTION public.admin_delete_customer_account(p_token TEXT, p_name TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE n INT;
BEGIN
  PERFORM public._require_admin(p_token);
  DELETE FROM customer_accounts
   WHERE LOWER(TRIM(customer_name)) = LOWER(TRIM(p_name)) OR customer_code = p_name;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN json_build_object('ok', false, 'error', 'ไม่พบบัญชี'); END IF;
  RETURN json_build_object('ok', true);
END $$;

ALTER TABLE public.news ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.news FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_news_list(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v JSON;
BEGIN
  PERFORM public._require_admin(p_token);
  SELECT COALESCE(json_agg(n ORDER BY n.is_pinned DESC, n.published_at DESC), '[]'::json)
    INTO v FROM public.news n;
  RETURN json_build_object('ok', true, 'news', v);
END $$;

CREATE OR REPLACE FUNCTION public.admin_news_save(
  p_token TEXT, p_id BIGINT, p_title TEXT, p_body TEXT, p_category TEXT,
  p_pinned BOOLEAN, p_published BOOLEAN)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE me public.accounts%ROWTYPE; v_id BIGINT;
BEGIN
  me := public._require_admin(p_token);
  IF COALESCE(TRIM(p_title),'') = '' THEN
    RETURN json_build_object('ok', false, 'error', 'title_required');
  END IF;
  IF p_id IS NULL THEN
    INSERT INTO public.news(title, body, category, is_pinned, is_published, published_at, created_by)
    VALUES (TRIM(p_title), COALESCE(p_body,''), COALESCE(p_category,'general'),
            COALESCE(p_pinned,false), COALESCE(p_published,true), now(), me.display_name)
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.news
       SET title = TRIM(p_title), body = COALESCE(p_body,''),
           category = COALESCE(p_category,'general'),
           is_pinned = COALESCE(p_pinned,false), is_published = COALESCE(p_published,true)
     WHERE id = p_id
     RETURNING id INTO v_id;
    IF v_id IS NULL THEN RETURN json_build_object('ok', false, 'error', 'not_found'); END IF;
  END IF;
  RETURN json_build_object('ok', true, 'id', v_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_news_delete(p_token TEXT, p_id BIGINT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public._require_admin(p_token);
  DELETE FROM public.news WHERE id = p_id;
  RETURN json_build_object('ok', true);
END $$;

CREATE TABLE IF NOT EXISTS public.doc_counters (
  key TEXT PRIMARY KEY,
  n   INT  NOT NULL
);
ALTER TABLE public.doc_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.doc_counters FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.next_receipt_no(p_token TEXT)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE k TEXT; v_base INT; v_n INT;
BEGIN
  PERFORM public._require_staff(p_token);
  k := 'RC-' || to_char(now() AT TIME ZONE 'Asia/Vientiane', 'YYMM');
  -- นับเฉพาะเลขปกติ RC-YYMM#### (ไม่นับเลขชั่วคราวตอนออฟไลน์ RC-YYMM-T...)
  SELECT COALESCE(MAX(substr(receipt_no, length(k) + 1)::INT), 0)
    INTO v_base FROM public.receipts WHERE receipt_no ~ ('^' || k || '[0-9]{1,9}$');
  INSERT INTO public.doc_counters(key, n) VALUES (k, v_base + 1)
  ON CONFLICT (key) DO UPDATE SET n = GREATEST(public.doc_counters.n, v_base) + 1
  RETURNING n INTO v_n;
  RETURN k || lpad(v_n::TEXT, 4, '0');
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'receipts_receipt_no_key') THEN
    IF EXISTS (SELECT 1 FROM public.receipts GROUP BY receipt_no HAVING count(*) > 1) THEN
      RAISE NOTICE '⚠ receipts มีเลขใบเสร็จซ้ำ — ยังไม่ได้สร้าง UNIQUE (ดูคำสั่งตรวจท้ายไฟล์)';
    ELSE
      ALTER TABLE public.receipts ADD CONSTRAINT receipts_receipt_no_key UNIQUE (receipt_no);
    END IF;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_po_no_key') THEN
    IF EXISTS (SELECT 1 FROM public.orders GROUP BY po_no HAVING count(*) > 1) THEN
      RAISE NOTICE '⚠ orders มีเลข PO ซ้ำ — ยังไม่ได้สร้าง UNIQUE (ดูคำสั่งตรวจท้ายไฟล์)';
    ELSE
      ALTER TABLE public.orders ADD CONSTRAINT orders_po_no_key UNIQUE (po_no);
    END IF;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_orders_updated_at ON public.orders(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON public.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_receipts_issued_at ON public.receipts(issued_at DESC);
CREATE INDEX IF NOT EXISTS idx_receipts_order ON public.receipts(order_id);

REVOKE EXECUTE ON FUNCTION public._staff_by_token(TEXT)  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._require_staff(TEXT)   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._require_admin(TEXT)   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._staff_public(public.accounts) FROM PUBLIC, anon, authenticated;
DO $$ BEGIN
  IF to_regprocedure('public._latest_po(text)') IS NOT NULL THEN
    REVOKE EXECUTE ON FUNCTION public._latest_po(TEXT) FROM PUBLIC, anon, authenticated;
  END IF;
  IF to_regprocedure('public._cust_by_token(text)') IS NOT NULL THEN
    REVOKE EXECUTE ON FUNCTION public._cust_by_token(TEXT) FROM PUBLIC, anon, authenticated;
  END IF;
  IF to_regprocedure('public.gen_customer_code()') IS NOT NULL THEN
    REVOKE EXECUTE ON FUNCTION public.gen_customer_code() FROM PUBLIC, anon, authenticated;
  END IF;
  IF to_regprocedure('public._touch_updated_at()') IS NOT NULL THEN
    REVOKE EXECUTE ON FUNCTION public._touch_updated_at() FROM PUBLIC, anon, authenticated;
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.request_staff_ok()                          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.staff_login(TEXT, TEXT)                     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.staff_session(TEXT)                         TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.staff_logout(TEXT)                          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.staff_change_password(TEXT, TEXT, TEXT)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.staff_save_location(TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_list(TEXT)                      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_add(TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_set_active(TEXT, TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_set_password(TEXT, TEXT, TEXT)  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_delete(TEXT, TEXT)              TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_customer_login_info(TEXT)             TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_customer_active(TEXT, TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reset_customer_password(TEXT, TEXT)   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_customer_account(TEXT, TEXT)   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_news_list(TEXT)                       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_news_save(TEXT, BIGINT, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_news_delete(TEXT, BIGINT)             TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.next_receipt_no(TEXT)                       TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ───────────── ส่วนที่ 3: ล็อกตารางบิล (RLS) ─────────────
DO $$
DECLARE
  t   TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['orders','order_items','receipts','customers','app_data','activity_logs'] LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE NOTICE 'ข้าม % (ไม่มีตารางนี้)', t;
      CONTINUE;
    END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = t LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;
    EXECUTE format(
      'CREATE POLICY staff_token_all ON public.%I FOR ALL TO anon, authenticated
         USING (public.request_staff_ok()) WITH CHECK (public.request_staff_ok())', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO anon, authenticated', t);
    RAISE NOTICE '✅ ล็อก % แล้ว', t;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
