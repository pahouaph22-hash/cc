-- =====================================================================
-- RubberLedger — ขั้นที่ 3: ระบบบัญชีรายรับ–รายจ่าย
-- วันที่: 2026-10-23     ต้องรัน 00 + setup-remaining (01/02) ก่อน     รันซ้ำได้
--
-- หลักการคำนวณ (กันนับซ้ำ):
--   • ต้นทุนรับซื้อ   = orders.grand_total ของบิลที่ไม่ถูกยกเลิก นับตาม "วันที่บิล" (orders.date)
--                      นับ 1 ครั้งต่อบิลเท่านั้น
--   • การจ่ายเงิน     = สถานะ/วันที่ชำระของบิลเดียวกัน (orders.paid_at + receipts)
--                      ใช้แสดงยอดจ่ายแล้ว/ค้างจ่าย และกระแสเงินสด — ไม่บวกเป็นต้นทุนซ้ำ
--   • ค่าใช้จ่ายเพิ่มเติม = ตาราง expenses (ไม่รวมรายการที่ถูกลบ)
--   • รายรับจากการขาย  = ตาราง rubber_sales — ถ้าไม่มีข้อมูล ระบบคืนค่า NULL (ไม่เดาตัวเลข)
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─────────────────────────────────────────────────────────────────────
-- 0) ตัวช่วยสิทธิ์: บทบาทของผู้เรียกจาก header x-staff-token
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.request_staff_role()
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT (public._staff_by_token(
            COALESCE(current_setting('request.headers', true)::json ->> 'x-staff-token', '')
          )).role
