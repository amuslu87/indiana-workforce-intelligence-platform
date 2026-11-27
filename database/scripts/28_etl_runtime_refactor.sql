USE IndianaWorkforceDW;
GO

-- 1. Recruitment tables and current record counts

SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    SUM(p.rows) AS RecordCount
FROM sys.tables t
JOIN sys.schemas s
    ON t.schema_id = s.schema_id
JOIN sys.partitions p
    ON t.object_id = p.object_id
WHERE p.index_id IN (0, 1)
AND (
    t.name LIKE '%StateCareers%'
    OR t.name LIKE '%Recruitment%'
    OR t.name IN (
        'Dim_Agency',
        'Dim_Skill',
        'Fact_StateJobPosting',
        'Bridge_JobPostingSkill'
    )
)
GROUP BY s.name, t.name
ORDER BY s.name, t.name;


-- 2. Recruitment table column definitions

SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    c.column_id AS ColumnOrder,
    c.name AS ColumnName,
    TYPE_NAME(c.user_type_id) AS DataType,
    c.max_length AS MaxLengthBytes,
    c.precision,
    c.scale,
    c.is_nullable AS IsNullable,
    c.is_identity AS IsIdentity
FROM sys.tables t
JOIN sys.schemas s
    ON t.schema_id = s.schema_id
JOIN sys.columns c
    ON t.object_id = c.object_id
WHERE
    t.name LIKE '%StateCareers%'
    OR t.name LIKE '%Recruitment%'
    OR t.name IN (
        'Dim_Agency',
        'Dim_Skill',
        'Fact_StateJobPosting',
        'Bridge_JobPostingSkill'
    )
ORDER BY s.name, t.name, c.column_id;


-- 3. Recruitment foreign key relationships

SELECT
    fk.name AS ForeignKeyName,
    OBJECT_SCHEMA_NAME(fk.parent_object_id)
        AS SourceSchema,
    OBJECT_NAME(fk.parent_object_id)
        AS SourceTable,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id)
        AS TargetSchema,
    OBJECT_NAME(fk.referenced_object_id)
        AS TargetTable,
    fk.is_disabled AS IsDisabled,
    fk.is_not_trusted AS IsNotTrusted
FROM sys.foreign_keys fk
WHERE
    OBJECT_NAME(fk.parent_object_id) LIKE '%StateCareers%'
    OR OBJECT_NAME(fk.parent_object_id) LIKE '%Recruitment%'
    OR OBJECT_NAME(fk.parent_object_id) IN (
        'Fact_StateJobPosting',
        'Bridge_JobPostingSkill'
    )
ORDER BY SourceSchema, SourceTable;


-- 4. Existing recruitment source registration

SELECT *
FROM control.DataSource
WHERE SourceCode = 'STATE_CAREERS';