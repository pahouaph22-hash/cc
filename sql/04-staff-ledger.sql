-- =====================================================================
-- RubberLedger — ขั้นที่ 4: บัญชีเงินสดของพนักงานฝ่ายจ่ายเงิน
-- วันที่: 2026-10-25     ต้องรัน 03-accounting.sql ก่อน     รันซ้ำได้
--
--   รายรับของพนักงาน  = เงินทดรองที่บริษัทมอบให้ (staff_cash_moves.kind='advance') — แอดมินบันทึก
--   รายจ่ายของพนักงาน = (1) จ่ายค่ายางให้ผู้ขาย  ← ใบเสร็จที่พนักงานคนนั้นออก (receipts.issued_by)
--                      (2) ค่าใช้จ่ายที่พนักงานจ่ายเอง (expenses.staff_username)
--                      (3) ส่งเงินคืนบริษัท (staff_cash_moves.kind='return')
--   ยอดคงเหลือในมือ   = ยกมา + รับ − จ่าย  (คำนวณเฉพาะเมื่อมีการบันทึกเงินรับแล้ว ไม่เดา)
-- =====================================================================

-- ─────────────────────────────────────────────────────────────────────
-- 1) ใบเสร็จ: ผู้ออกใบเสร็จมาจาก token ฝั่งเซิร์ฟเวอร์ (แก้จากเบราว์เซอร์ไม่ได้)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._receipt_stamp()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE a public.accounts%ROWTYPE;
BEGIN
  a := public._staff_by_token(COALESCE(current_setting('request.headers', true)::json ->> 'x-staff-token', ''));
  IF a.username IS NOT NULL THEN
    NEW.issued_by   := a.username;
    NEW.issued_role := a.role;
  END IF;
  RETURN NEW;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_receipts_stamp') THEN
    CREATE TRIGGER trg_receipts_stamp BEFORE INSERT ON public.receipts
      FOR EACH ROW EXECUTE FUNCTION public._receipt_stamp();
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_receipts_issued_by ON public.receipts (issued_by, issued_at);

-- ─────────────────────────────────────────────────────────────────────
-- 2) เงินทดรอง / ส่งคืน
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.staff_cash_moves (
  id             BIGSERIAL PRIMARY KEY,
  staff_username TEXT NOT NULL,
  move_date      DATE NOT NULL,
  kind           TEXT NOT NULL CHECK (kind IN ('advance','return')),
  amount         NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  method         TEXT NOT NULL DEFAULT 'cash' CHECK (method IN ('cash','transfer')),
  note           TEXT DEFAULT '',
  is_deleted     BOOLEAN NOT NULL DEFAULT false,
  deleted_at     TIMESTAMPTZ,
  deleted_by     TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by     TEXT,
  updated_at     TIMESTAMPTZ,
  updated_by     TEXT
);
CREATE INDEX IF NOT EXISTS idx_cash_moves_staff ON public.staff_cash_moves (staff_username, move_date);

-- ค่าใช้จ่ายที่พนักงานจ่ายจากเงินในมือ
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS staff_username TEXT;
CREATE INDEX IF NOT EXISTS idx_expenses_staff ON public.expenses (staff_username, expense_date) WHERE staff_username IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────
-- 3) Trigger: ประทับเวลา/ผู้บันทึก + ประวัติ (ใช้ของ 03) และบังคับเจ้าของรายการ
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._acct_stamp()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE who TEXT := COALESCE(public.request_staff_user(), current_user::text);
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := now(); NEW.created_by := who;
    NEW.updated_at := NULL;  NEW.updated_by := NULL;
  ELSE
    NEW.created_at := OLD.created_at; NEW.created_by := OLD.created_by;
    NEW.updated_at := now(); NEW.updated_by := who;
  END IF;
  IF TG_TABLE_NAME IN ('expenses','rubber_sales','staff_cash_moves') THEN
    IF NEW.is_deleted AND (TG_OP = 'INSERT' OR NOT OLD.is_deleted) THEN
      NEW.deleted_at := now(); NEW.deleted_by := who;
    ELSIF NOT NEW.is_deleted THEN
      NEW.deleted_at := NULL; NEW.deleted_by := NULL;
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public._acct_audit()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE act TEXT := lower(TG_OP);
BEGIN
  IF TG_OP = 'UPDATE' AND TG_TABLE_NAME IN ('expenses','rubber_sales','staff_cash_moves') THEN
    IF NEW.is_deleted AND NOT OLD.is_deleted THEN act := 'delete';
    ELSIF OLD.is_deleted AND NOT NEW.is_deleted THEN act := 'restore'; END IF;
  END IF;
  INSERT INTO public.acct_audit(table_name, row_id, action, old_data, new_data, actor)
  VALUES (TG_TABLE_NAME, NEW.id::text, act,
          CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END, to_jsonb(NEW),
          COALESCE(public.request_staff_user(), current_user::text));
  RETURN NEW;
