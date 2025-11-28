#!/usr/bin/env python3
"""
Stateful In-Memory API Service
Generic base for all airline microservices
Supports full CRUD operations with in-memory storage
"""

import json
import logging
from typing import Dict, List, Optional
from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS
import uuid
import random
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create Flask app
app = Flask(__name__)
CORS(app)

# In-memory storage
class InMemoryStore:
    def __init__(self, data_file: str, id_field: str = "id", resource_name: Optional[str] = None):
        self.id_field = id_field
        self.resource_name = resource_name
        self.data: Dict[str, any] = {}
        self.raw_data: Dict[str, any] = {}
        self.load_initial_data(data_file)
    
    def load_initial_data(self, data_file: str):
        """Load initial data from JSON file"""
        try:
            if os.path.exists(data_file):
                with open(data_file, 'r') as f:
                    raw_data = json.load(f)
                    self.raw_data = raw_data
                    # Extract the main data object (could be flights, bookings, etc.)
                    for key in raw_data:
                        if isinstance(raw_data[key], dict):
                            self.data = raw_data[key]
                            logger.info(f"Loaded {len(self.data)} records from {data_file}")
                            break
            else:
                logger.warning(f"Data file {data_file} not found, starting empty")
                self.raw_data = {}
        except Exception as e:
            logger.error(f"Error loading data: {e}")
            self.data = {}
            self.raw_data = {}
    
    def _generate_id(self) -> str:
        """Generate a new record ID consistent with seeded data."""
        # Booking IDs use the BK###### pattern in seed data
        if self.resource_name == "Bookings" and self.id_field == "booking_id":
            while True:
                new_id = f"BK{random.randint(100000, 999999)}"
                if new_id not in self.data:
                    return new_id
        # Default: UUID
        return str(uuid.uuid4())
    
    def get_all(self) -> Dict:
        """Get all records"""
        return self.data
    
    def get_by_id(self, record_id: str) -> Optional[Dict]:
        """Get single record by ID"""
        return self.data.get(record_id)
    
    def create(self, record: Dict) -> Dict:
        """Create new record"""
        if self.id_field not in record or not record.get(self.id_field):
            record[self.id_field] = self._generate_id()
        
        record_id = record[self.id_field]
        self.data[record_id] = record
        logger.info(f"Created record: {record_id}")
        return record
    
    def update(self, record_id: str, updates: Dict) -> Optional[Dict]:
        """Update existing record"""
        if record_id not in self.data:
            return None
        
        self.data[record_id].update(updates)
        logger.info(f"Updated record: {record_id}")
        return self.data[record_id]
    
    def delete(self, record_id: str) -> bool:
        """Delete record"""
        if record_id in self.data:
            del self.data[record_id]
            logger.info(f"Deleted record: {record_id}")
            return True
        return False
    
    def search(self, **filters) -> List[Dict]:
        """Search records by filters"""
        results = []
        for record in self.data.values():
            match = True
            for key, value in filters.items():
                if key in record and record[key] != value:
                    match = False
                    break
            if match:
                results.append(record)
        return results


# Initialize store (will be set by service-specific code)
store: Optional[InMemoryStore] = None

def init_store(data_file: str, id_field: str, resource_name: str):
    """Initialize the data store"""
    global store, RESOURCE_NAME
    store = InMemoryStore(data_file, id_field, resource_name)
    RESOURCE_NAME = resource_name
    logger.info(f"Initialized {resource_name} service with {len(store.data)} records")

# Generic routes
@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "records": len(store.data) if store else 0}), 200

@app.route('/openapi.yaml', methods=['GET'])
def openapi():
    """Serve OpenAPI spec if available"""
    openapi_file = os.getenv('OPENAPI_FILE', '/public/openapi.yaml')
    if os.path.exists(openapi_file):
        with open(openapi_file, 'r') as f:
            return f.read(), 200, {'Content-Type': 'application/x-yaml'}
    return "OpenAPI spec not found", 404

