#!/usr/bin/env bash
set -euo pipefail

PROFILE="xxxxxxx"
DEFAULT_REGION="us-east-1"   # Región inicial para listar las demás

echo "=== Habilitando Amazon GuardDuty en todas las regiones ==="
echo "Perfil: $PROFILE  |  Región inicial: $DEFAULT_REGION"

# 1. Obtener todas las regiones habilitadas en la cuenta
REGIONS=$(aws ec2 describe-regions \
    --region "$DEFAULT_REGION" \
    --profile "$PROFILE" \
    --query "Regions[].RegionName" \
    --output text)

# 2. Crear detector en cada región si no existe
for region in $REGIONS; do
    echo
    echo "-> Región: $region"

    DETECTOR_ID=$(aws guardduty list-detectors \
        --region "$region" \
        --profile "$PROFILE" \
        --query "DetectorIds[0]" \
        --output text 2>/dev/null || true)

    if [[ "$DETECTOR_ID" != "None" && -n "$DETECTOR_ID" ]]; then
        echo "   GuardDuty ya está habilitado (Detector ID: $DETECTOR_ID)."
    else
        echo "   Habilitando GuardDuty en $region..."
        DETECTOR_ID=$(aws guardduty create-detector \
            --enable \
            --region "$region" \
            --profile "$PROFILE" \
            --query "DetectorId" \
            --output text)
        echo "   GuardDuty habilitado. Detector ID: $DETECTOR_ID"
    fi
done

echo
echo "=== GuardDuty habilitado en todas las regiones de tu cuenta ==="

