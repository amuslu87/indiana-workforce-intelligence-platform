---— Verify database constraints

USE IndianaWorkforceDW;
GO

SELECT
    OBJECT_SCHEMA_NAME(parent_object_id) AS SchemaName,
    OBJECT_NAME(parent_object_id) AS TableName,
    name AS ConstraintName,
    type_desc AS ConstraintType
FROM sys.objects
WHERE type IN ('PK', 'UQ', 'F', 'C', 'D')
AND (
    OBJECT_NAME(parent_object_id) LIKE 'StateCareers%'
    OR OBJECT_NAME(parent_object_id) IN (
        'Dim_Agency',
        'Dim_Skill',
        'Fact_StateJobPosting',
        'Fact_RecruitmentDaily',
        'Bridge_JobPostingSkill'
    )
)
ORDER BY SchemaName, TableName, ConstraintType;

SELECT
    OBJECT_NAME(object_id) AS TableName,
    name AS IndexName,
    is_unique AS IsUnique,
    is_disabled AS IsDisabled
FROM sys.indexes
WHERE (
    OBJECT_NAME(object_id) LIKE 'StateCareers%'
    OR OBJECT_NAME(object_id) IN (
        'Dim_Agency',
        'Dim_Skill',
        'Fact_StateJobPosting',
        'Fact_RecruitmentDaily',
        'Bridge_JobPostingSkill'
    )
)
AND index_id > 0
ORDER BY TableName, IndexName;