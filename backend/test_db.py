import psycopg2


DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "database": "cacao_gradeai",
    "user": "postgres",
    "password": "admin123"
}


try:
    conn = psycopg2.connect(**DB_CONFIG)
    print("SUCCESS: Connected to PostgreSQL!")

    conn.close()

except Exception as e:
    print("ERROR: Could not connect to PostgreSQL.")
    print(e)