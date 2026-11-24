from pathlib import Path

# Project directory
PROJECT_ROOT = Path(r"C:\Projects\IndianaWorkforceIntelligence")

# Location of the original STATS Indiana datasets
RAW_DATA_DIR = PROJECT_ROOT / "data" / "raw" / "stats_indiana" / "laus"

print("Raw data directory:", RAW_DATA_DIR)
print("Directory exists:", RAW_DATA_DIR.exists())

# Find all downloaded STATS Indiana .xls files
source_files = sorted(RAW_DATA_DIR.glob("*.xls"))

print("\nAvailable source files:")

for file in source_files:
    print(file.name)

print(f"\nTotal files found: {len(source_files)}")

import pandas as pd


# Select the 2023 unemployment dataset
file_path = RAW_DATA_DIR / "stats_data_2023.xls"

# Read HTML tables from the file
tables = pd.read_html(file_path)

# Display the number of tables found
print("\nNumber of tables found:", len(tables))

# Display the first five rows of the first table
print("\nFirst five rows:")
print(tables[0].head())

# Store the extracted table in a DataFrame
df_2023 = tables[0]

# Check dataset dimensions
print("\nDataset dimensions (rows, columns):")
print(df_2023.shape)

# Check column data types
print("\nColumn data types:")
print(df_2023.dtypes)

# Check missing values
print("\nMissing values by column:")
print(df_2023.isnull().sum())

# Count unique geographic areas
unique_geographies = df_2023["FIPS Code"].nunique()

print("\nUnique geographic areas:", unique_geographies)

# Count records for each geography
records_per_geography = df_2023.groupby("Geography").size()

print("\nRecords per geography:")
print(records_per_geography.describe())


# Examine reporting periods in the 2023 dataset
reporting_periods = (
    df_2023.groupby(["Month Code", "Month"])
    .size()
    .reset_index(name="RecordCount")
    .sort_values("Month Code")
)

print("\n2023 reporting periods:")
print(reporting_periods.to_string(index=False))

# Define the business key
business_key = ["FIPS Code", "Year", "Month Code"]

# Identify duplicate observations
duplicate_records = df_2023.duplicated(
    subset=business_key,
    keep=False
)

# Count duplicate rows
duplicate_count = duplicate_records.sum()

print("\nDuplicate records:", duplicate_count)

if duplicate_count > 0:
    print("\nDuplicate observations:")
    print(df_2023[duplicate_records])
else:
    print("PASS: No duplicate business keys found.")


# Validate unemployment rate values
invalid_rates = df_2023[
    (df_2023["Unemployment Rate"] < 0) |
    (df_2023["Unemployment Rate"] > 100)
]

print("\nUnemployment rate validation:")
print("Minimum rate:", df_2023["Unemployment Rate"].min())
print("Maximum rate:", df_2023["Unemployment Rate"].max())
print("Invalid rate records:", len(invalid_rates))

if invalid_rates.empty:
    print("PASS: All unemployment rates are within 0–100%.")
else:
    print("FAIL: Invalid unemployment rates detected.")
    print(invalid_rates)

# Identify statewide and county-level observations
statewide_records = df_2023[
    df_2023["FIPS Code"] == 18000
]

county_records = df_2023[
    df_2023["FIPS Code"] != 18000
]

# Count unique geographic identifiers
statewide_count = statewide_records["FIPS Code"].nunique()
county_count = county_records["FIPS Code"].nunique()

print("\nGeographic classification validation:")
print("Statewide geographic areas:", statewide_count)
print("County geographic areas:", county_count)
print("Statewide observations:", len(statewide_records))
print("County observations:", len(county_records))

if statewide_count == 1 and county_count == 92:
    print("PASS: Geographic counts match the expected structure.")
else:
    print("FAIL: Unexpected geographic counts detected.")


# Validate all downloaded annual datasets
print("\nMULTI-YEAR DATA VALIDATION")

