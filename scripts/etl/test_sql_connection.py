import pyodbc

# SQL Server connection configuration
server = "Matt"
database = "IndianaWorkforceDW"

connection_string = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    f"SERVER={server};"
    f"DATABASE={database};"
    "Trusted_Connection=yes;"
    "Encrypt=yes;"
    "TrustServerCertificate=yes;"
)

try:
    connection = pyodbc.connect(connection_string, timeout=10)

    cursor = connection.cursor()
    cursor.execute("SELECT DB_NAME(), @@SERVERNAME")

    result = cursor.fetchone()

    print("SUCCESS: Connected to SQL Server!")
    print("Database:", result[0])
    print("Server:", result[1])

     # Verify access to the Bronze unemployment table
    cursor.execute("""
        SELECT COUNT(*)
        FROM bronze.Laus_Unemployment_Raw
    """)

    record_count = cursor.fetchone()[0]

    print("Bronze table accessible: YES")
    print("Current records:", record_count)

    connection.close()

except pyodbc.Error as error:
    print("ERROR: SQL Server connection failed.")
    print(error)