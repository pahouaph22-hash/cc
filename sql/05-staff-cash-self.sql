-- =====================================================================
-- RubberLedger — ขั้นที่ 5: พนักงานบันทึกเงินที่ได้รับเอง + แหล่งที่มา + การยืนยันโดยแอดมิน
-- วันที่: 2026-10-25     ต้องรัน 04-staff-ledger.sql ก่อน     รันซ้ำได้
--
--  • พนักงานจ่ายเงินบันทึก "เงินที่ได้รับ" / "ส่งเงินคืน" ของตัวเองได้ พร้อมแหล่งที่มา วิธีรับ เลขอ้างอิง
--  • รายการที่พนักงานบันทึกเอง = "รอยืนยัน" → แก้/ลบได้จนกว่าแอดมินยืนยัน แล้วจะถูกล็อก
--  • แอดมินบันทึกแทนได้ และกดยืนยันได้ (ผู้ยืนยัน/เวลา บันทึกจากระบบ ปลอมไม่ได้)
-- =====================================================================

ALTER TABLE public.staff_cash_moves
  ADD COLUMN IF NOT EXISTS source      TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS ref_no      TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS verified_by TEXT;

-- รายการเดิมที่แอดมินบันทึกไว้ก่อนมีระบบยืนยัน ถือว่ายืนยันแล้ว
UPDATE public.staff_cash_moves m SET verified_at = m.created_at, verified_by = m.created_by
 WHERE m.verified_at IS NULL
   AND EXISTS (SELECT 1 FROM public.accounts a WHERE a.username = m.created_by AND a.role = 'admin');

