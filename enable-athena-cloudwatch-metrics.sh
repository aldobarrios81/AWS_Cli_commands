#!/bin/bash

PROFILE="azcenit"
REGION="us-east-1"

echo "=== Habilitando CloudWatch Metrics Logging para Athena WorkGroups en $REGION ==="
echo "Perfil: $PROFILE"

# Obtener todos los workgroups
WORKGROUPS=$(aws athena list-work-groups --region "$REGION" --profile "$PROFILE" --query "WorkGroups[].Name" --output text)

if [ -z "$WORKGROUPS" ]; then
    echo "⚠ No se encontraron WorkGroups en $REGION"
    exit 0
fi

for WG in $WORKGROUPS; do
    echo "-> Habilitando CloudWatch Metrics Logging para WorkGroup: $WG"

    aws athena update-work-group \
        --region "$REGION" \
        --profile "$PROFILE" \
        --work-group "$WG" \
        --configuration-updates "PublishCloudWatchMetricsEnabled=true" \
        && echo "   ✔ Logging habilitado para $WG" \
        || echo "   ⚠ Error habilitando logging para $WG"
done

echo "=== Proceso completado ✅ ==="

