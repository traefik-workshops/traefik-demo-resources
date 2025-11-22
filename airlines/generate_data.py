
import json
import random
import datetime
from pathlib import Path

# Configuration
BASE_DIR = Path("airlines/helm/templates")
COUNTS = {
    "flights": 20,
    "passengers": 50,
    "bookings": 100,
    "loyalty": 50  # Match passengers
}

# Reference Data
CITIES = [
    {"code": "JFK", "city": "New York", "country": "USA"},
    {"code": "LHR", "city": "London", "country": "UK"},
    {"code": "CDG", "city": "Paris", "country": "France"},
    {"code": "HND", "city": "Tokyo", "country": "Japan"},
    {"code": "DXB", "city": "Dubai", "country": "UAE"},
    {"code": "SIN", "city": "Singapore", "country": "Singapore"},
    {"code": "LAX", "city": "Los Angeles", "country": "USA"},
    {"code": "SYD", "city": "Sydney", "country": "Australia"},
    {"code": "FRA", "city": "Frankfurt", "country": "Germany"},
    {"code": "AMS", "city": "Amsterdam", "country": "Netherlands"}
]

NAMES = [
    ("James", "Smith"), ("Maria", "Garcia"), ("Robert", "Johnson"), ("Lisa", "Davis"),
    ("David", "Wilson"), ("Jennifer", "Brown"), ("Michael", "Miller"), ("Elizabeth", "Taylor"),
    ("William", "Anderson"), ("Linda", "Thomas"), ("Richard", "Jackson"), ("Patricia", "White"),
    ("Joseph", "Harris"), ("Susan", "Martin"), ("Thomas", "Thompson"), ("Jessica", "Garcia"),
    ("Charles", "Martinez"), ("Sarah", "Robinson"), ("Christopher", "Clark"), ("Karen", "Rodriguez"),
    ("Daniel", "Lewis"), ("Nancy", "Lee"), ("Matthew", "Walker"), ("Margaret", "Hall"),
    ("Anthony", "Allen"), ("Betty", "Young"), ("Mark", "Hernandez"), ("Dorothy", "King"),
    ("Donald", "Wright"), ("Sandra", "Lopez"), ("Steven", "Hill"), ("Ashley", "Scott"),
    ("Paul", "Green"), ("Kimberly", "Adams"), ("Andrew", "Baker"), ("Donna", "Gonzalez"),
    ("Joshua", "Nelson"), ("Emily", "Carter"), ("Kenneth", "Mitchell"), ("Michelle", "Perez"),
    ("Kevin", "Roberts"), ("Carol", "Turner"), ("Brian", "Phillips"), ("Amanda", "Campbell"),
    ("George", "Parker"), ("Melissa", "Evans"), ("Edward", "Edwards"), ("Deborah", "Collins"),
    ("Ronald", "Stewart"), ("Stephanie", "Sanchez")
]

TIERS = ["Standard", "Silver", "Gold", "Platinum", "Diamond"]

def generate_flights():
    flights = {}
    for i in range(COUNTS["flights"]):
        origin = random.choice(CITIES)
        dest = random.choice([c for c in CITIES if c != origin])
        flight_num = f"FL{random.randint(100, 999)}"
        
        # Generate schedule for next 30 days
        date = datetime.datetime.now() + datetime.timedelta(days=random.randint(1, 30))
        dept_time = date.replace(hour=random.randint(6, 22), minute=random.choice([0, 15, 30, 45]))
        duration = random.randint(2, 14)
        arr_time = dept_time + datetime.timedelta(hours=duration)
        
        flights[flight_num] = {
            "flight_id": flight_num,
            "origin": origin["code"],
            "destination": dest["code"],
            "departure_time": dept_time.isoformat(),
            "arrival_time": arr_time.isoformat(),
            "status": random.choice(["scheduled"] * 8 + ["delayed", "cancelled"]),
            "aircraft": random.choice(["B737", "A320", "B787", "A350"]),
            "seats_available": random.randint(0, 50),
            "price": random.randint(200, 1500)
        }
    return flights

def generate_passengers():
    passengers = {}
    for i, (first, last) in enumerate(NAMES):
        pid = f"P{10000 + i}"
        passengers[pid] = {
            "passenger_id": pid,
            "first_name": first,
            "last_name": last,
            "email": f"{first.lower()}.{last.lower()}@example.com",
            "phone": f"+1-555-01{i:02d}",
            "passport_number": f"X{random.randint(10000000, 99999999)}"
        }
    return passengers

def generate_loyalty(passengers):
    loyalty = {}
    for pid, p in passengers.items():
        lid = f"LM{pid[1:]}"
        tier = random.choice(TIERS)
        miles = random.randint(0, 500000)
        if tier == "Standard": miles = random.randint(0, 20000)
        
        loyalty[lid] = {
            "member_id": lid,
            "passenger_id": pid,
            "tier": tier,
            "miles_balance": miles,
            "status": "active"
        }
    return loyalty