for source_file in source_files:
    df = pd.read_html(source_file)[0]

    duplicate_count = df.duplicated(
        subset=["FIPS Code", "Year", "Month Code"]
    ).sum()

    missing_count = df.isnull().sum().sum()

    invalid_rate_count = (
        (~df["Unemployment Rate"].between(0, 100))
        & df["Unemployment Rate"].notna()
    ).sum()

    print(f"\nFile: {source_file.name}")
    print(f"Records: {len(df)}")
    print(f"Geographic areas: {df['FIPS Code'].nunique()}")
    print(f"Missing values: {missing_count}")
    print(f"Duplicate business keys: {duplicate_count}")
    print(f"Invalid unemployment rates: {invalid_rate_count}")


# Examine reporting-period coverage across all datasets
print("\nMULTI-YEAR REPORTING PERIOD COVERAGE")

for source_file in source_files:
    df = pd.read_html(source_file)[0]

    year = df["Year"].iloc[0]

    period_counts = (
        df.groupby(["Month Code", "Month"])
        .size()
        .reset_index(name="Records")
        .sort_values("Month Code")
    )

    print(f"\nYear: {year}")
    print(period_counts.to_string(index=False))


# Prepare 2023 records for Bronze ingestion
# Combine all available annual source files
all_dataframes = []

for source_file in source_files:
    df = pd.read_html(source_file)[0]

    # Preserve the original source filename for lineage
    df["SourceFile"] = source_file.name

    all_dataframes.append(df)

bronze_df = pd.concat(all_dataframes, ignore_index=True)

# Rename source columns to match SQL Server
bronze_df = bronze_df.rename(columns={
    "FIPS Code": "FIPSCode",
    "Year": "ReportingYear",
    "Month": "ReportingMonth",
    "Month Code": "MonthCode",
    "Unemployment Rate": "UnemploymentRate"
})

# Add data lineage metadata
bronze_df["SourceSystem"] = "STATS Indiana LAUS"


# Convert source values to text for Bronze storage
for column in [
    "FIPSCode",
    "ReportingYear",
    "MonthCode",
    "UnemploymentRate"
]:
    bronze_df[column] = bronze_df[column].astype(str)

print("\nBRONZE INGESTION PREVIEW")
print(bronze_df.head())
print("\nRecords prepared:", len(bronze_df))



import pyodbc

connection_string = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=Matt;"
    "DATABASE=IndianaWorkforceDW;"
    "Trusted_Connection=yes;"
    "Encrypt=yes;"
    "TrustServerCertificate=yes;"
)

insert_sql = """
INSERT INTO bronze.Laus_Unemployment_Raw
(
    Geography,
    FIPSCode,
    ReportingYear,
    ReportingMonth,
    MonthCode,
    UnemploymentRate,
    SourceSystem,
    SourceFile
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
"""

columns = [
    "Geography",
    "FIPSCode",
    "ReportingYear",
    "ReportingMonth",
    "MonthCode",
    "UnemploymentRate",
    "SourceSystem",
    "SourceFile"
]

records = list(bronze_df[columns].itertuples(index=False, name=None))

connection = None

try:
    connection = pyodbc.connect(connection_string)
    cursor = connection.cursor()

    # Process each source file independently
    for source_file in source_files:

        filename = source_file.name

        # Select records belonging to this source file
        file_records = [
            record
            for record in records
            if record[7] == filename
        ]

        # Check whether this file has already been loaded
        cursor.execute(
            """
            SELECT COUNT(*)
            FROM bronze.Laus_Unemployment_Raw
            WHERE SourceFile = ?
            """,
            filename
        )

        existing_records = cursor.fetchone()[0]

        if existing_records > 0:
            print(
                f"SKIPPED: {filename} "
                f"already contains {existing_records} records."
            )
        else:
            cursor.executemany(insert_sql, file_records)

            print(
                f"PREPARED: {filename} "
                f"({len(file_records)} records)"
            )

    # Commit all new records as one transaction
    connection.commit()

    print("Bronze ingestion transaction completed.")

except pyodbc.Error as error:

    if connection is not None:
        connection.rollback()

    print("ERROR: Bronze ingestion failed.")
    print(error)

finally:

    if connection is not None:
        connection.close()