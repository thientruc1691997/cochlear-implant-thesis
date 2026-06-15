import pyodbc
import pandas as pd
import os

# Import config local 
sys.path.insert(0, os.path.abspath("."))
from config import DB_SERVER, DB_NAME, DB_DRIVER, CSV_OUTPUT

def get_connection():
    conn_str = (
        f"DRIVER={{{DB_DRIVER}}};"
        f"SERVER={DB_SERVER};"
        f"DATABASE={DB_NAME};"
        "Trusted_Connection=yes;"   # Windows Authentication
    )
    return pyodbc.connect(conn_str)

def run_pipeline():
    conn = get_connection()


    sql_dir = os.path.join(os.path.dirname(__file__))
    scripts = [
        "01_patient_surgery.sql",
        "02_preop_audiometry.sql",
        "03_preop_speech.sql",
        "04_preop_phoneme.sql",
        "05_postop_extraction.sql",
        "06_keywords.sql",
        "07_final_merge.sql",   # SELECT * FROM final_view
    ]

    for script in scripts[:-1]:
        path = os.path.join(sql_dir, script)
        with open(path, "r", encoding="utf-8") as f:
            sql = f.read()
        print(f"Running {script}...")
        conn.execute(sql)
        conn.commit()

    final_script = os.path.join(sql_dir, scripts[-1])
    with open(final_script, "r", encoding="utf-8") as f:
        sql = f.read()

    print("Exporting final dataset...")
    df = pd.read_sql(sql, conn)
    print(f"Rows: {len(df)} | Columns: {len(df.columns)}")

    os.makedirs(os.path.dirname(CSV_OUTPUT), exist_ok=True)
    df.to_csv(CSV_OUTPUT, index=False)
    print(f"Saved to {CSV_OUTPUT}")
    conn.close()

if __name__ == "__main__":
    run_pipeline()