def create_rest_api(resource_path: str):
    """Create RESTful API routes for a resource"""
    
    @app.route(f'/{resource_path}', methods=['GET'])
    def list_all():
        """List all records"""
        # Support query parameters for filtering
        filters = request.args.to_dict()

        if filters:
            results = store.search(**filters)
            return jsonify(results), 200

        # Return array of all records
        return jsonify(list(store.data.values())), 200
    
    @app.route(f'/{resource_path}/<record_id>', methods=['GET'])
    def get_one(record_id):
        """Get single record"""
        record = store.get_by_id(record_id)
        if record:
            # Return single record object directly
            return jsonify(record), 200
        return jsonify({"error": "Not found", "status": 404}), 404
    
    @app.route(f'/{resource_path}', methods=['POST'])
    def create():
        """Create new record"""
        data = request.get_json(silent=True) or {}
        if not data:
            return jsonify({"error": "No data provided"}), 400
        
        record = store.create(data)
        return jsonify({"status": "created", "data": record}), 201
    
    @app.route(f'/{resource_path}/<record_id>', methods=['PUT', 'PATCH'])
    def update(record_id):
        """Update existing record"""
        data = request.get_json(silent=True)
        if data is None:
            data = {}

        # If record doesn't exist, still return 404
        existing = store.get_by_id(record_id)
        if not existing:
            return jsonify({"error": "Not found"}), 404

        # If no updates provided, act as a no-op update and return the current record
        if not data:
            return jsonify({"status": "updated", "data": existing}), 200

        record = store.update(record_id, data)
        return jsonify({"status": "updated", "data": record}), 200
    
    @app.route(f'/{resource_path}/<record_id>', methods=['DELETE'])
    def delete(record_id):
        """Delete record"""
        if RESOURCE_NAME == "Bookings":
            # Bookings API expects 204 No Content on successful cancel
            existing = store.get_by_id(record_id)
            if existing:
                store.update(record_id, {"status": "cancelled"})
            return "", 204

        if store.delete(record_id):
            return jsonify({"status": "deleted"}), 200
        return jsonify({"error": "Not found"}), 404
    
    # Special search endpoint
    @app.route(f'/{resource_path}/search', methods=['GET'])
    def search():
        """Search with query parameters"""
        filters = request.args.to_dict()
        results = store.search(**filters)
        return jsonify(results), 200

    # Service-specific extra routes
    # Loyalty API: lookup by passenger_id and member_id
    if resource_path == 'loyalty':
        @app.route('/loyalty/<passenger_id>', methods=['GET'])
        def get_loyalty_status(passenger_id):
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            member = None
            for m in store.data.values():
                if m.get('passenger_id') == passenger_id:
                    member = m
                    break
            if member:
                return jsonify(member), 200
            return jsonify({"error": "Not found"}), 404

        @app.route('/loyalty/member/<member_id>', methods=['GET'])
        def get_loyalty_member(member_id):
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            member = store.get_by_id(member_id)
            if member:
                return jsonify(member), 200
            return jsonify({"error": "Not found"}), 404

    # Checkin API: boarding pass by booking ID
    if resource_path == 'checkin':
        @app.route('/checkin/<booking_id>/boarding-pass', methods=['GET'])
        def get_boarding_pass(booking_id):
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            record = store.get_by_id(booking_id)
            if record:
                return jsonify(record), 200
            return jsonify({"error": "Not found"}), 404

    # Baggage API: add, track, and list baggage for a booking
    if resource_path == 'baggage':
        @app.route('/baggage/add', methods=['POST'])
        def add_baggage():
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            data = request.get_json(silent=True) or {}
            booking_id = data.get('booking_id')
            bags = int(data.get('bags', 1)) if data.get('bags') is not None else 1
            if not booking_id:
                return jsonify({"error": "booking_id required"}), 400

            raw = store.raw_data or {}
            booking_map = raw.setdefault('baggage/booking', {})
            baggage_map = raw.setdefault('baggage', {})

            new_records = []
            existing_for_booking = booking_map.setdefault(booking_id, [])
            for _ in range(bags):
                bag_tag = f"BT{booking_id}-{len(baggage_map) + 1}"
                rec = {
                    "bag_tag": bag_tag,
                    "booking_id": booking_id,
                    "weight": data.get('weight', 20),
                    "status": "checked",
                    "location": data.get('location', "JFK"),
                }
                existing_for_booking.append(rec)
                baggage_map[bag_tag] = rec
                new_records.append(rec)

            store.raw_data = raw
            return jsonify({"baggage": new_records}), 201

        @app.route('/baggage/track/<bag_tag>', methods=['GET'])
        def track_baggage(bag_tag):
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            raw = store.raw_data or {}
            baggage_map = raw.get('baggage', {})
            rec = baggage_map.get(bag_tag)
            if rec:
                return jsonify(rec), 200
            return jsonify({"error": "Not found"}), 404

        @app.route('/baggage/track/<bag_tag>', methods=['PUT'])
        def update_baggage(bag_tag):
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            data = request.get_json(silent=True) or {}
            raw = store.raw_data or {}
            baggage_map = raw.get('baggage', {})
            rec = baggage_map.get(bag_tag)
            if not rec:
                return jsonify({"error": "Not found"}), 404
            rec.update(data)
            baggage_map[bag_tag] = rec
            raw['baggage'] = baggage_map
            store.raw_data = raw
            return jsonify(rec), 200

        @app.route('/baggage/booking/<booking_id>', methods=['GET'])
        def get_baggage_for_booking(booking_id):
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            raw = store.raw_data or {}
            booking_map = raw.get('baggage/booking', {})
            bags = booking_map.get(booking_id, [])
            return jsonify(bags), 200

    # Pricing API: calculate total price
    if resource_path == 'pricing':
        @app.route('/pricing/calculate', methods=['POST'])
        def calculate_pricing():
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            data = request.get_json(silent=True) or {}
            flight_id = data.get('flight_id')
            travel_class = data.get('class')

            pricing_table = store.data or {}
            taxes_fees = (store.raw_data or {}).get('taxes_fees', {})

            result = None
            # Try flight-specific pricing first
            if flight_id and flight_id in pricing_table:
                result = pricing_table.get(flight_id)

            # Fallback to a default pricing entry
            if not result:
                result = pricing_table.get('FL123', {"base_fare": 400, "taxes": taxes_fees.get('domestic', 50), "total": 450})

            # Ensure numeric fields are present
            base_fare = float(result.get('base_fare', 0))
            taxes = float(result.get('taxes', taxes_fees.get('domestic', 0)))
            total = float(result.get('total', base_fare + taxes))

            payload = {"base_fare": base_fare, "taxes": taxes, "total": total}
            return jsonify(payload), 201

    # Ancillaries API: meals and seat upgrades
    if resource_path == 'ancillaries':
        @app.route('/ancillaries/meals', methods=['GET'])
        def get_meal_options():
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            meals = (store.raw_data or {}).get('meals', {})
            return jsonify(meals), 200

        @app.route('/ancillaries/meal', methods=['POST'])
        def record_meal_preference():
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            data = request.get_json(silent=True) or {}
            booking_id = data.get('booking_id') or request.args.get('booking_id')
            preference = data.get('preference') or request.args.get('preference')
            if not booking_id or not preference:
                return jsonify({"error": "booking_id and preference required"}), 400
            result = {
                "booking_id": booking_id,
                "preference": preference,
                "status": "recorded",
            }
            return jsonify(result), 201

        @app.route('/ancillaries/seat-upgrade', methods=['POST'])
        def upgrade_seat():
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            data = request.get_json(silent=True) or {}
            booking_id = data.get('booking_id')
            new_seat = data.get('new_seat')
            if not booking_id or not new_seat:
                return jsonify({"error": "booking_id and new_seat required"}), 400
            result = {
                "booking_id": booking_id,
                "new_seat": new_seat,
                "status": "upgraded",
            }
            return jsonify(result), 201

    # Notifications API: send and history
    if resource_path == 'notifications':
        @app.route('/notifications/send', methods=['POST'])
        def send_notification():
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            data = request.get_json(silent=True) or {}
            notif_type = data.get('type')
            recipient = data.get('recipient')
            booking_id = data.get('booking_id')
            bag_tag = data.get('bag_tag')

            raw = store.raw_data or {}
            templates = raw.get('templates', {})
            template = templates.get(notif_type, {})
            subject = template.get('subject', 'Notification')
            body_template = template.get('body', '')
            body = body_template.replace('{booking_id}', booking_id or '').replace('{bag_tag}', bag_tag or '')

            result = {
                "type": notif_type,
                "recipient": recipient,
                "subject": subject,
                "body": body,
                "booking_id": booking_id,
                "bag_tag": bag_tag,
            }

            history = raw.setdefault('history', {})
            history.setdefault(recipient or 'unknown', []).append(result)
            store.raw_data = raw

            return jsonify(result), 201

        @app.route('/notifications/history/<recipient_id>', methods=['GET'])
        def get_notification_history(recipient_id):
            if not store:
                return jsonify({"error": "Service not initialized"}), 500
            raw = store.raw_data or {}
            history = raw.get('history', {})
            items = history.get(recipient_id, [])
            return jsonify(items), 200


def run_service(resource_name: str, resource_path: str, id_field: str, data_file: str = "/api/api.json", port: int = 3000):
    """Run the service"""
    init_store(data_file, id_field, resource_name)
    create_rest_api(resource_path)
    
    logger.info(f"Starting {resource_name} service on port {port}")
    logger.info(f"Endpoints: /{resource_path}, /{resource_path}/<id>, /{resource_path}/search")
    logger.info(f"Loaded {len(store.data)} initial records")
    
    app.run(host='0.0.0.0', port=port, debug=False)


if __name__ == '__main__':
    # Can be run directly for testing
    run_service(
        resource_name=os.getenv('SERVICE_NAME', 'generic'),
        resource_path=os.getenv('RESOURCE_PATH', 'items'),
        id_field=os.getenv('ID_FIELD', 'id'),
        data_file=os.getenv('DATA_FILE', '/api/api.json'),
        port=int(os.getenv('PORT', '3000'))
    )
