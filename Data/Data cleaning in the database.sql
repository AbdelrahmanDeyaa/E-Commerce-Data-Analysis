-- ========================================
-- 🔹 فحص القيم المفقودة لكل الأعمدة في جدول واحد مباشرة
-- ========================================
CREATE TEMP TABLE missing_summary (
    ColumnName text,
    TotalRows bigint,
    MissingCount bigint
);

DO $$
DECLARE
    col RECORD;
    sql TEXT;
BEGIN
    FOR col IN
        SELECT column_name
        FROM information_schema.columns
        WHERE table_name = 'sales'
    LOOP
        sql := format(
            'INSERT INTO missing_summary SELECT ''%s'', COUNT(*), COUNT(*) FILTER (WHERE %I IS NULL) FROM sales;',
            col.column_name, col.column_name
        );
        EXECUTE sql;
    END LOOP;
END
$$;

-- ========================================
-- 🔹 عرض الجدول النهائي للقيم المفقودة
-- ========================================
SELECT * FROM missing_summary;

-- ========================================
-- 🔹 تنظيف عمود Description
-- تحويل النصوص الفارغة أو التي تحتوي على مسافات فقط إلى NULL
-- ========================================
UPDATE sales
SET Description = NULL
WHERE BTRIM(Description) = '';

-- ========================================
-- 🔹 استبدال القيم المفقودة في Description بكلمة توضيحية
-- ========================================
UPDATE sales
SET Description = 'Unknown Description'
WHERE Description IS NULL;

-- ========================================
-- 🔹 تنظيف عمود CustomerID
-- وسم العملاء غير المعروفين بالقيمة 0
-- ========================================
UPDATE sales
SET CustomerID = 0
WHERE CustomerID IS NULL;

-- ========================================
-- 🔹 تنظيف عمود Quantity
-- 1) عرض الصفوف غير صالحة: سالبة، كسور عشرية، أو نصوص
-- ========================================
SELECT *
FROM sales
WHERE Quantity::TEXT !~ '^\d+$' OR Quantity <= 0 OR Quantity <> FLOOR(Quantity::NUMERIC);

-- ========================================
-- 2) حفظ الصفوف السيئة في جدول استثناءات قبل التعديل أو الحذف
-- ========================================
CREATE TABLE IF NOT EXISTS sales_bad_quantity AS
SELECT *
FROM sales
WHERE Quantity::TEXT !~ '^\d+$' OR Quantity <= 0 OR Quantity <> FLOOR(Quantity::NUMERIC)
LIMIT 0;  -- إنشاء الجدول فارغ أولاً

INSERT INTO sales_bad_quantity
SELECT *
FROM sales
WHERE Quantity::TEXT !~ '^\d+$' OR Quantity <= 0 OR Quantity <> FLOOR(Quantity::NUMERIC);

-- ========================================
-- 3) حذف الصفوف الغير صالحة من الجدول الأساسي
-- ========================================
DELETE FROM sales
WHERE Quantity::TEXT !~ '^\d+$' OR Quantity <= 0;

-- ========================================
-- 4) تقريب أي كسور عشرية في Quantity إلى أقرب عدد صحيح
-- ========================================
UPDATE sales
SET Quantity = ROUND(Quantity::NUMERIC,0)
WHERE Quantity <> FLOOR(Quantity::NUMERIC);

-- ========================================
-- 🔹 تنظيف عمود UnitPrice
-- التأكد أن العمود من نوع NUMERIC(10,2) لقبول الكسور
-- ========================================
ALTER TABLE sales
ALTER COLUMN UnitPrice TYPE NUMERIC(10,2);

-- ========================================
-- 🔹 إنشاء جدول لحفظ أي صفوف أخرى غير منطقية (Quantity أو UnitPrice ≤ 0)
-- ========================================
CREATE TABLE IF NOT EXISTS sales_bad_rows AS
SELECT *
FROM sales
WHERE 1=0;  -- إنشاء الجدول فارغ أولاً

INSERT INTO sales_bad_rows
SELECT *
FROM sales
WHERE Quantity <= 0 OR UnitPrice <= 0;

-- حذف هذه الصفوف من الجدول الأساسي
DELETE FROM sales
WHERE Quantity <= 0 OR UnitPrice <= 0;

-- ========================================
-- 🔹 التحقق من تواريخ InvoiceDate
-- عرض أي تواريخ غير صالحة للتحويل
-- ========================================
SELECT *
FROM sales
WHERE TO_CHAR(InvoiceDate, 'YYYY-MM-DD') !~ '^\d{4}-\d{2}-\d{2}$';

-- ========================================
-- 🔹 إنشاء نسخة نهائية نظيفة من الجدول
-- هذا الجدول سيكون جاهز للتصدير إلى Excel أو التحليل
-- ========================================
DROP TABLE IF EXISTS sales_clean;

CREATE TABLE sales_clean AS
SELECT *
FROM sales;

-- ========================================
-- 🔹 فحص سريع بعد التنظيف
-- التأكد من عدم وجود قيم مفقودة أو صفوف غير منطقية
-- ========================================
SELECT COUNT(*) AS NullCustomerID
FROM sales_clean
WHERE CustomerID IS NULL;

SELECT COUNT(*) AS NullDescription
FROM sales_clean
WHERE Description IS NULL;

SELECT COUNT(*) AS InvalidQuantity
FROM sales_clean
WHERE Quantity <= 0 OR Quantity <> FLOOR(Quantity::NUMERIC);

SELECT COUNT(*) AS InvalidUnitPrice
FROM sales_clean
WHERE UnitPrice <= 0;
