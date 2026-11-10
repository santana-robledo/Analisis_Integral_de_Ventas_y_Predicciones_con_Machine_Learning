/* ============================================================
   PROYECTO: ANÁLISIS DE VENTAS - EMPRESA ALIADA
   Autor: Josue Santana Robled
   Fecha: 2026-11-05
   Base de datos: DWH_Ventas_Aliada
   ============================================================ */

-- ============================================================
-- PASO 1: CREACIÓN DE LA BASE DE DATOS
-- ============================================================
USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'DWH_Ventas_Aliada')
    DROP DATABASE DWH_Ventas_Aliada;
GO

CREATE DATABASE DWH_Ventas_Aliada;
GO

USE DWH_Ventas_Aliada;
GO

-- ============================================================
-- PASO 2: DEFINICIÓN DE LA ESTRUCTURA DE LAS TABLAS
-- ============================================================

-- 2.1 DIM_CATEGORY
CREATE TABLE DIM_CATEGORY (
    ID_CATEGORY INT NOT NULL PRIMARY KEY,
    CATEGORY    NVARCHAR(100) NOT NULL
);
GO

-- 2.2 DIM_PRODUCT
CREATE TABLE DIM_PRODUCT (
    MANUFACTURER      NVARCHAR(150) NULL,
    BRAND             NVARCHAR(150) NULL,
    ITEM              NVARCHAR(50)  NOT NULL PRIMARY KEY,
    ITEM_DESCRIPTION  NVARCHAR(500) NULL,
    CATEGORY          INT           NULL,     -- FK -> DIM_CATEGORY.ID_CATEGORY
    FORMAT            NVARCHAR(50)  NULL,
    ATTR1             NVARCHAR(100) NULL,
    ATTR2             NVARCHAR(100) NULL,
    ATTR3             NVARCHAR(100) NULL,
    CONSTRAINT FK_PRODUCT_CATEGORY
        FOREIGN KEY (CATEGORY) REFERENCES DIM_CATEGORY(ID_CATEGORY)
);
GO

-- 2.3 DIM_SEGMENT
CREATE TABLE DIM_SEGMENT (
    CATEGORY   INT           NULL,
    ATTR1      NVARCHAR(100) NULL,
    ATTR2      NVARCHAR(100) NULL,
    ATTR3      NVARCHAR(100) NULL,
    FORMAT     NVARCHAR(50)  NULL,
    SEGMENT    NVARCHAR(50)  NOT NULL
);
GO

-- 2.4 DIM_CALENDAR
CREATE TABLE DIM_CALENDAR (
    WEEK         NVARCHAR(10) NOT NULL PRIMARY KEY,  -- ej. '01-21'
    [YEAR]       INT          NOT NULL,
    [MONTH]      INT          NOT NULL,
    WEEK_NUMBER  INT          NOT NULL,
    [DATE]       DATE         NOT NULL
);
GO

-- 2.5 FACT_SALES
CREATE TABLE FACT_SALES (
    WEEK                        NVARCHAR(10)   NOT NULL,
    ITEM_CODE                   NVARCHAR(50)   NOT NULL,
    TOTAL_UNIT_SALES            DECIMAL(18,4)  NULL,
    TOTAL_VALUE_SALES           DECIMAL(18,4)  NULL,
    TOTAL_UNIT_AVG_WEEKLY_SALES DECIMAL(18,4)  NULL,
    REGION                      NVARCHAR(100)  NULL,
    CONSTRAINT FK_SALES_CALENDAR
        FOREIGN KEY (WEEK) REFERENCES DIM_CALENDAR(WEEK),
    CONSTRAINT FK_SALES_PRODUCT
        FOREIGN KEY (ITEM_CODE) REFERENCES DIM_PRODUCT(ITEM)
);
GO


-- ============================================================
-- PASO 3: IMPORTACIÓN VÍA IMPORT FLAT FILE WIZARD
-- ============================================================


-- ============================================================
-- PASO 4: TRANSFERENCIA DE TABLAS _IMP A TABLAS FINALES
-- ============================================================

USE DWH_Ventas_Aliada;
GO

-- 4.1 DIM_CATEGORY
INSERT INTO DIM_CATEGORY (ID_CATEGORY, CATEGORY)
SELECT i.ID_CATEGORY, i.CATEGORY
FROM DIM_CATEGORY_IMP i
WHERE NOT EXISTS (SELECT 1 FROM DIM_CATEGORY d WHERE d.ID_CATEGORY = i.ID_CATEGORY);
GO

