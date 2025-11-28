#!/usr/bin/env python3
"""Loyalty Service - In-memory stateful API with passenger lookup"""
import sys
sys.path.append('/app')
from base_service import app, init_store, create_rest_api
from flask import jsonify
import base_service

def setup_loyalty_routes():
    """Add loyalty-specific routes"""
    @app.route('/loyalty/passenger/<passenger_id>', methods=['GET'])
    def get_loyalty_by_passenger(passenger_id):
        """Look up loyalty member by passenger_id"""
        if not base_service.store:
            return jsonify({"error": "Service not initialized"}), 500

        # Search through all loyalty records for matching passenger_id
        for member in base_service.store.data.values():
            if member.get('passenger_id') == passenger_id:
                return jsonify(member), 200

        return jsonify({"error": "Not found"}), 404

if __name__ == '__main__':
    # Initialize the store
    init_store('/api/api.json', 'member_id', 'Loyalty')

    # Set up loyalty-specific routes FIRST (before generic CRUD routes)
    setup_loyalty_routes()

    # Then set up standard CRUD routes
    create_rest_api('loyalty')

    # Start the server
    import logging
    logger = logging.getLogger(__name__)
    logger.info(f"Starting Loyalty service on port 3000")
    logger.info(f"Endpoints: /loyalty, /loyalty/<id>, /loyalty/passenger/<passenger_id>, /loyalty/member/<member_id>")
    logger.info(f"Loaded {len(base_service.store.data)} initial records")

    app.run(host='0.0.0.0', port=3000, debug=False)