def generate_bookings(passengers, flights):
    bookings = {}
    tickets = {}
    checkins = {}
    baggage = {}
    
    flight_list = list(flights.values())
    passenger_list = list(passengers.values())
    
    for i in range(COUNTS["bookings"]):
        bid = f"BK{random.randint(100000, 999999)}"
        flight = random.choice(flight_list)
        passenger = random.choice(passenger_list)
        
        status = "confirmed"
        if flight["status"] == "cancelled": status = "cancelled"
        
        bookings[bid] = {
            "booking_id": bid,
            "flight_id": flight["flight_id"],
            "passenger_id": passenger["passenger_id"],
            "status": status,
            "booking_date": (datetime.datetime.now() - datetime.timedelta(days=random.randint(1, 60))).isoformat(),
            "class": random.choice(["economy", "business", "first"])
        }
        
        # Generate Ticket
        if status == "confirmed":
            tid = f"TK{random.randint(1000000000, 9999999999)}"
            tickets[tid] = {
                "ticket_id": tid,
                "booking_id": bid,
                "passenger_name": f"{passenger['first_name']} {passenger['last_name']}",
                "price": flight["price"],
                "status": "issued"
            }
            
            # Generate Checkin (50% chance)
            if random.random() > 0.5:
                seat = f"{random.randint(1, 30)}{random.choice(['A', 'B', 'C', 'D', 'E', 'F'])}"
                checkins[bid] = {
                    "booking_id": bid,
                    "seat": seat,
                    "boarding_pass": f"BP{bid[2:]}",
                    "checked_in_at": datetime.datetime.now().isoformat(),
                    "gate": f"{random.choice(['A', 'B', 'C'])}{random.randint(1, 50)}"
                }
                
                # Generate Baggage (50% of checkins)
                if random.random() > 0.5:
                    bag_tag = f"BT{bid[2:]}-1"
                    baggage[bag_tag] = {
                        "bag_tag": bag_tag,
                        "booking_id": bid,
                        "weight": random.randint(15, 25),
                        "status": "checked",
                        "location": flight["origin"]
                    }

    return bookings, tickets, checkins, baggage

def update_yaml(file_path, data_key, new_data):
    path = Path(file_path)
    if not path.exists():
        print(f"❌ File not found: {file_path}")
        return

    content = path.read_text()
    
    # Simple string replacement for the JSON block
    # This assumes the format: "api.json: |" followed by the JSON block
    try:
        start_marker = "api.json: |"
        start_idx = content.find(start_marker)
        if start_idx == -1:
            print(f"❌ JSON marker not found in {file_path}")
            return
            
        # Find the start of the JSON object (first { after marker)
        json_start = content.find("{", start_idx)
        
        # Find the end of the JSON block (this is tricky in YAML)
        # We'll assume the next "---" or end of file marks the end, 
        # but we need to be careful about indentation.
        # A safer way is to construct the new file content.
        
        # Let's reconstruct the file content
        # We know the structure is ConfigMap -> api.json -> JSON
        
        # Create the new JSON string with indentation
        json_str = json.dumps({data_key: new_data}, indent=2)
        # Indent it by 4 spaces
        indented_json = "\n".join("    " + line for line in json_str.splitlines())
        
        # We need to replace the content between "api.json: |" and the next "---"
        # or just rewrite the whole ConfigMap part if we can parse it.
        
        # Let's use a simpler approach: Read the file, find the lines, replace.
        lines = content.splitlines()
        new_lines = []
        in_json = False
        json_replaced = False
        
        for line in lines:
            if "api.json: |" in line:
                new_lines.append(line)
                new_lines.append(indented_json)
                in_json = True
                json_replaced = True
                continue
            
            if in_json:
                # If we hit the next document separator or a top-level key (no indent)
                if line.strip() == "---" or (line and not line.startswith(" ")):
                    in_json = False
                    new_lines.append(line)
                # Else, skip the old JSON lines
            else:
                new_lines.append(line)
                
        path.write_text("\n".join(new_lines) + "\n")
        print(f"✅ Updated {file_path} with {len(new_data)} records")
        
    except Exception as e:
        print(f"❌ Error updating {file_path}: {e}")

def main():
    print("🚀 Generating Airline Data...")
    
    flights = generate_flights()
    passengers = generate_passengers()
    loyalty = generate_loyalty(passengers)
    bookings, tickets, checkins, baggage = generate_bookings(passengers, flights)
    
    # Update Files
    update_yaml(BASE_DIR / "flights/service.yaml", "flights", flights)
    update_yaml(BASE_DIR / "passengers/service.yaml", "passengers", passengers)
    update_yaml(BASE_DIR / "loyalty/service.yaml", "members", loyalty)
    update_yaml(BASE_DIR / "bookings/service.yaml", "bookings", bookings)
    update_yaml(BASE_DIR / "tickets/service.yaml", "tickets", tickets)
    update_yaml(BASE_DIR / "checkin/service.yaml", "checkins", checkins)
    update_yaml(BASE_DIR / "baggage/service.yaml", "baggage", baggage)
    
    print("\n✨ Data Generation Complete!")
    print(f"  - Flights: {len(flights)}")
    print(f"  - Passengers: {len(passengers)}")
    print(f"  - Bookings: {len(bookings)}")
    print(f"  - Tickets: {len(tickets)}")
    print(f"  - Checkins: {len(checkins)}")
    print(f"  - Bags: {len(baggage)}")

if __name__ == "__main__":
    main()