-- 4.2 DIM_CALENDAR
INSERT INTO DIM_CALENDAR (WEEK, [YEAR], [MONTH], WEEK_NUMBER, [DATE])
SELECT i.WEEK, i.[YEAR], i.[MONTH], i.WEEK_NUMBER,
       COALESCE(TRY_CONVERT(DATE, i.[DATE]),
                TRY_CONVERT(DATE, i.[DATE], 103))
FROM DIM_CALENDAR_IMP i
WHERE COALESCE(TRY_CONVERT(DATE, i.[DATE]),
               TRY_CONVERT(DATE, i.[DATE], 103)) IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DIM_CALENDAR d WHERE d.WEEK = i.WEEK);
GO

-- 4.3 DIM_PRODUCT
INSERT INTO DIM_PRODUCT
    (MANUFACTURER, BRAND, ITEM, ITEM_DESCRIPTION, CATEGORY, FORMAT, ATTR1, ATTR2, ATTR3)
SELECT i.MANUFACTURER, i.BRAND, i.ITEM, i.ITEM_DESCRIPTION,
       i.CATEGORY, i.FORMAT, i.ATTR1, i.ATTR2, i.ATTR3
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY ITEM ORDER BY (SELECT NULL)) AS rn
    FROM DIM_PRODUCT_IMP
) i
WHERE i.rn = 1
  AND NOT EXISTS (SELECT 1 FROM DIM_PRODUCT d WHERE d.ITEM = i.ITEM);
GO

-- 4.4 DIM_SEGMENT
DELETE FROM DIM_SEGMENT;
GO

INSERT INTO DIM_SEGMENT (CATEGORY, ATTR1, ATTR2, ATTR3, FORMAT, SEGMENT)
SELECT CATEGORY, ATTR1, ATTR2, ATTR3, FORMAT, SEGMENT
FROM DIM_SEGMENT_IMP;
GO

-- 4.5 FACT_SALES
ALTER TABLE FACT_SALES NOCHECK CONSTRAINT ALL;
GO

TRUNCATE TABLE FACT_SALES;
GO

INSERT INTO FACT_SALES
    (WEEK, ITEM_CODE, TOTAL_UNIT_SALES, TOTAL_VALUE_SALES,
     TOTAL_UNIT_AVG_WEEKLY_SALES, REGION)
SELECT
    LTRIM(RTRIM(REPLACE(WEEK, '"', ''))),
    LTRIM(RTRIM(REPLACE(ITEM_CODE, '"', ''))),
    TRY_CAST(REPLACE(TOTAL_UNIT_SALES, '"', '') AS DECIMAL(18,4)),
    TRY_CAST(REPLACE(TOTAL_VALUE_SALES, '"', '') AS DECIMAL(18,4)),
    TRY_CAST(REPLACE(TOTAL_UNIT_AVG_WEEKLY_SALES, '"', '') AS DECIMAL(18,4)),
    LTRIM(RTRIM(REPLACE(REGION, '"', '')))
FROM FACT_SALES_IMP
WHERE LTRIM(RTRIM(REPLACE(WEEK, '"', ''))) <> ''
  AND LTRIM(RTRIM(REPLACE(ITEM_CODE, '"', ''))) <> '';
GO

ALTER TABLE FACT_SALES CHECK CONSTRAINT ALL;
GO


-- ============================================================
-- PASO 5: VALIDACIONES
-- ============================================================

-- 5.1 Conteo de filas por tabla
SELECT 'DIM_CATEGORY' AS Tabla, COUNT(*) AS Filas FROM DIM_CATEGORY
UNION ALL SELECT 'DIM_PRODUCT',  COUNT(*) FROM DIM_PRODUCT
UNION ALL SELECT 'DIM_SEGMENT',  COUNT(*) FROM DIM_SEGMENT
UNION ALL SELECT 'DIM_CALENDAR', COUNT(*) FROM DIM_CALENDAR
UNION ALL SELECT 'FACT_SALES',   COUNT(*) FROM FACT_SALES
ORDER BY Tabla;
GO

-- 5.3 Nulos en métricas
SELECT
    COUNT(*) AS Total,
    SUM(CASE WHEN TOTAL_UNIT_SALES IS NULL THEN 1 ELSE 0 END) AS Unit_Null,
    SUM(CASE WHEN TOTAL_VALUE_SALES IS NULL THEN 1 ELSE 0 END) AS Value_Null,
    SUM(CASE WHEN TOTAL_UNIT_AVG_WEEKLY_SALES IS NULL THEN 1 ELSE 0 END) AS Avg_Null
