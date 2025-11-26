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
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create Flask app
app = Flask(__name__)
CORS(app)

# In-memory storage
class InMemoryStore:
    def __init__(self, data_file: str, id_field: str = "id"):
        self.id_field = id_field
        self.data: Dict[str, any] = {}
        self.load_initial_data(data_file)
    
    def load_initial_data(self, data_file: str):
        """Load initial data from JSON file"""
        try:
            if os.path.exists(data_file):
                with open(data_file, 'r') as f:
                    raw_data = json.load(f)
                    # Extract the main data object (could be flights, bookings, etc.)
                    for key in raw_data:
                        if isinstance(raw_data[key], dict):
                            self.data = raw_data[key]
                            logger.info(f"Loaded {len(self.data)} records from {data_file}")
                            break
            else:
                logger.warning(f"Data file {data_file} not found, starting empty")
        except Exception as e:
            logger.error(f"Error loading data: {e}")
            self.data = {}
    
    def get_all(self) -> Dict:
        """Get all records"""
        return self.data
    
    def get_by_id(self, record_id: str) -> Optional[Dict]:
        """Get single record by ID"""
        return self.data.get(record_id)
    
    def create(self, record: Dict) -> Dict:
        """Create new record"""
        if self.id_field not in record:
            record[self.id_field] = str(uuid.uuid4())
        
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
    store = InMemoryStore(data_file, id_field)
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
            return jsonify({resource_path: results}), 200
        
        return jsonify({resource_path: store.data}), 200
    
    @app.route(f'/{resource_path}/<record_id>', methods=['GET'])
    def get_one(record_id):
        """Get single record"""
        record = store.get_by_id(record_id)
        if record:
            # Return wrapped or unwrapped based on convention
            return jsonify({resource_path: {record_id: record}}), 200
        return jsonify({"error": "Not found", "status": 404}), 404
    
    @app.route(f'/{resource_path}', methods=['POST'])
    def create():
        """Create new record"""
        data = request.json
        if not data:
            return jsonify({"error": "No data provided"}), 400
        
        record = store.create(data)
        return jsonify({"status": "created", "data": record}), 201
    
    @app.route(f'/{resource_path}/<record_id>', methods=['PUT', 'PATCH'])
    def update(record_id):
        """Update existing record"""
        data = request.json
        if not data:
            return jsonify({"error": "No data provided"}), 400
        
        record = store.update(record_id, data)
        if record:
            return jsonify({"status": "updated", "data": record}), 200
        return jsonify({"error": "Not found"}), 404
    
    @app.route(f'/{resource_path}/<record_id>', methods=['DELETE'])
    def delete(record_id):
        """Delete record"""
        if store.delete(record_id):
            return jsonify({"status": "deleted"}), 200
        return jsonify({"error": "Not found"}), 404
    
    # Special search endpoint
    @app.route(f'/{resource_path}/search', methods=['GET'])
    def search():
        """Search with query parameters"""
        filters = request.args.to_dict()
        results = store.search(**filters)
        return jsonify({resource_path: results}), 200


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
