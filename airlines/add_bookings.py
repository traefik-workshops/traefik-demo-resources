#!/usr/bin/env python3
"""
Quick script to add 10 more bookings to demonstrate dashboard updates
"""
import json
import random
import datetime
from pathlib import Path

# Read existing bookings
bookings_file = Path("airlines/helm/templates/bookings/service.yaml")
content = bookings_file.read_text()

# Extract the JSON block
start = content.find('{\n      "bookings":')
end = content.find('\n    }', start) + 6
json_str = content[start:end]
data = json.loads(json_str)

existing_bookings = data["bookings"]
print(f"📊 Current bookings: {len(existing_bookings)}")

# Add 10 new bookings
flights = ["FL876", "FL680", "FL874", "FL605"]
passengers = [f"P{10000 + i}" for i in range(50)]

for i in range(10):
    bid = f"BK{random.randint(900000, 999999)}"
    existing_bookings[bid] = {
        "booking_id": bid,
        "flight_id": random.choice(flights),
        "passenger_id": random.choice(passengers),
        "status": "confirmed",
        "booking_date": datetime.datetime.now().isoformat(),
        "class": random.choice(["economy", "business", "first"])
    }

print(f"✅ New bookings: {len(existing_bookings)}")

# Write back
new_json = json.dumps({"bookings": existing_bookings}, indent=2)
indented = "\n".join("    " + line for line in new_json.splitlines())

# Replace the content
new_content = content[:start] + indented + content[end:]
bookings_file.write_text(new_content)

print("🚀 Updated bookings/service.yaml - run ./deploy.sh to apply")
