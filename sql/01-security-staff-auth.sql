-- =====================================================================
-- RubberLedger — ขั้นที่ 1: ความปลอดภัยบัญชีพนักงาน + ฟังก์ชันแอดมิน
-- วันที่: 2026-10-20
--
-- ทำอะไร:
--   1. เก็บรหัสพนักงานแบบเข้ารหัส (bcrypt) แทนข้อความธรรมดา
--   2. ระบบ session token สำหรับพนักงาน (staff_login / staff_session / staff_logout)
--   3. จัดการพนักงานผ่าน RPC ที่ตรวจสิทธิ์แอดมิน (ห้ามแตะตาราง accounts ตรง ๆ)
--   4. ฟังก์ชันแอดมินของพอร์ทัลลูกค้า + ข่าว ต้องมี token แอดมิน
--   5. เลขใบเสร็จออกจากฐานข้อมูล (ไม่ซ้ำกันระหว่างเครื่อง)
--   6. UNIQUE ที่ po_no และ receipt_no (ถ้าข้อมูลเดิมไม่มีเลขซ้ำ)
--
-- ลำดับที่ถูกต้อง:
--   (ก) deploy หน้าเว็บเวอร์ชันใหม่ขึ้น GitHub Pages ก่อน
--   (ข) แล้วจึงรันไฟล์นี้ทั้งไฟล์ใน Supabase → SQL Editor → Run
--   หน้าเว็บใหม่รองรับทั้งก่อนและหลังรันไฟล์นี้
--
-- รันซ้ำได้ (idempotent)
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─────────────────────────────────────────────────────────────────────
-- 1) ตาราง accounts — คอลัมน์ที่ต้องมี
-- ─────────────────────────────────────────────────────────────────────
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

-- ย้ายรหัสเดิมเป็น bcrypt
UPDATE public.accounts
   SET pass_hash = crypt(password, gen_salt('bf'))
 WHERE pass_hash IS NULL AND password IS NOT NULL AND password <> '';

-- ล้างรหัสแบบข้อความธรรมดาทิ้ง
ALTER TABLE public.accounts ALTER COLUMN password DROP NOT NULL;
UPDATE public.accounts SET password = NULL WHERE pass_hash IS NOT NULL;

-- ปิดการเข้าถึงตาราง accounts จากเบราว์เซอร์โดยตรง
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='accounts' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.accounts', pol.policyname);
  END LOOP;
END $$;
REVOKE ALL ON public.accounts FROM anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 2) Session ของพนักงาน
-- ─────────────────────────────────────────────────────────────────────
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

-- ข้อมูลพนักงานที่ส่งให้หน้าเว็บได้ (ไม่มีรหัสผ่าน)
CREATE OR REPLACE FUNCTION public._staff_public(a public.accounts)
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT (to_jsonb(a) - 'password' - 'pass_hash' - 'failed_count' - 'locked_until')
         || jsonb_build_object('has_password', a.pass_hash IS NOT NULL)
$$;

-- หา account จาก token (NULL = ไม่ถูกต้อง/หมดอายุ/ถูกปิด)
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

-- ใช้ใน RLS (ขั้นที่ 2): token ส่งมาใน header x-staff-token
CREATE OR REPLACE FUNCTION public.request_staff_ok()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT (public._staff_by_token(
            COALESCE(current_setting('request.headers', true)::json ->> 'x-staff-token', '')
          )).username IS NOT NULL
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 3) RPC: ล็อกอิน / ตรวจ session / ออกจากระบบ / เปลี่ยนรหัสตัวเอง
-- ─────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────
-- 4) RPC: แอดมินจัดการพนักงาน
-- ─────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────
-- 5) พอร์ทัลลูกค้า: ฟังก์ชันแอดมิน — ต้องมี token แอดมิน
--    ลบเวอร์ชันเก่าที่ใครก็เรียกได้ทิ้งก่อน
-- ─────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.admin_list_customer_accounts();
DROP FUNCTION IF EXISTS public.admin_customer_login_info();
DROP FUNCTION IF EXISTS public.admin_set_customer_active(TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS public.admin_reset_customer_password(TEXT);
DROP FUNCTION IF EXISTS public.admin_reset_customer_pin(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.admin_delete_customer_account(TEXT);

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

-- ─────────────────────────────────────────────────────────────────────
-- 6) ข่าวสาร: ลูกค้าอ่านผ่าน customer_news() เท่านั้น แอดมินแก้ผ่าน RPC
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE public.news ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "news_admin_all" ON public.news;
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

-- ─────────────────────────────────────────────────────────────────────
-- 7) เลขใบเสร็จจากฐานข้อมูล: RC-YYMM#### ไม่ซ้ำกันระหว่างเครื่อง
-- ─────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────
-- 8) UNIQUE ที่เลขเอกสาร (ข้ามถ้าข้อมูลเดิมมีเลขซ้ำ — ดูคำสั่งตรวจด้านล่าง)
-- ─────────────────────────────────────────────────────────────────────
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

-- index ช่วยให้หน้าประวัติ/ซิงก์เร็วขึ้น
CREATE INDEX IF NOT EXISTS idx_orders_updated_at ON public.orders(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON public.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_receipts_issued_at ON public.receipts(issued_at DESC);
CREATE INDEX IF NOT EXISTS idx_receipts_order ON public.receipts(order_id);

-- ─────────────────────────────────────────────────────────────────────
-- 9) สิทธิ์เรียกฟังก์ชัน: ปิดทุกอย่างก่อน แล้วเปิดเฉพาะที่ตั้งใจ
-- ─────────────────────────────────────────────────────────────────────
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

-- ให้ PostgREST รู้จักฟังก์ชันใหม่ทันที
NOTIFY pgrst, 'reload schema';

-- =====================================================================
-- คำสั่งตรวจหลังรัน (รันแยกทีละคำสั่งได้)
-- =====================================================================
-- บัญชีที่ยังไม่มีรหัสแบบเข้ารหัส (ต้องตั้งรหัสใหม่ให้):
--   SELECT username, role FROM accounts WHERE pass_hash IS NULL;
-- เลขใบเสร็จซ้ำ:
--   SELECT receipt_no, count(*) FROM receipts GROUP BY 1 HAVING count(*) > 1;
-- เลข PO ซ้ำ:
--   SELECT po_no, count(*) FROM orders GROUP BY 1 HAVING count(*) > 1;