$$;
CREATE OR REPLACE FUNCTION public.request_staff_user()
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT (public._staff_by_token(
            COALESCE(current_setting('request.headers', true)::json ->> 'x-staff-token', '')
          )).username
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 1) ตาราง
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.expense_categories (
  id         BIGSERIAL PRIMARY KEY,
  name       TEXT NOT NULL,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  sort_order INT NOT NULL DEFAULT 100,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by TEXT,
  updated_at TIMESTAMPTZ,
  updated_by TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_expense_cat_name ON public.expense_categories (LOWER(TRIM(name)));

INSERT INTO public.expense_categories(name, sort_order, created_by)
SELECT v.name, v.ord, 'system'
FROM (VALUES ('ค่าขนส่ง',10),('ค่าแรงงาน',20),('ค่าน้ำมัน',30),('ค่าอาหารพนักงาน',40),('ค่าใช้จ่ายอื่น ๆ',90)) AS v(name, ord)
WHERE NOT EXISTS (SELECT 1 FROM public.expense_categories c WHERE LOWER(TRIM(c.name)) = LOWER(TRIM(v.name)));

CREATE TABLE IF NOT EXISTS public.expenses (
  id           BIGSERIAL PRIMARY KEY,
  expense_date DATE NOT NULL,
  category_id  BIGINT NOT NULL REFERENCES public.expense_categories(id),
  description  TEXT NOT NULL CHECK (length(trim(description)) > 0),
  amount       NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  note         TEXT DEFAULT '',
  is_deleted   BOOLEAN NOT NULL DEFAULT false,
  deleted_at   TIMESTAMPTZ,
  deleted_by   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by   TEXT,
  updated_at   TIMESTAMPTZ,
  updated_by   TEXT
);
CREATE INDEX IF NOT EXISTS idx_expenses_date ON public.expenses (expense_date) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS idx_expenses_cat  ON public.expenses (category_id);

CREATE TABLE IF NOT EXISTS public.rubber_sales (
  id           BIGSERIAL PRIMARY KEY,
  sale_date    DATE NOT NULL,
  buyer        TEXT NOT NULL CHECK (length(trim(buyer)) > 0),
  qty_kg       NUMERIC(14,2) NOT NULL CHECK (qty_kg > 0),
  price_per_kg NUMERIC(14,2) NOT NULL CHECK (price_per_kg >= 0),
  amount       NUMERIC(14,2) NOT NULL CHECK (amount >= 0),
  doc_no       TEXT DEFAULT '',
  note         TEXT DEFAULT '',
  is_deleted   BOOLEAN NOT NULL DEFAULT false,
  deleted_at   TIMESTAMPTZ,
  deleted_by   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by   TEXT,
  updated_at   TIMESTAMPTZ,
  updated_by   TEXT
);
CREATE INDEX IF NOT EXISTS idx_sales_date ON public.rubber_sales (sale_date) WHERE NOT is_deleted;

-- ประวัติการแก้ไข (append-only)
CREATE TABLE IF NOT EXISTS public.acct_audit (
  id         BIGSERIAL PRIMARY KEY,
  table_name TEXT NOT NULL,
  row_id     TEXT NOT NULL,
  action     TEXT NOT NULL,          -- insert | update | delete (soft) | restore
  old_data   JSONB,
  new_data   JSONB,
  actor      TEXT,
  at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_acct_audit_row ON public.acct_audit (table_name, row_id, at DESC);

-- ─────────────────────────────────────────────────────────────────────
-- 2) Trigger: ผู้บันทึก/ผู้แก้ไข มาจาก token ฝั่งเซิร์ฟเวอร์ (ปลอมจากเบราว์เซอร์ไม่ได้)
--    + บันทึกประวัติทุกครั้ง
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
  IF TG_TABLE_NAME IN ('expenses','rubber_sales') THEN
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
  IF TG_OP = 'UPDATE' AND TG_TABLE_NAME IN ('expenses','rubber_sales') THEN
    IF NEW.is_deleted AND NOT OLD.is_deleted THEN act := 'delete';
    ELSIF OLD.is_deleted AND NOT NEW.is_deleted THEN act := 'restore'; END IF;
  END IF;
  INSERT INTO public.acct_audit(table_name, row_id, action, old_data, new_data, actor)
  VALUES (TG_TABLE_NAME, NEW.id::text, act,
          CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END, to_jsonb(NEW),
          COALESCE(public.request_staff_user(), current_user::text));
  RETURN NEW;
END $$;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['expense_categories','expenses','rubber_sales'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_'||t||'_stamp') THEN
      EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public._acct_stamp()', 'trg_'||t||'_stamp', t);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_'||t||'_audit') THEN
      EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public._acct_audit()', 'trg_'||t||'_audit', t);
    END IF;
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 3) สิทธิ์: เฉพาะแอดมิน (ผ่าน token) — อ่าน/เพิ่ม/แก้ได้ ลบจริงไม่ได้ (ใช้ลบแบบซ่อน)
--    ประวัติ: อ่านได้อย่างเดียว
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rubber_sales       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acct_audit         ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['expense_categories','expenses','rubber_sales'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=t AND policyname='acct_admin_select') THEN
      EXECUTE format('CREATE POLICY acct_admin_select ON public.%I FOR SELECT TO anon, authenticated USING (public.request_staff_role() = ''admin'')', t);
      EXECUTE format('CREATE POLICY acct_admin_insert ON public.%I FOR INSERT TO anon, authenticated WITH CHECK (public.request_staff_role() = ''admin'')', t);
      EXECUTE format('CREATE POLICY acct_admin_update ON public.%I FOR UPDATE TO anon, authenticated USING (public.request_staff_role() = ''admin'') WITH CHECK (public.request_staff_role() = ''admin'')', t);
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='acct_audit' AND policyname='acct_admin_select') THEN
    CREATE POLICY acct_admin_select ON public.acct_audit FOR SELECT TO anon, authenticated USING (public.request_staff_role() = 'admin');
  END IF;
END $$;

