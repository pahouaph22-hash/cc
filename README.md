# RubberLedger — KUBTHOR

ระบบบันทึกการรับซื้อยางพารา (PWA) + พอร์ทัลลูกค้า ทำงานบน GitHub Pages + Supabase

| ไฟล์ | หน้าที่ |
|---|---|
| `rubber-ledger.html` | แอปหลักสำหรับพนักงาน/แอดมิน |
| `index.html` | ส่งต่อไป `rubber-ledger.html` (เวอร์ชันเก่าอยู่ในประวัติ git) |
| `customer-portal.html` | พอร์ทัลลูกค้า |
| `kubthor-frontend.html` | หน้าเว็บ KUBTHOR |
| `sw.js`, `manifest.json`, `icons/` | ใช้งานออฟไลน์ + ติดตั้งเป็นแอป |
| `customer-portal-schema.sql` | ฐานข้อมูลพอร์ทัลลูกค้า |
| `sql/01-security-staff-auth.sql` | ความปลอดภัยบัญชีพนักงาน, ฟังก์ชันแอดมิน, เลขใบเสร็จ |
| `sql/02-lock-business-tables.sql` | ปิดตารางบิลจากคนนอก (RLS) |

## อัปเกรดความปลอดภัย (ทำตามลำดับ)

1. Deploy หน้าเว็บเวอร์ชันนี้ขึ้น GitHub Pages ก่อน — ใช้ได้ทั้งกับฐานข้อมูลเดิมและฐานข้อมูลที่อัปเกรดแล้ว
2. Supabase → SQL Editor → รัน `sql/01-security-staff-auth.sql` ทั้งไฟล์
3. ล็อกอินแอดมิน → ตั้งค่า → 🔧 ตรวจสอบระบบ ต้องขึ้น “โหมดปลอดภัย”
4. เปลี่ยนรหัสแอดมินด้วยปุ่ม 🔑 มุมขวาบน
5. ให้ทุกเครื่องรีเฟรชแอปหนึ่งครั้ง แล้วรัน `sql/02-lock-business-tables.sql`

หลังรันไฟล์ 01: รหัสผ่านทุกบัญชีถูกเข้ารหัส (bcrypt) ใช้รหัสเดิมเข้าได้ตามปกติ
