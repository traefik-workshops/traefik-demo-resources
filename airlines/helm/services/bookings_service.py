#!/usr/bin/env python3
"""Bookings Service - In-memory stateful API"""
import sys
sys.path.append('/app')
from base_service import run_service

if __name__ == '__main__':
    run_service(
        resource_name='Bookings',
        resource_path='bookings',
        id_field='booking_id',
        data_file='/api/api.json',
        port=3000
    )
