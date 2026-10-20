-- =====================================================================
-- RubberLedger — ขั้นที่ 2: ปิดตารางบิลจากคนนอก (RLS ตาม staff token)
-- วันที่: 2026-10-20
--
-- ต้องรัน 01-security-staff-auth.sql ก่อน และทุกเครื่องต้องใช้หน้าเว็บเวอร์ชันใหม่แล้ว
-- (เวอร์ชันใหม่ส่ง header x-staff-token ทุกคำขอหลังล็อกอิน)
--
-- หลังรัน: คำขอที่ไม่มี token ของพนักงานที่ยังใช้งานอยู่ จะอ่าน/เขียนตารางเหล่านี้ไม่ได้
--   orders, order_items, receipts, customers, app_data, activity_logs
--
-- ⚠ ผลข้างเคียงที่ต้องรู้:
--   Supabase Realtime จะไม่ส่ง event ของตารางเหล่านี้ให้หน้าเว็บอีก
--   (Realtime ไม่ได้รับ header นี้) หน้าเว็บจะใช้การดึงข้อมูลทุก 10 วินาทีแทนโดยอัตโนมัติ
--   บิลใหม่จากเครื่องอื่นจะขึ้นช้าสุดประมาณ 10 วินาที
--
-- พอร์ทัลลูกค้าไม่ได้รับผลกระทบ (ใช้ฟังก์ชัน SECURITY DEFINER)
-- ถ้าต้องการย้อนกลับ ดูส่วน ROLLBACK ท้ายไฟล์
-- =====================================================================

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

-- =====================================================================
-- ทดสอบหลังรัน: เปิดหน้าเว็บแบบไม่ล็อกอิน แล้วใน console พิมพ์
--   await _sb.from('orders').select('id').limit(1)
-- ต้องได้ data: [] (ว่าง) — ถ้ายังเห็นข้อมูล แปลว่ายังมี policy อื่นเปิดอยู่
-- =====================================================================

-- ROLLBACK (กรณีฉุกเฉิน เปิดกลับแบบเดิม):
-- DO $$ DECLARE t TEXT; BEGIN
--   FOREACH t IN ARRAY ARRAY['orders','order_items','receipts','customers','app_data','activity_logs'] LOOP
--     EXECUTE format('DROP POLICY IF EXISTS staff_token_all ON public.%I', t);
--     EXECUTE format('CREATE POLICY open_all ON public.%I FOR ALL TO anon USING (true) WITH CHECK (true)', t);
--   END LOOP; END $$;
