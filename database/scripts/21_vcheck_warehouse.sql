USE IndianaWorkforceDW;

SELECT
    SourceCode,
    Status,
    RunID,
    PublishedRunID,
    PublishedUTC
FROM control.vw_PipelineHealth;

SELECT 'Unemployment' AS Dataset,
       COUNT_BIG(*) AS PublishedRows
FROM serving.vw_Unemployment

UNION ALL

SELECT 'Labor Market', COUNT_BIG(*)
FROM serving.vw_LaborMarket

UNION ALL

SELECT 'Occupational Wages', COUNT_BIG(*)
FROM serving.vw_OccupationalWages

UNION ALL

SELECT 'Occupational Projections', COUNT_BIG(*)
FROM serving.vw_OccupationalProjection;

SELECT @@TRANCOUNT AS OpenTransactions;