REVOKE ALL ON public.expense_categories, public.expenses, public.rubber_sales, public.acct_audit FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.expense_categories, public.expenses, public.rubber_sales TO anon, authenticated;
GRANT SELECT ON public.acct_audit TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.expense_categories_id_seq, public.expenses_id_seq, public.rubber_sales_id_seq TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 4) วันที่บิลที่ใช้คำนวณ (ถ้าไม่มี date ใช้วันที่สร้างตามเวลาลาว)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._bill_date(o public.orders)
RETURNS DATE LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT COALESCE(o.date, (o.created_at AT TIME ZONE 'Asia/Vientiane')::date)
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 5) รายละเอียดต่อบิล (ใช้ทั้งรายงานและตารางย้อนกลับไปหาบิลต้นทาง)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._acct_bill_rows(p_from DATE, p_to DATE)
RETURNS TABLE (
  order_id TEXT, po_no TEXT, customer TEXT, bill_date DATE, month TEXT, status TEXT,
  grand_total NUMERIC, total_qty NUMERIC, created_by TEXT, paid_by TEXT, paid_at TIMESTAMPTZ,
  n_items INT, rubber_kg NUMERIC, rubber_amt NUMERIC, ship_amt NUMERIC, other_amt NUMERIC,
  items_amt NUMERIC, price_min NUMERIC, price_max NUMERIC,
  n_receipts INT, receipt_amt NUMERIC, receipt_nos TEXT, date_missing BOOLEAN
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH b AS (
    SELECT o.*, public._bill_date(o) AS bd FROM public.orders o
  ), it AS (
    SELECT i.order_id,
           COUNT(*)::int AS n_items,
           SUM(CASE WHEN i.product_id = 'RUBBER' THEN COALESCE(i.qty,0) END) AS rubber_kg,
           SUM(CASE WHEN i.product_id = 'RUBBER' THEN COALESCE(i.qty,0) * COALESCE(i.price,0) END) AS rubber_amt,
           SUM(CASE WHEN i.product_id = 'SHIPPING' THEN COALESCE(i.price,0) END) AS ship_price_sum,
           SUM(CASE WHEN i.product_id NOT IN ('RUBBER','SHIPPING') THEN COALESCE(i.qty,0) * COALESCE(i.price,0) END) AS other_amt,
           MIN(CASE WHEN i.product_id = 'RUBBER' THEN i.price END) AS price_min,
           MAX(CASE WHEN i.product_id = 'RUBBER' THEN i.price END) AS price_max
      FROM public.order_items i GROUP BY i.order_id
  ), rc AS (
    SELECT r.order_id, COUNT(*)::int AS n, SUM(r.amount) AS amt,
           string_agg(r.receipt_no, ', ' ORDER BY r.issued_at) AS nos
      FROM public.receipts r WHERE r.order_id IS NOT NULL GROUP BY r.order_id
  )
  SELECT b.id, b.po_no, b.customer, b.bd, to_char(b.bd, 'YYYY-MM'), b.status,
         COALESCE(b.grand_total,0), COALESCE(b.total_qty,0), b.created_by, b.paid_by, b.paid_at,
         COALESCE(it.n_items,0),
         COALESCE(it.rubber_kg,0), COALESCE(it.rubber_amt,0),
         -- ค่าจัดส่งในบิล = กก.ยางทั้งบิล × ราคาจัดส่ง/กก. (ตรงกับวิธีคำนวณในแอป)
         COALESCE(it.ship_price_sum,0) * COALESCE(b.total_qty,0),
         COALESCE(it.other_amt,0),
         COALESCE(it.rubber_amt,0) + COALESCE(it.ship_price_sum,0) * COALESCE(b.total_qty,0) + COALESCE(it.other_amt,0),
         it.price_min, it.price_max,
         COALESCE(rc.n,0), COALESCE(rc.amt,0), rc.nos, (b.date IS NULL)
    FROM b LEFT JOIN it ON it.order_id = b.id LEFT JOIN rc ON rc.order_id = b.id
   WHERE (p_from IS NULL OR b.bd >= p_from) AND (p_to IS NULL OR b.bd <= p_to)
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 6) RPC: รายงานบัญชี
--    p_include_unpaid = true  → นับบิล draft/sent/paid (ยกเว้นยกเลิก)
--                     = false → นับเฉพาะบิลที่ชำระแล้ว
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.acct_report(p_token TEXT, p_from DATE, p_to DATE, p_include_unpaid BOOLEAN DEFAULT true)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_months JSONB; v_totals JSONB; v_issues JSONB; v_cats JSONB; v_excluded JSONB;
BEGIN
  PERFORM public._require_admin(p_token);
  IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_from > p_to THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_range');
  END IF;

  WITH _b AS (SELECT * FROM public._acct_bill_rows(p_from, p_to)),
  counted AS (
    SELECT * FROM _b WHERE status <> 'cancelled' AND (p_include_unpaid OR status = 'paid')
  ), pm AS (
    SELECT month,
           COUNT(*)                                   AS n_bills,
           SUM(total_qty)                             AS kg,
           SUM(grand_total)                           AS purchase_cost,
           SUM(rubber_amt)                            AS rubber_amt,
           SUM(rubber_kg)                             AS rubber_kg_items,
           SUM(ship_amt)                              AS ship_amt,
           SUM(other_amt)                             AS other_item_amt,
           MIN(price_min)                             AS price_min,
           MAX(price_max)                             AS price_max,
           SUM(grand_total) FILTER (WHERE status = 'paid')  AS paid_amt,
           SUM(grand_total) FILTER (WHERE status <> 'paid') AS unpaid_amt,
           COUNT(*) FILTER (WHERE status <> 'paid')         AS n_unpaid
      FROM counted GROUP BY month
  ), cash AS (    -- เงินที่จ่ายออกจริง ตามวันที่ชำระ (ข้อมูลประกอบ ไม่บวกซ้ำกับต้นทุน)
    SELECT to_char((o.paid_at AT TIME ZONE 'Asia/Vientiane')::date, 'YYYY-MM') AS month,
           SUM(o.grand_total) AS cash_paid, COUNT(*) AS n_paid
      FROM public.orders o
     WHERE o.status = 'paid' AND o.paid_at IS NOT NULL
       AND (p_from IS NULL OR (o.paid_at AT TIME ZONE 'Asia/Vientiane')::date >= p_from)
       AND (p_to   IS NULL OR (o.paid_at AT TIME ZONE 'Asia/Vientiane')::date <= p_to)
     GROUP BY 1
  ), ex AS (
    SELECT to_char(e.expense_date, 'YYYY-MM') AS month, SUM(e.amount) AS expenses, COUNT(*) AS n_expenses
      FROM public.expenses e
     WHERE NOT e.is_deleted
       AND (p_from IS NULL OR e.expense_date >= p_from) AND (p_to IS NULL OR e.expense_date <= p_to)
     GROUP BY 1
  ), sl AS (
    SELECT to_char(s.sale_date, 'YYYY-MM') AS month, SUM(s.amount) AS revenue, SUM(s.qty_kg) AS sold_kg, COUNT(*) AS n_sales
      FROM public.rubber_sales s
     WHERE NOT s.is_deleted
       AND (p_from IS NULL OR s.sale_date >= p_from) AND (p_to IS NULL OR s.sale_date <= p_to)
     GROUP BY 1
  ), months AS (
    SELECT month FROM pm UNION SELECT month FROM cash UNION SELECT month FROM ex UNION SELECT month FROM sl
  )
  , _m AS (
  SELECT m.month,
         COALESCE(pm.n_bills,0) AS n_bills, COALESCE(pm.kg,0) AS kg,
         COALESCE(pm.purchase_cost,0) AS purchase_cost,
         COALESCE(pm.rubber_amt,0) AS rubber_amt, COALESCE(pm.rubber_kg_items,0) AS rubber_kg_items,
         COALESCE(pm.ship_amt,0) AS ship_amt, COALESCE(pm.other_item_amt,0) AS other_item_amt,
         CASE WHEN COALESCE(pm.rubber_kg_items,0) > 0 THEN ROUND(pm.rubber_amt / pm.rubber_kg_items, 2) END AS avg_price,
         pm.price_min, pm.price_max,
         COALESCE(pm.paid_amt,0) AS paid_amt, COALESCE(pm.unpaid_amt,0) AS unpaid_amt, COALESCE(pm.n_unpaid,0) AS n_unpaid,
         COALESCE(cash.cash_paid,0) AS cash_paid, COALESCE(cash.n_paid,0) AS n_paid,
         COALESCE(ex.expenses,0) AS expenses, COALESCE(ex.n_expenses,0) AS n_expenses,
         sl.revenue, COALESCE(sl.sold_kg,0) AS sold_kg, COALESCE(sl.n_sales,0) AS n_sales,
         CASE WHEN COALESCE(sl.sold_kg,0) > 0 THEN ROUND(sl.revenue / sl.sold_kg, 2) END AS avg_sell_price,
         CASE WHEN sl.n_sales > 0
              THEN sl.revenue - COALESCE(pm.purchase_cost,0) - COALESCE(ex.expenses,0) END AS net_profit
    FROM months m
    LEFT JOIN pm   ON pm.month = m.month
    LEFT JOIN cash ON cash.month = m.month
    LEFT JOIN ex   ON ex.month = m.month
    LEFT JOIN sl   ON sl.month = m.month
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(_m) ORDER BY month), '[]'::jsonb),
    jsonb_build_object(
    'n_bills', COALESCE(SUM(n_bills),0), 'kg', COALESCE(SUM(kg),0),
    'purchase_cost', COALESCE(SUM(purchase_cost),0),
    'rubber_amt', COALESCE(SUM(rubber_amt),0), 'rubber_kg_items', COALESCE(SUM(rubber_kg_items),0),
    'ship_amt', COALESCE(SUM(ship_amt),0), 'other_item_amt', COALESCE(SUM(other_item_amt),0),
    'avg_price', CASE WHEN SUM(rubber_kg_items) > 0 THEN ROUND(SUM(rubber_amt) / SUM(rubber_kg_items), 2) END,
    'price_min', MIN(price_min), 'price_max', MAX(price_max),
    'paid_amt', COALESCE(SUM(paid_amt),0), 'unpaid_amt', COALESCE(SUM(unpaid_amt),0), 'n_unpaid', COALESCE(SUM(n_unpaid),0),
    'cash_paid', COALESCE(SUM(cash_paid),0),
    'expenses', COALESCE(SUM(expenses),0), 'n_expenses', COALESCE(SUM(n_expenses),0),
    'revenue', CASE WHEN SUM(n_sales) > 0 THEN SUM(revenue) END,
    'sold_kg', COALESCE(SUM(sold_kg),0), 'n_sales', COALESCE(SUM(n_sales),0),
    'avg_sell_price', CASE WHEN SUM(sold_kg) > 0 THEN ROUND(SUM(revenue) / SUM(sold_kg), 2) END,
    'net_profit', CASE WHEN SUM(n_sales) > 0
                       THEN COALESCE(SUM(revenue),0) - COALESCE(SUM(purchase_cost),0) - COALESCE(SUM(expenses),0) END,
    'months_without_sales', COUNT(*) FILTER (WHERE n_sales = 0 AND (n_bills > 0 OR n_expenses > 0)),
    'stock_kg', COALESCE(SUM(kg),0) - COALESCE(SUM(sold_kg),0)
  ) AS totals
    INTO v_months, v_totals FROM _m;

  -- ค่าใช้จ่ายแยกตามประเภท × เดือน
  SELECT COALESCE(jsonb_agg(x ORDER BY x.month, x.sort_order, x.category), '[]'::jsonb) INTO v_cats FROM (
    SELECT to_char(e.expense_date,'YYYY-MM') AS month, c.id AS category_id, c.name AS category, c.sort_order,
           SUM(e.amount) AS amount, COUNT(*) AS n
      FROM public.expenses e JOIN public.expense_categories c ON c.id = e.category_id
     WHERE NOT e.is_deleted
       AND (p_from IS NULL OR e.expense_date >= p_from) AND (p_to IS NULL OR e.expense_date <= p_to)
     GROUP BY 1,2,3,4
  ) x;

  -- บิลที่ไม่ถูกนับ (เพื่อความโปร่งใส)
  SELECT jsonb_build_object(
    'cancelled_n', COUNT(*) FILTER (WHERE status = 'cancelled'),
    'cancelled_amt', COALESCE(SUM(grand_total) FILTER (WHERE status = 'cancelled'),0),
    'unpaid_excluded_n', CASE WHEN p_include_unpaid THEN 0 ELSE COUNT(*) FILTER (WHERE status IN ('draft','sent')) END,
    'unpaid_excluded_amt', CASE WHEN p_include_unpaid THEN 0 ELSE COALESCE(SUM(grand_total) FILTER (WHERE status IN ('draft','sent')),0) END
  ) INTO v_excluded FROM public._acct_bill_rows(p_from, p_to);

  -- ตรวจความถูกต้องของข้อมูลก่อนใช้ตัวเลข
  WITH _b AS (SELECT * FROM public._acct_bill_rows(p_from, p_to))
  SELECT COALESCE(jsonb_agg(i ORDER BY i.sev, i.po_no), '[]'::jsonb) INTO v_issues FROM (
    SELECT 1 AS sev, 'items_mismatch' AS code, order_id, po_no, month,
           jsonb_build_object('bill', grand_total, 'items', items_amt, 'diff', grand_total - items_amt) AS info
      FROM _b WHERE status <> 'cancelled' AND n_items > 0 AND ABS(grand_total - items_amt) > 1
    UNION ALL
    SELECT 1, 'kg_mismatch', order_id, po_no, month, jsonb_build_object('bill', total_qty, 'items', rubber_kg)
      FROM _b WHERE status <> 'cancelled' AND n_items > 0 AND ABS(total_qty - rubber_kg) > 0.01
    UNION ALL
    SELECT 1, 'no_items', order_id, po_no, month, jsonb_build_object('bill', grand_total)
      FROM _b WHERE status <> 'cancelled' AND n_items = 0
    UNION ALL
    SELECT 1, 'receipt_amount_mismatch', order_id, po_no, month,
           jsonb_build_object('bill', grand_total, 'receipts', receipt_amt, 'receipt_nos', receipt_nos)
      FROM _b WHERE status = 'paid' AND n_receipts > 0 AND ABS(grand_total - receipt_amt) > 1
    UNION ALL
    SELECT 1, 'multiple_receipts', order_id, po_no, month, jsonb_build_object('n', n_receipts, 'receipt_nos', receipt_nos)
      FROM _b WHERE n_receipts > 1
    UNION ALL
    SELECT 1, 'receipt_on_unpaid', order_id, po_no, month, jsonb_build_object('status', status, 'receipt_nos', receipt_nos)
      FROM _b WHERE status <> 'paid' AND n_receipts > 0
    UNION ALL
    SELECT 2, 'paid_without_receipt', order_id, po_no, month, jsonb_build_object('bill', grand_total)
      FROM _b WHERE status = 'paid' AND n_receipts = 0
    UNION ALL
    SELECT 2, 'paid_without_date', order_id, po_no, month, '{}'::jsonb
      FROM _b WHERE status = 'paid' AND paid_at IS NULL
    UNION ALL
    SELECT 2, 'zero_amount', order_id, po_no, month, jsonb_build_object('bill', grand_total, 'kg', total_qty)
      FROM _b WHERE status <> 'cancelled' AND (grand_total <= 0 OR total_qty <= 0)
    UNION ALL
    SELECT 3, 'bill_date_missing', order_id, po_no, month, '{}'::jsonb
      FROM _b WHERE date_missing AND status <> 'cancelled'
    UNION ALL
    SELECT 2, 'sale_amount_mismatch', 'sale:'||s.id, COALESCE(NULLIF(s.doc_no,''), 'ขาย #'||s.id), to_char(s.sale_date,'YYYY-MM'),
           jsonb_build_object('amount', s.amount, 'qty_x_price', ROUND(s.qty_kg * s.price_per_kg, 2))
      FROM public.rubber_sales s
     WHERE NOT s.is_deleted AND ABS(s.amount - s.qty_kg * s.price_per_kg) > 1
       AND (p_from IS NULL OR s.sale_date >= p_from) AND (p_to IS NULL OR s.sale_date <= p_to)
    LIMIT 500
  ) i;

  RETURN jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'include_unpaid', p_include_unpaid,
                            'generated_at', now(), 'months', v_months, 'totals', v_totals,
                            'expense_by_category', v_cats, 'excluded', v_excluded, 'issues', v_issues);
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 7) RPC: รายการบิลต้นทาง (ย้อนกลับจากยอดสรุป)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.acct_bills(p_token TEXT, p_from DATE, p_to DATE, p_include_unpaid BOOLEAN DEFAULT true)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v JSONB;
BEGIN
  PERFORM public._require_admin(p_token);
  SELECT COALESCE(jsonb_agg(to_jsonb(b) ORDER BY b.bill_date DESC, b.po_no DESC), '[]'::jsonb) INTO v
    FROM public._acct_bill_rows(p_from, p_to) b
   WHERE p_include_unpaid OR b.status IN ('paid','cancelled');
  RETURN jsonb_build_object('ok', true, 'bills', v);
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 8) สิทธิ์ฟังก์ชัน
-- ─────────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public._acct_stamp()                    FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._acct_audit()                    FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._bill_date(public.orders)        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._acct_bill_rows(DATE, DATE)      FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.request_staff_role()             TO anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.request_staff_user()             TO anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.acct_report(TEXT, DATE, DATE, BOOLEAN) TO anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.acct_bills(TEXT, DATE, DATE, BOOLEAN)  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
