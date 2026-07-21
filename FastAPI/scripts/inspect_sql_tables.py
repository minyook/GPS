import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.sql_connect import get_connection

def inspect_columns():
    conn = get_connection()
    cursor = conn.cursor()
    
    for table in ['user', 'store']:
        cursor.execute(f"""
            SELECT column_name, data_type 
            FROM information_schema.columns 
            WHERE table_name = '{table}';
        """)
        cols = cursor.fetchall()
        print(f"\nTable '{table}' columns:")
        for col in cols:
            print(f" - {col[0]} ({col[1]})")
    
    cursor.close()
    conn.close()

if __name__ == "__main__":
    inspect_columns()
