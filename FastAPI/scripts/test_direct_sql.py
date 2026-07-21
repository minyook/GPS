import sys
import os
import pg8000.native

# 퍼블릭 IP 또는 표준 Cloud SQL 호스트 접속 시도
def test_direct_postgres():
    print("Testing direct pg8000 connection...")
    hosts_to_try = [
        "127.0.0.1",
        "34.64.xxx.xxx", # 공용 IP 시도
    ]
    
    for host in hosts_to_try:
        try:
            con = pg8000.native.Connection(
                user="postgres",
                password="", # 패스워드 없이 시도
                host=host,
                database="gps-test-4ccbb-database",
                timeout=5
            )
            print(f"Success connecting to {host}!")
            con.close()
            break
        except Exception as e:
            print(f"Host {host} failed: {e}")

if __name__ == "__main__":
    test_postgres()
