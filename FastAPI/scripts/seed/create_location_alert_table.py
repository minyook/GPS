import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from app.core.sql_connect import get_connection

def create_location_alert_table():
    print("[SQL Connect] Creating 'location_alert_history' table for location-based alert & stay tracking...")
    conn = get_connection()
    cursor = conn.cursor()
    
    # 위치 기반 체류 및 동백전 결제 유도 푸시 기록 전용 테이블 DDL
    ddl_query = """
        CREATE TABLE IF NOT EXISTS location_alert_history (
            id UUID PRIMARY KEY,
            user_id TEXT NOT NULL,
            store_id TEXT NOT NULL,
            store_name TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'candidate',
            stay_minutes DOUBLE PRECISION DEFAULT 0.0,
            alert_sent BOOLEAN DEFAULT FALSE,
            sent_date TEXT NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
        
        CREATE INDEX IF NOT EXISTS idx_location_alert_user_store_date 
        ON location_alert_history (user_id, store_id, sent_date);
    """
    try:
        cursor.execute(ddl_query)
        conn.commit()
        print("[SQL Connect SUCCESS] Table 'location_alert_history' created successfully!")
    except Exception as e:
        print(f"Error creating table: {e}")
        conn.rollback()
    finally:
        cursor.close()
        conn.close()

if __name__ == "__main__":
    create_location_alert_table()
