#!/bin/bash
# Generate all remaining airline service entry points

cd "$(dirname "$0")"

# Service configurations: service_name:resource_path:id_field
services=(
    "tickets:tickets:ticket_id"
    "passengers:passengers:passenger_id"
    "pricing:pricing:pricing_id"
    "baggage:baggage:baggage_id"
    "notifications:notifications:notification_id"
    "ancillaries:ancillaries:ancillary_id"
)

# Generate each service
for service_config in "${services[@]}"; do
    IFS=':' read -r service_name resource_path id_field <<< "$service_config"
    
    # Capitalize first letter for service name
    service_display=$(echo "$service_name" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
    
    cat > "${service_name}_service.py" <<EOF
#!/usr/bin/env python3
"""${service_display} Service - In-memory stateful API"""
import sys
sys.path.append('/app')
from base_service import run_service

if __name__ == '__main__':
    run_service(
        resource_name='${service_display}',
        resource_path='${resource_path}',
        id_field='${id_field}',
        data_file='/api/api.json',
        port=3000
    )
EOF
    
    chmod +x "${service_name}_service.py"
    echo "✅ Created ${service_name}_service.py"
done

echo ""
echo "✅ All service entry points created!"
echo ""
echo "Services generated:"
for service_config in "${services[@]}"; do
    IFS=':' read -r service_name resource_path id_field <<< "$service_config"
    echo "  - ${service_name}_service.py → /${resource_path}"
done
