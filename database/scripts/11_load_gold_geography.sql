USE IndianaWorkforceDW;
GO

-- Load unique geographic areas from Silver into Gold
INSERT INTO gold.Dim_Geography
(
    FIPSCode,
    GeographyName,
    GeographyType
)
SELECT DISTINCT
    s.FIPSCode,
    s.Geography,
    s.GeographyType
FROM silver.Laus_Unemployment AS s
WHERE NOT EXISTS
(
    SELECT 1
    FROM gold.Dim_Geography AS g
    WHERE g.FIPSCode = s.FIPSCode
);
GO

-- Validate the dimension
SELECT
    GeographyType,
    COUNT(*) AS GeographicAreas
FROM gold.Dim_Geography
GROUP BY GeographyType;