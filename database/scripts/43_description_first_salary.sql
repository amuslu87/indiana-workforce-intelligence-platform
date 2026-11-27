USE IndianaWorkforceDW;
GO

CREATE OR ALTER FUNCTION control.fn_DescriptionBaseSalary
(
    @Evidence nvarchar(max)
)
RETURNS nvarchar(100)
AS
BEGIN
    DECLARE @Text nvarchar(max);
    DECLARE @Position int;
    DECLARE @Amount nvarchar(100);
    DECLARE @End int;

    SET @Text = LOWER(@Evidence);

    IF @Text IS NULL
        RETURN NULL;

    -- Recognize explicit starting salary statements
    IF @Text NOT LIKE '%salary for this position%starts%'
       AND @Text NOT LIKE '%this position starts at%'
       AND @Text NOT LIKE '%salary for this position is%'
       AND @Text NOT LIKE '%salary ranges from%'
        RETURN NULL;

    -- Locate the first advertised monetary amount
    SET @Position = CHARINDEX('$',@Text);

    IF @Position = 0
        RETURN NULL;

    SET @Amount =
        SUBSTRING(@Text,@Position+1,100);

    SET @End =
        PATINDEX('%[^0-9,.]%',@Amount+' ');

    SET @Amount = LEFT(@Amount,@End-1);

    IF RIGHT(@Amount,1) = '.'
        SET @Amount = LEFT(@Amount,LEN(@Amount)-1);

    IF TRY_CONVERT(decimal(18,2),
        REPLACE(@Amount,',','')) IS NULL
        RETURN NULL;

    RETURN @Amount;
END;
GO

-- Preview description-derived starting salaries
WITH Evidence AS
(
    SELECT DISTINCT
        p.JobPostingID,
        p.JobTitle,
        p.SalaryAmount AS CurrentBaseSalary,
        TRY_CONVERT(
            decimal(18,2),
            REPLACE(
                control.fn_DescriptionBaseSalary(
                    c.SalaryEvidence
                ),',',''
            )
        ) AS DescriptionBaseSalary
    FROM silver.StateCareers_JobPosting p
    JOIN silver.StateCareers_JobCompensation c
        ON c.JobPostingID = p.JobPostingID
        AND c.SourceRawID = p.LatestRawID
    WHERE p.IsActive = 1
),
Assessment AS
(
    SELECT
        JobPostingID,
        JobTitle,
        CurrentBaseSalary,
        MIN(DescriptionBaseSalary) AS MinimumDescriptionBase,
        MAX(DescriptionBaseSalary) AS MaximumDescriptionBase,
        COUNT(DISTINCT DescriptionBaseSalary)
            AS DistinctBaseAmounts
    FROM Evidence
    WHERE DescriptionBaseSalary > 0
    GROUP BY
        JobPostingID,
        JobTitle,
        CurrentBaseSalary
)
SELECT *
FROM Assessment
WHERE CurrentBaseSalary IS NULL
   OR CurrentBaseSalary <> MinimumDescriptionBase
   OR DistinctBaseAmounts > 1
ORDER BY JobTitle;
GO

PRINT 'DESCRIPTION SALARY EXTRACTION PREVIEW COMPLETE';
GO
