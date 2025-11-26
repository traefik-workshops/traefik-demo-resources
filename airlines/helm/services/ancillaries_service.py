#!/usr/bin/env python3
"""Ancillaries Service - In-memory stateful API"""
import sys
sys.path.append('/app')
from base_service import run_service

if __name__ == '__main__':
    run_service(
        resource_name='Ancillaries',
        resource_path='ancillaries',
        id_field='ancillary_id',
        data_file='/api/api.json',
        port=3000
    )
