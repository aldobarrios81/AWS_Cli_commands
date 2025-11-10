#!/usr/bin/env bash
set -euo pipefail

PROFILE="xxxxxxx"
DEFAULT_REGION="us-east-1"

echo "=== Habilitando GuardDuty con Runtime Protection en todas las regiones ==="
echo "Perfil: $PROFILE  |  Región inicial: $DEFAULT_REGION"

# 1. Obtener todas las regiones habilitadas en la cuenta
REGIONS=$(aws ec2 describe-regions \
    --region "$DEFAULT_REGION" \
    --profile "$PROFILE" \
    --query "Regions[].RegionName" \
    --output text)

for region in $REGIONS; do
    echo
    echo "-> Región: $region"

    # 2. Verificar si GuardDuty ya está habilitado
    detector=$(aws guardduty list-detectors \
        --region "$region" \
        --profile "$PROFILE" \
        --query "DetectorIds[0]" \
        --output text)

    if [[ "$detector" == "None" ]]; then
        echo "   Creando detector de GuardDuty con Runtime Protection..."
        detector=$(aws guardduty create-detector \
            --enable \
            --features '[{"Name":"RUNTIME_MONITORING","Status":"ENABLED"}]' \
            --region "$region" \
            --profile "$PROFILE" \
            --query "DetectorId" \
            --output text)
    else
        echo "   Detector existente: $detector"
        echo "   Habilitando Runtime Protection si no estaba activo..."
        aws guardduty update-detector \
            --detector-id "$detector" \
            --features '[{"Name":"RUNTIME_MONITORING","Status":"ENABLED"}]' \
            --region "$region" \
            --profile "$PROFILE"
    fi

    echo "   ✔ GuardDuty con Runtime Protection habilitado en $region"
done

echo
echo "=== Proceso completado: GuardDuty + Runtime Protection habilitado en todas las regiones ==="