END $$;

-- พนักงาน (ไม่ใช่แอดมิน) บันทึกค่าใช้จ่ายได้เฉพาะในนามตัวเอง และย้ายเจ้าของไม่ได้
CREATE OR REPLACE FUNCTION public._expense_owner()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE r TEXT := public.request_staff_role(); u TEXT := public.request_staff_user();
BEGIN
  IF r IS NOT NULL AND r <> 'admin' THEN
    IF TG_OP = 'UPDATE' AND OLD.staff_username IS DISTINCT FROM u THEN
      RAISE EXCEPTION 'not_owner' USING ERRCODE = '42501';
    END IF;
    NEW.staff_username := u;
  END IF;
  IF NEW.staff_username = '' THEN NEW.staff_username := NULL; END IF;
  RETURN NEW;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_expenses_owner') THEN
    CREATE TRIGGER trg_expenses_owner BEFORE INSERT OR UPDATE ON public.expenses
      FOR EACH ROW EXECUTE FUNCTION public._expense_owner();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_staff_cash_moves_stamp') THEN
    CREATE TRIGGER trg_staff_cash_moves_stamp BEFORE INSERT OR UPDATE ON public.staff_cash_moves
      FOR EACH ROW EXECUTE FUNCTION public._acct_stamp();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_staff_cash_moves_audit') THEN
    CREATE TRIGGER trg_staff_cash_moves_audit AFTER INSERT OR UPDATE ON public.staff_cash_moves
      FOR EACH ROW EXECUTE FUNCTION public._acct_audit();
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 4) สิทธิ์
--   แอดมิน: ทุกอย่าง (policy เดิมจาก 03)
--   พนักงานจ่ายเงิน: อ่าน/เพิ่ม/แก้ ค่าใช้จ่ายของตัวเอง, อ่านเงินทดรองของตัวเอง, อ่านประเภทค่าใช้จ่าย,
--                   อ่านประวัติของรายการตัวเอง
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE public.staff_cash_moves ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff_cash_moves' AND policyname='acct_admin_select') THEN
    CREATE POLICY acct_admin_select ON public.staff_cash_moves FOR SELECT TO anon, authenticated USING (public.request_staff_role() = 'admin');
    CREATE POLICY acct_admin_insert ON public.staff_cash_moves FOR INSERT TO anon, authenticated WITH CHECK (public.request_staff_role() = 'admin');
    CREATE POLICY acct_admin_update ON public.staff_cash_moves FOR UPDATE TO anon, authenticated USING (public.request_staff_role() = 'admin') WITH CHECK (public.request_staff_role() = 'admin');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff_cash_moves' AND policyname='staff_own_select') THEN
    CREATE POLICY staff_own_select ON public.staff_cash_moves FOR SELECT TO anon, authenticated
      USING (public.request_staff_role() = 'staff_cashier' AND staff_username = public.request_staff_user());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='expenses' AND policyname='staff_own_select') THEN
    CREATE POLICY staff_own_select ON public.expenses FOR SELECT TO anon, authenticated
      USING (public.request_staff_role() = 'staff_cashier' AND staff_username = public.request_staff_user());
    CREATE POLICY staff_own_insert ON public.expenses FOR INSERT TO anon, authenticated
      WITH CHECK (public.request_staff_role() = 'staff_cashier' AND staff_username = public.request_staff_user());
    CREATE POLICY staff_own_update ON public.expenses FOR UPDATE TO anon, authenticated
      USING (public.request_staff_role() = 'staff_cashier' AND staff_username = public.request_staff_user())
      WITH CHECK (public.request_staff_role() = 'staff_cashier' AND staff_username = public.request_staff_user());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='expense_categories' AND policyname='staff_read') THEN
    CREATE POLICY staff_read ON public.expense_categories FOR SELECT TO anon, authenticated
      USING (public.request_staff_role() = 'staff_cashier');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='acct_audit' AND policyname='staff_own_select') THEN
    CREATE POLICY staff_own_select ON public.acct_audit FOR SELECT TO anon, authenticated
      USING (public.request_staff_role() = 'staff_cashier'
             AND table_name IN ('expenses','staff_cash_moves')
             AND new_data ->> 'staff_username' = public.request_staff_user());
  END IF;
