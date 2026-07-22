import csv
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
file_path = os.path.abspath(os.path.join(script_dir, "..", "..", "부산광역시_지역화폐(동백전) 가맹점 현황_20260424.csv"))

count = 0
with open(file_path, 'r', encoding='utf-8-sig') as f:
    reader = csv.reader(f)
    header = next(reader)
    for row in reader:
        count += 1

print(f"Total store rows in CSV: {count}")
