#!/bin/bash
# enable-ec2-detailed-monitoring.sh
# Habilita Detailed Monitoring en todas las instancias EC2

PROFILE="xxxxxxx"
REGION="us-east-1"

echo "=== Habilitando Detailed Monitoring para todas las instancias EC2 en $REGION ==="
INSTANCES=$(aws ec2 describe-instances \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text \
    --profile $PROFILE \
    --region $REGION)

if [ -z "$INSTANCES" ]; then
    echo "⚠ No se encontraron instancias EC2 en $REGION"
    exit 0
fi

for INSTANCE in $INSTANCES; do
    echo "-> Habilitando Detailed Monitoring para instancia: $INSTANCE"
    aws ec2 monitor-instances \
        --instance-ids $INSTANCE \
        --profile $PROFILE \
        --region $REGION
    echo "   ✔ Monitoring habilitado para $INSTANCE"
done

echo "=== Detailed Monitoring habilitado para todas las instancias ✅ ==="

