import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.sql_connect import get_connection

def inspect_waiting():
    conn = get_connection()
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_name = 'waiting_history';
    """)
    cols = cursor.fetchall()
    print("Table 'waiting_history' columns:")
    for col in cols:
        print(f" - {col[0]} ({col[1]})")
    
    cursor.close()
    conn.close()

if __name__ == "__main__":
    inspect_waiting()