END $$;

REVOKE ALL ON public.staff_cash_moves FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.staff_cash_moves TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.staff_cash_moves_id_seq TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 5) รายการเคลื่อนไหวทั้งหมดของพนักงาน (ใช้ภายใน)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._staff_lines(v_user TEXT)
RETURNS TABLE (
  ev_date DATE, ev_ts TIMESTAMPTZ, kind TEXT, ref TEXT, ref2 TEXT, party TEXT, detail TEXT,
  kg NUMERIC, price_min NUMERIC, price_max NUMERIC, method TEXT, location TEXT,
  amount_in NUMERIC, amount_out NUMERIC, src_table TEXT, src_id TEXT, order_status TEXT, bill_total NUMERIC
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  -- เงินทดรอง / ส่งคืน
SELECT m.move_date, m.created_at, m.kind,
       'CM-' || m.id, NULL, NULL, COALESCE(m.note,''),
       NULL, NULL, NULL, m.method, NULL,
       CASE WHEN m.kind = 'advance' THEN m.amount ELSE 0 END,
       CASE WHEN m.kind = 'return'  THEN m.amount ELSE 0 END,
       'staff_cash_moves', m.id::text, NULL, NULL
  FROM public.staff_cash_moves m
 WHERE m.staff_username = v_user AND NOT m.is_deleted
UNION ALL
-- จ่ายค่ายางให้ผู้ขาย (จากใบเสร็จที่พนักงานคนนี้ออก)
SELECT (r.issued_at AT TIME ZONE 'Asia/Vientiane')::date, r.issued_at, 'payment',
       r.receipt_no, o.po_no, COALESCE(o.customer, r.customer), COALESCE(r.note,''),
       COALESCE(o.total_qty, r.total_qty),
       (SELECT MIN(i.price) FROM public.order_items i WHERE i.order_id = o.id AND i.product_id = 'RUBBER'),
       (SELECT MAX(i.price) FROM public.order_items i WHERE i.order_id = o.id AND i.product_id = 'RUBBER'),
       r.pay_method, r.work_location,
       0, COALESCE(r.amount, 0),
       'orders', r.order_id, o.status, o.grand_total
  FROM public.receipts r LEFT JOIN public.orders o ON o.id = r.order_id
 WHERE r.issued_by = v_user
UNION ALL
-- ค่าใช้จ่ายที่พนักงานจ่ายเอง
SELECT e.expense_date, e.created_at, 'expense',
       'EX-' || e.id, c.name, NULL, e.description || CASE WHEN COALESCE(e.note,'') <> '' THEN ' — ' || e.note ELSE '' END,
       NULL, NULL, NULL, NULL, NULL,
       0, e.amount, 'expenses', e.id::text, NULL, NULL
  FROM public.expenses e LEFT JOIN public.expense_categories c ON c.id = e.category_id
 WHERE e.staff_username = v_user AND NOT e.is_deleted
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 6) RPC: บัญชีเงินสดของพนักงาน
--   แอดมินเลือกดูพนักงานคนใดก็ได้ / พนักงานดูได้เฉพาะของตัวเอง (p_username ถูกเมิน)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.staff_ledger(p_token TEXT, p_username TEXT, p_from DATE, p_to DATE)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  me public.accounts%ROWTYPE; who public.accounts%ROWTYPE;
  v_user TEXT; v_has_cash BOOLEAN; v_opening NUMERIC;
  v_lines JSONB; v_daily JSONB; v_sum JSONB; v_issues JSONB; v_methods JSONB;
