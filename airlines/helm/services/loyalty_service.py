#!/usr/bin/env python3
"""Loyalty Service - In-memory stateful API"""
import sys
sys.path.append('/app')
from base_service import run_service

if __name__ == '__main__':
    run_service(
        resource_name='Loyalty',
        resource_path='loyalty',
        id_field='member_id',
        data_file='/api/api.json',
        port=3000
    )