-- ─────────────────────────────────────────────────────────────────────
-- Trigger: เจ้าของรายการ + การยืนยัน
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._cash_move_rules()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE r TEXT := public.request_staff_role(); u TEXT := public.request_staff_user();
BEGIN
  IF r IS NOT NULL AND r <> 'admin' THEN
    -- พนักงาน: ได้เฉพาะของตัวเอง, ยืนยันตัวเองไม่ได้, แก้รายการที่ยืนยันแล้วไม่ได้
    IF TG_OP = 'UPDATE' THEN
      IF OLD.staff_username IS DISTINCT FROM u THEN RAISE EXCEPTION 'not_owner' USING ERRCODE = '42501'; END IF;
      IF OLD.verified_at IS NOT NULL THEN RAISE EXCEPTION 'already_verified' USING ERRCODE = '42501'; END IF;
    END IF;
    NEW.staff_username := u;
    NEW.verified_at := NULL; NEW.verified_by := NULL;
  ELSE
    -- แอดมิน: รายการที่แอดมินบันทึกเอง = ยืนยันแล้วทันที; ยืนยัน/ยกเลิกยืนยันได้ — ผู้ยืนยันและเวลามาจากระบบ
    IF TG_OP = 'INSERT' THEN
      NEW.verified_at := now(); NEW.verified_by := COALESCE(u, current_user::text);
    ELSIF NEW.verified_at IS NOT NULL AND OLD.verified_at IS NULL THEN
      NEW.verified_at := now(); NEW.verified_by := COALESCE(u, current_user::text);
    ELSIF NEW.verified_at IS NULL THEN
      NEW.verified_by := NULL;
    ELSIF TG_OP = 'UPDATE' THEN
      NEW.verified_at := OLD.verified_at; NEW.verified_by := OLD.verified_by;
    END IF;
  END IF;
  NEW.source := COALESCE(TRIM(NEW.source), ''); NEW.ref_no := COALESCE(TRIM(NEW.ref_no), '');
  RETURN NEW;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_staff_cash_moves_rules') THEN
    CREATE TRIGGER trg_staff_cash_moves_rules BEFORE INSERT OR UPDATE ON public.staff_cash_moves
      FOR EACH ROW EXECUTE FUNCTION public._cash_move_rules();
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- สิทธิ์: พนักงานจ่ายเงินเพิ่ม/แก้ รายการของตัวเองที่ยังไม่ยืนยัน
-- ─────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff_cash_moves' AND policyname='staff_own_insert') THEN
    CREATE POLICY staff_own_insert ON public.staff_cash_moves FOR INSERT TO anon, authenticated
      WITH CHECK (public.request_staff_role() = 'staff_cashier' AND staff_username = public.request_staff_user() AND verified_at IS NULL);
    CREATE POLICY staff_own_update ON public.staff_cash_moves FOR UPDATE TO anon, authenticated
      USING (public.request_staff_role() = 'staff_cashier' AND staff_username = public.request_staff_user() AND verified_at IS NULL)
      WITH CHECK (public.request_staff_role() = 'staff_cashier' AND staff_username = public.request_staff_user() AND verified_at IS NULL);
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- รายการเคลื่อนไหว v2: เพิ่มข้อมูลครบทุกช่องของต้นทาง (meta) สำหรับหน้ารายละเอียด
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._staff_lines_v2(v_user TEXT)
RETURNS TABLE (
  ev_date DATE, ev_ts TIMESTAMPTZ, kind TEXT, ref TEXT, ref2 TEXT, party TEXT, detail TEXT,
  kg NUMERIC, price_min NUMERIC, price_max NUMERIC, method TEXT, location TEXT,
  amount_in NUMERIC, amount_out NUMERIC, src_table TEXT, src_id TEXT, order_status TEXT, bill_total NUMERIC,
  verified BOOLEAN, meta JSONB
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
SELECT m.move_date, m.created_at, m.kind,
       'CM-' || m.id, NULLIF(m.ref_no,''), NULLIF(m.source,''), COALESCE(m.note,''),
       NULL, NULL, NULL, m.method, NULL,
       CASE WHEN m.kind = 'advance' THEN m.amount ELSE 0 END,
       CASE WHEN m.kind = 'return'  THEN m.amount ELSE 0 END,
       'staff_cash_moves', m.id::text, NULL, NULL,
       (m.verified_at IS NOT NULL),
       jsonb_build_object('move_date', m.move_date, 'kind', m.kind, 'amount', m.amount, 'source', m.source,
                          'method', m.method, 'ref_no', m.ref_no, 'note', m.note,
                          'created_by', m.created_by, 'created_at', m.created_at,
                          'updated_by', m.updated_by, 'updated_at', m.updated_at,
                          'verified_by', m.verified_by, 'verified_at', m.verified_at)
  FROM public.staff_cash_moves m
 WHERE m.staff_username = v_user AND NOT m.is_deleted
UNION ALL
SELECT (r.issued_at AT TIME ZONE 'Asia/Vientiane')::date, r.issued_at, 'payment',
       r.receipt_no, o.po_no, COALESCE(o.customer, r.customer), COALESCE(r.note,''),
       COALESCE(o.total_qty, r.total_qty),
       (SELECT MIN(i.price) FROM public.order_items i WHERE i.order_id = o.id AND i.product_id = 'RUBBER'),
       (SELECT MAX(i.price) FROM public.order_items i WHERE i.order_id = o.id AND i.product_id = 'RUBBER'),
       r.pay_method, r.work_location,
       0, COALESCE(r.amount, 0),
       'orders', r.order_id, o.status, o.grand_total,
       NULL,
       jsonb_build_object('receipt_no', r.receipt_no, 'po_no', o.po_no, 'customer', COALESCE(o.customer, r.customer),
                          'bill_date', o.date, 'kg', COALESCE(o.total_qty, r.total_qty), 'amount', r.amount,
                          'bill_total', o.grand_total, 'pay_method', r.pay_method, 'issued_at', r.issued_at,
                          'issued_by', r.issued_by, 'issued_by_name', r.issued_by_name, 'paid_by', o.paid_by,
                          'location', r.work_location, 'note', r.note, 'bill_note', o.note,
                          'created_by', o.created_by, 'status', o.status,
                          'items', (SELECT COALESCE(jsonb_agg(jsonb_build_object('product', i.product_id, 'qty',
                                       CASE WHEN i.product_id = 'SHIPPING' THEN o.total_qty ELSE i.qty END,
                                       'price', i.price) ORDER BY i.sort_order), '[]'::jsonb)
                                      FROM public.order_items i WHERE i.order_id = o.id))
  FROM public.receipts r LEFT JOIN public.orders o ON o.id = r.order_id
 WHERE r.issued_by = v_user
UNION ALL
SELECT e.expense_date, e.created_at, 'expense',
       'EX-' || e.id, c.name, NULL, e.description || CASE WHEN COALESCE(e.note,'') <> '' THEN ' — ' || e.note ELSE '' END,
       NULL, NULL, NULL, NULL, NULL,
       0, e.amount, 'expenses', e.id::text, NULL, NULL,
       NULL,
       jsonb_build_object('expense_date', e.expense_date, 'category', c.name, 'description', e.description,
                          'amount', e.amount, 'note', e.note,
                          'created_by', e.created_by, 'created_at', e.created_at,
                          'updated_by', e.updated_by, 'updated_at', e.updated_at)
  FROM public.expenses e LEFT JOIN public.expense_categories c ON c.id = e.category_id
 WHERE e.staff_username = v_user AND NOT e.is_deleted
$$;

CREATE OR REPLACE FUNCTION public.staff_ledger(p_token TEXT, p_username TEXT, p_from DATE, p_to DATE)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  me public.accounts%ROWTYPE; who public.accounts%ROWTYPE;
  v_user TEXT; v_has_cash BOOLEAN; v_opening NUMERIC;
  v_lines JSONB; v_daily JSONB; v_sum JSONB; v_issues JSONB; v_methods JSONB; v_sources JSONB;
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
    FROM public._staff_lines_v2(v_user) WHERE p_from IS NOT NULL AND ev_date < p_from;

  WITH ordered AS (
    SELECT l.*, SUM(amount_in - amount_out) OVER (ORDER BY ev_date, ev_ts, kind, ref ROWS UNBOUNDED PRECEDING) AS running
      FROM public._staff_lines_v2(v_user) l
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'date', ev_date, 'ts', ev_ts, 'kind', kind, 'ref', ref, 'ref2', ref2, 'party', party, 'detail', detail,
           'kg', kg, 'price_min', price_min, 'price_max', price_max, 'method', method, 'location', location,
           'in', amount_in, 'out', amount_out,
           'balance', CASE WHEN v_has_cash THEN running END,
           'src_table', src_table, 'src_id', src_id, 'order_status', order_status, 'bill_total', bill_total,
           'verified', verified, 'meta', meta)
         ORDER BY ev_date, ev_ts, kind, ref), '[]'::jsonb)
    INTO v_lines
    FROM ordered
   WHERE (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to);

  SELECT COALESCE(jsonb_agg(d ORDER BY d.date), '[]'::jsonb) INTO v_daily FROM (
    SELECT ev_date AS date,
           SUM(amount_in)                                    AS cash_in,
           SUM(amount_out) FILTER (WHERE kind = 'payment')   AS paid_out,
           COUNT(*)        FILTER (WHERE kind = 'payment')   AS n_payments,
           SUM(kg)         FILTER (WHERE kind = 'payment')   AS kg,
           SUM(amount_out) FILTER (WHERE kind = 'expense')   AS expense_out,
           SUM(amount_out) FILTER (WHERE kind = 'return')    AS returned,
           SUM(amount_in - amount_out)                       AS net
      FROM public._staff_lines_v2(v_user)
     WHERE (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to)
     GROUP BY ev_date
  ) d;

  SELECT jsonb_build_object(
    'opening',     CASE WHEN v_has_cash THEN v_opening END,
    'cash_in',     COALESCE(SUM(amount_in),0),
    'n_advances',  COUNT(*) FILTER (WHERE kind = 'advance'),
    'unverified_in', COALESCE(SUM(amount_in) FILTER (WHERE kind = 'advance' AND NOT verified),0),
    'n_unverified',  COUNT(*) FILTER (WHERE src_table = 'staff_cash_moves' AND NOT verified),
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
    FROM public._staff_lines_v2(v_user)
   WHERE (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to);

  SELECT COALESCE(jsonb_object_agg(method, amt), '{}'::jsonb) INTO v_methods FROM (
    SELECT COALESCE(method,'cash') AS method, SUM(amount_out) AS amt
      FROM public._staff_lines_v2(v_user) WHERE kind = 'payment'
       AND (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to)
     GROUP BY 1
  ) x;

  -- เงินที่ได้รับ แยกตามแหล่งที่มา
  SELECT COALESCE(jsonb_agg(x ORDER BY x.amount DESC), '[]'::jsonb) INTO v_sources FROM (
    SELECT COALESCE(party, '') AS source, SUM(amount_in) AS amount, COUNT(*) AS n
      FROM public._staff_lines_v2(v_user) WHERE kind = 'advance'
       AND (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to)
     GROUP BY 1
  ) x;

  SELECT COALESCE(jsonb_agg(i), '[]'::jsonb) INTO v_issues FROM (
    SELECT 'receipt_amount_mismatch' AS code, ref, ref2, src_id,
           jsonb_build_object('receipt', amount_out, 'bill', bill_total) AS info
      FROM public._staff_lines_v2(v_user) WHERE kind = 'payment' AND bill_total IS NOT NULL AND ABS(amount_out - bill_total) > 1
       AND (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to)
    UNION ALL
    SELECT 'receipt_order_not_paid', ref, ref2, src_id, jsonb_build_object('status', COALESCE(order_status, 'missing'))
      FROM public._staff_lines_v2(v_user) WHERE kind = 'payment' AND COALESCE(order_status,'missing') <> 'paid'
       AND (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to)
    UNION ALL
    SELECT 'multiple_receipts', MIN(ref), MIN(ref2), src_id, jsonb_build_object('n', COUNT(*))
      FROM public._staff_lines_v2(v_user) WHERE kind = 'payment' AND src_id IS NOT NULL
       AND (p_from IS NULL OR ev_date >= p_from) AND (p_to IS NULL OR ev_date <= p_to)
     GROUP BY src_id HAVING COUNT(*) > 1
  ) i;

  RETURN jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'generated_at', now(),
    'staff', jsonb_build_object('username', v_user, 'display_name', COALESCE(who.display_name, v_user), 'role', who.role),
    'summary', v_sum, 'by_method', v_methods, 'by_source', v_sources,
    'daily', v_daily, 'lines', v_lines, 'issues', v_issues);
END $$;

REVOKE EXECUTE ON FUNCTION public._cash_move_rules()     FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._staff_lines_v2(TEXT)  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.staff_ledger(TEXT, TEXT, DATE, DATE) TO anon, authenticated;
NOTIFY pgrst, 'reload schema';
