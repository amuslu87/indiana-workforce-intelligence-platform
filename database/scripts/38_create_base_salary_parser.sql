USE IndianaWorkforceDW;
GO

CREATE OR ALTER FUNCTION control.fn_ParseBaseSalary
(
    @RawSalary nvarchar(100)
)
RETURNS @Result TABLE
(
    BaseSalary decimal(18,2),
    SalaryFrequency varchar(20),
    AnnualizedSalary decimal(18,2),
    AnnualizationHours smallint,
    ParsingStatus varchar(30)
)
AS
BEGIN
    DECLARE @Text nvarchar(100);
    DECLARE @Low nvarchar(100);
    DECLARE @High nvarchar(100);
    DECLARE @Amount decimal(18,2);
    DECLARE @UpperAmount decimal(18,2);
    DECLARE @Frequency varchar(20) = 'UNKNOWN';
    DECLARE @Separator int;
    DECLARE @Status varchar(30) = 'PARSED';

    -- Standard Indiana state working schedule
    DECLARE @StandardBiweeklyHours smallint = 75;
    DECLARE @AnnualPayPeriods smallint = 26;
    DECLARE @StandardAnnualHours smallint;

    SET @StandardAnnualHours =
        @StandardBiweeklyHours * @AnnualPayPeriods;

    SET @Text = LOWER(LTRIM(RTRIM(@RawSalary)));

    -- Handle missing salary
    IF NULLIF(@Text,'') IS NULL
    BEGIN
        INSERT INTO @Result
        VALUES (NULL,'UNKNOWN',NULL,NULL,'MISSING');
        RETURN;
    END;

    -- Normalize salary range separators
    SET @Text = REPLACE(@Text,NCHAR(8211),'-');
    SET @Text = REPLACE(@Text,NCHAR(8212),'-');
    SET @Text = REPLACE(@Text,' to ','-');

    -- Identify advertised salary frequency
    IF @Text LIKE '%/hr'
       OR @Text LIKE '%/hour'
       OR @Text LIKE '%per hour'
        SET @Frequency = 'HOURLY';

    ELSE IF @Text LIKE '%annually'
         OR @Text LIKE '%/year'
         OR @Text LIKE '%per year'
         OR @Text LIKE '% annual'
        SET @Frequency = 'ANNUAL';

    ELSE IF @Text LIKE '%monthly'
         OR @Text LIKE '%/month'
         OR @Text LIKE '%per month'
        SET @Frequency = 'MONTHLY';

    ELSE IF @Text LIKE '%biweekly'
         OR @Text LIKE '%bi-weekly'
        SET @Frequency = 'BIWEEKLY';

    -- Remove frequency indicators
    SET @Text = REPLACE(@Text,'/hour','');
    SET @Text = REPLACE(@Text,'/hr','');
    SET @Text = REPLACE(@Text,'per hour','');
    SET @Text = REPLACE(@Text,'annually','');
    SET @Text = REPLACE(@Text,' annual','');
    SET @Text = REPLACE(@Text,'/year','');
    SET @Text = REPLACE(@Text,'per year','');
    SET @Text = REPLACE(@Text,'monthly','');
    SET @Text = REPLACE(@Text,'/month','');
    SET @Text = REPLACE(@Text,'per month','');
    SET @Text = REPLACE(@Text,'biweekly','');
    SET @Text = REPLACE(@Text,'bi-weekly','');

    -- Remove currency formatting
    SET @Text = REPLACE(@Text,'$','');
    SET @Text = REPLACE(@Text,',','');
    SET @Text = LTRIM(RTRIM(@Text));

    -- Extract minimum salary from a range
    SET @Separator = CHARINDEX('-',@Text);

    IF @Separator > 0
    BEGIN
        SET @Low = LEFT(@Text,@Separator-1);
        SET @High = SUBSTRING(@Text,@Separator+1,100);

        SET @Amount =
            TRY_CONVERT(decimal(18,2),@Low);

        SET @UpperAmount =
            TRY_CONVERT(decimal(18,2),@High);

        IF @UpperAmount IS NULL
           OR @Amount IS NULL
           OR @UpperAmount < @Amount
            SET @Amount = NULL;

        SET @Status = 'RANGE_MINIMUM';
    END
    ELSE
    BEGIN
        SET @Amount =
            TRY_CONVERT(decimal(18,2),@Text);
    END;

    -- Reject invalid or ambiguous amounts
    IF @Amount IS NULL OR @Amount <= 0
    BEGIN
        INSERT INTO @Result
        VALUES (
            NULL,'UNKNOWN',NULL,NULL,'REVIEW_REQUIRED'
        );
        RETURN;
    END;

    -- Calculate standardized annual compensation
    INSERT INTO @Result
    SELECT
        @Amount,
        @Frequency,

        CASE
            WHEN @Frequency = 'HOURLY'
                THEN @Amount * @StandardAnnualHours

            WHEN @Frequency = 'ANNUAL'
                THEN @Amount

            WHEN @Frequency = 'MONTHLY'
                THEN @Amount * 12

            WHEN @Frequency = 'BIWEEKLY'
                THEN @Amount * @AnnualPayPeriods

            ELSE NULL
        END,

        CASE
            WHEN @Frequency = 'HOURLY'
                THEN @StandardAnnualHours
            ELSE NULL
        END,

        @Status;

    RETURN;
END;
GO

-- Test salary parsing and annualization
SELECT
    v.RawSalary,
    p.*
FROM (VALUES
    (N'$20.00/hr'),
    (N'$20-$25/hr'),
    (N'$85,020-$110,000 annually'),
    (N'$93,002.00'),
    (N'$22.00/hr'),
    (N'$24.26/hr'),
    (N'$4.00/hr'),
    (N'$5,000 monthly'),
    (N'$2,000 biweekly'),
    (N'$20/hr + $1 incentive'),
    (N'$25-$20/hr'),
    (N''),
    (N'Negotiable')
) v(RawSalary)
CROSS APPLY
    control.fn_ParseBaseSalary(v.RawSalary) p;
GO

-- Assess all active job postings
SELECT
    s.ParsingStatus,
    s.SalaryFrequency,
    COUNT(*) AS Postings,
    MIN(s.BaseSalary) AS MinimumBase,
    MAX(s.BaseSalary) AS MaximumBase,
    MIN(s.AnnualizedSalary) AS MinimumAnnualized,
    MAX(s.AnnualizedSalary) AS MaximumAnnualized
FROM silver.StateCareers_JobPosting p
CROSS APPLY
    control.fn_ParseBaseSalary(p.MinimumSalaryRaw) s
WHERE p.IsActive = 1
GROUP BY
    s.ParsingStatus,
    s.SalaryFrequency;
GO

PRINT 'BASE SALARY PARSER CREATED SUCCESSFULLY';
GO
