#!/usr/bin/env python3
"""Baggage Service - In-memory stateful API"""
import sys
sys.path.append('/app')
from base_service import run_service

if __name__ == '__main__':
    run_service(
        resource_name='Baggage',
        resource_path='baggage',
        id_field='baggage_id',
        data_file='/api/api.json',
        port=3000
    )