FROM FACT_SALES;
GO

-- ============================================================
-- PASO 6: CONSULTAS BÁSICAS 
-- ============================================================
SELECT TOP 10 * FROM DIM_CATEGORY;
SELECT TOP 10 * FROM DIM_PRODUCT;
SELECT TOP 10 * FROM DIM_SEGMENT;
SELECT TOP 10 * FROM DIM_CALENDAR;
SELECT TOP 10 * FROM FACT_SALES;
GO

-- ============================================================
-- PASO 7: UNIONES
-- ============================================================

-- 7.1 Ventas por categoría
SELECT
    dc.CATEGORY,
    SUM(f.TOTAL_UNIT_SALES)  AS Unidades_Vendidas,
    SUM(f.TOTAL_VALUE_SALES) AS Valor_Total,
    COUNT(DISTINCT f.ITEM_CODE) AS Productos_Distintos
FROM FACT_SALES f
INNER JOIN DIM_PRODUCT p  ON f.ITEM_CODE = p.ITEM
INNER JOIN DIM_CATEGORY dc ON p.CATEGORY = dc.ID_CATEGORY
GROUP BY dc.CATEGORY
ORDER BY Valor_Total DESC;
GO

-- 7.2 Ventas por región
SELECT
    REGION,
    SUM(TOTAL_UNIT_SALES)  AS Unidades,
    SUM(TOTAL_VALUE_SALES) AS Valor,
    COUNT(*)               AS Transacciones
FROM FACT_SALES
GROUP BY REGION
ORDER BY Valor DESC;
GO

-- 7.3 Ventas por año
SELECT
    c.[YEAR],
    SUM(f.TOTAL_UNIT_SALES)  AS Unidades,
    SUM(f.TOTAL_VALUE_SALES) AS Valor
FROM FACT_SALES f
INNER JOIN DIM_CALENDAR c ON f.WEEK = c.WEEK
GROUP BY c.[YEAR]
ORDER BY c.[YEAR];
GO

-- 7.4 Top 10 marcas por valor
SELECT TOP 10
    p.BRAND,
    SUM(f.TOTAL_UNIT_SALES)  AS Unidades,
    SUM(f.TOTAL_VALUE_SALES) AS Valor
FROM FACT_SALES f
INNER JOIN DIM_PRODUCT p ON f.ITEM_CODE = p.ITEM
GROUP BY p.BRAND
ORDER BY Valor DESC;
GO

-- 7.5 Ventas por segmento
SELECT
    s.SEGMENT,
    SUM(f.TOTAL_UNIT_SALES)  AS Unidades,
    SUM(f.TOTAL_VALUE_SALES) AS Valor
FROM FACT_SALES f
INNER JOIN DIM_PRODUCT p ON f.ITEM_CODE = p.ITEM
INNER JOIN DIM_SEGMENT s ON
       p.CATEGORY = s.CATEGORY
   AND ISNULL(p.ATTR1,'') = ISNULL(s.ATTR1,'')
   AND ISNULL(p.ATTR2,'') = ISNULL(s.ATTR2,'')
   AND ISNULL(p.ATTR3,'') = ISNULL(s.ATTR3,'')
   AND ISNULL(p.FORMAT,'') = ISNULL(s.FORMAT,'')
GROUP BY s.SEGMENT
ORDER BY Valor DESC;
GO

-- 7.6 Ventas cruzadas: Categoría × Región
SELECT
    dc.CATEGORY,
    f.REGION,
    SUM(f.TOTAL_VALUE_SALES) AS Valor
FROM FACT_SALES f
INNER JOIN DIM_PRODUCT p  ON f.ITEM_CODE = p.ITEM
INNER JOIN DIM_CATEGORY dc ON p.CATEGORY = dc.ID_CATEGORY
GROUP BY dc.CATEGORY, f.REGION
ORDER BY dc.CATEGORY, Valor DESC;
GO

-- 7.7 Participación por marca (% del total)
SELECT
    p.BRAND,
    SUM(f.TOTAL_VALUE_SALES) AS Valor,
    ROUND(
        SUM(f.TOTAL_VALUE_SALES) * 100.0 /
        (SELECT SUM(TOTAL_VALUE_SALES) FROM FACT_SALES), 2
    ) AS Pct_Participacion
FROM FACT_SALES f
INNER JOIN DIM_PRODUCT p ON f.ITEM_CODE = p.ITEM
GROUP BY p.BRAND
ORDER BY Valor DESC;
GO