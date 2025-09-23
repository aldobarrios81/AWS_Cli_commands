#!/bin/bash
# review-s3-replication.sh
# Revisa la configuración de replicación cross-account en todos los buckets S3

REGION="us-east-1"
PROFILE="xxxxxx"

echo "=== Revisando replicación cross-account en buckets S3 en $REGION ==="

# Listar todos los buckets S3
BUCKETS=$(aws s3api list-buckets --profile $PROFILE --query 'Buckets[].Name' --output text)

for BUCKET in $BUCKETS; do
    echo "-> Revisando bucket: $BUCKET"
    REPLICATION=$(aws s3api get-bucket-replication --bucket "$BUCKET" --profile $PROFILE 2>/dev/null)

    if [ -z "$REPLICATION" ]; then
        echo "   ⚠ Sin configuración de replicación"
    else
        echo "   ✔ Configuración de replicación encontrada:"
        echo "$REPLICATION" | jq '.ReplicationConfiguration.Rules[] | {ID, Status, Destination}' 
    fi
done

echo "✅ Revisión de replicación S3 completada"