BEGIN
  me := public._require_staff(p_token);
  IF me.role = 'admin' THEN
    v_user := COALESCE(NULLIF(TRIM(p_username), ''), me.username);
  ELSIF me.role = 'staff_cashier' THEN
    v_user := me.username;
  ELSE
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;
  IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_from > p_to THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_range');
  END IF;
  SELECT * INTO who FROM public.accounts WHERE username = v_user;

  SELECT EXISTS (SELECT 1 FROM public.staff_cash_moves m
                  WHERE m.staff_username = v_user AND m.kind = 'advance' AND NOT m.is_deleted)
    INTO v_has_cash;

  SELECT COALESCE(SUM(amount_in - amount_out), 0) INTO v_opening
    FROM public._staff_lines(v_user) WHERE p_from IS NOT NULL AND ev_date < p_from;

  -- รายการตามลำดับเวลา พร้อมยอดคงเหลือสะสม
  WITH ordered AS (
    SELECT l.*, SUM(amount_in - amount_out) OVER (ORDER BY ev_date, ev_ts, kind, ref ROWS UNBOUNDED PRECEDING) AS running
      FROM public._staff_lines(v_user) l
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'date', ev_date, 'ts', ev_ts, 'kind', kind, 'ref', ref, 'ref2', ref2, 'party', party, 'detail', detail,
           'kg', kg, 'price_min', price_min, 'price_max', price_max, 'method', method, 'location', location,
           'in', amount_in, 'out', amount_out,
           'balance', CASE WHEN v_has_cash THEN running END,
           'src_table', src_table, 'src_id', src_id, 'order_status', order_status, 'bill_total', bill_total)
         ORDER BY ev_date, ev_ts, kind, ref), '[]'::jsonb)
    INTO v_lines
    FROM ordered
   WHERE (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to);

  -- รายวัน
  SELECT COALESCE(jsonb_agg(d ORDER BY d.date), '[]'::jsonb) INTO v_daily FROM (
    SELECT ev_date AS date,
           SUM(amount_in)                                    AS cash_in,
           SUM(amount_out) FILTER (WHERE kind = 'payment')   AS paid_out,
           COUNT(*)        FILTER (WHERE kind = 'payment')   AS n_payments,
           SUM(kg)         FILTER (WHERE kind = 'payment')   AS kg,
           SUM(amount_out) FILTER (WHERE kind = 'expense')   AS expense_out,
           SUM(amount_out) FILTER (WHERE kind = 'return')    AS returned,
           SUM(amount_in - amount_out)                       AS net
      FROM public._staff_lines(v_user)
     WHERE (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to)
     GROUP BY ev_date
  ) d;

  -- สรุป
  SELECT jsonb_build_object(
    'opening',     CASE WHEN v_has_cash THEN v_opening END,
    'cash_in',     COALESCE(SUM(amount_in),0),
    'n_advances',  COUNT(*) FILTER (WHERE kind = 'advance'),
    'paid_out',    COALESCE(SUM(amount_out) FILTER (WHERE kind = 'payment'),0),
    'n_payments',  COUNT(*) FILTER (WHERE kind = 'payment'),
    'kg',          COALESCE(SUM(kg) FILTER (WHERE kind = 'payment'),0),
    'avg_price',   CASE WHEN SUM(kg) FILTER (WHERE kind = 'payment') > 0
                        THEN ROUND(SUM(amount_out) FILTER (WHERE kind = 'payment') / SUM(kg) FILTER (WHERE kind = 'payment'), 2) END,
    'expense_out', COALESCE(SUM(amount_out) FILTER (WHERE kind = 'expense'),0),
    'n_expenses',  COUNT(*) FILTER (WHERE kind = 'expense'),
    'returned',    COALESCE(SUM(amount_out) FILTER (WHERE kind = 'return'),0),
    'total_out',   COALESCE(SUM(amount_out),0),
    'net',         COALESCE(SUM(amount_in - amount_out),0),
    'closing',     CASE WHEN v_has_cash THEN v_opening + COALESCE(SUM(amount_in - amount_out),0) END,
    'has_cash_records', v_has_cash
  ) INTO v_sum
    FROM public._staff_lines(v_user)
   WHERE (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to);

  -- แยกตามวิธีชำระ
  SELECT COALESCE(jsonb_object_agg(method, amt), '{}'::jsonb) INTO v_methods FROM (
    SELECT COALESCE(method,'cash') AS method, SUM(amount_out) AS amt
      FROM public._staff_lines(v_user) WHERE kind = 'payment'
       AND (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to)
     GROUP BY 1
  ) x;

  -- ตรวจความถูกต้อง
  SELECT COALESCE(jsonb_agg(i), '[]'::jsonb) INTO v_issues FROM (
    SELECT 'receipt_amount_mismatch' AS code, ref, ref2, src_id,
           jsonb_build_object('receipt', amount_out, 'bill', bill_total) AS info
      FROM public._staff_lines(v_user) WHERE kind = 'payment' AND bill_total IS NOT NULL AND ABS(amount_out - bill_total) > 1
       AND (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to)
    UNION ALL
    SELECT 'receipt_order_not_paid', ref, ref2, src_id, jsonb_build_object('status', COALESCE(order_status, 'missing'))
      FROM public._staff_lines(v_user) WHERE kind = 'payment' AND COALESCE(order_status,'missing') <> 'paid'
       AND (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to)
    UNION ALL
    SELECT 'multiple_receipts', MIN(ref), MIN(ref2), src_id, jsonb_build_object('n', COUNT(*))
      FROM public._staff_lines(v_user) WHERE kind = 'payment' AND src_id IS NOT NULL
       AND (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to)
     GROUP BY src_id HAVING COUNT(*) > 1
  ) i;

  RETURN jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'generated_at', now(),
    'staff', jsonb_build_object('username', v_user, 'display_name', COALESCE(who.display_name, v_user), 'role', who.role),
    'summary', v_sum, 'by_method', v_methods, 'daily', v_daily, 'lines', v_lines, 'issues', v_issues);
END $$;

-- รายชื่อพนักงานจ่ายเงิน (สำหรับแอดมินเลือกดู)
CREATE OR REPLACE FUNCTION public.staff_ledger_people(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v JSONB;
BEGIN
  PERFORM public._require_admin(p_token);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('username', a.username, 'display_name', a.display_name,
                                               'role', a.role, 'is_active', a.is_active)
                            ORDER BY (a.role = 'staff_cashier') DESC, a.display_name), '[]'::jsonb)
    INTO v
    FROM public.accounts a
   WHERE a.role IN ('staff_cashier','admin')
      OR EXISTS (SELECT 1 FROM public.receipts r WHERE r.issued_by = a.username);
  RETURN jsonb_build_object('ok', true, 'people', v);
END $$;

REVOKE EXECUTE ON FUNCTION public._receipt_stamp()  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._expense_owner()  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._staff_lines(TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._acct_stamp()     FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._acct_audit()     FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.staff_ledger(TEXT, TEXT, DATE, DATE) TO anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.staff_ledger_people(TEXT)            TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
