#!/usr/bin/env python3
"""Notifications Service - In-memory stateful API"""
import sys
sys.path.append('/app')
from base_service import run_service

if __name__ == '__main__':
    run_service(
        resource_name='Notifications',
        resource_path='notifications',
        id_field='notification_id',
        data_file='/api/api.json',
        port=3000
    )
