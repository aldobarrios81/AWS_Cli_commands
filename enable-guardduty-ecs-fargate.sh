#!/bin/bash
# Habilita GuardDuty Runtime Protection para ECS (Fargate) en la región
PROFILE="xxxxxxxx"
REGION="us-east-1"

echo "=== Habilitando GuardDuty Runtime Protection (general) en $REGION ==="

# 1️⃣ Verificar o crear detector
DETECTOR_ID=$(aws guardduty list-detectors --region "$REGION" --profile "$PROFILE" --query 'DetectorIds[0]' --output text)
if [ "$DETECTOR_ID" == "None" ] || [ -z "$DETECTOR_ID" ]; then
    echo "No hay detector. Creando uno nuevo..."
    DETECTOR_ID=$(aws guardduty create-detector --enable --region "$REGION" --profile "$PROFILE" --query 'DetectorId' --output text)
    echo "✔ Detector creado: $DETECTOR_ID"
else
    echo "✔ Detector existente: $DETECTOR_ID"
fi

# 2️⃣ Activar Runtime Protection general (EKS + ECS/Fargate)
echo "Activando GuardDuty Runtime Monitoring..."
aws guardduty update-detector \
    --detector-id "$DETECTOR_ID" \
    --features Name=RUNTIME_MONITORING,Status=ENABLED \
    --region "$REGION" \
    --profile "$PROFILE"

echo "✔ GuardDuty Runtime Protection habilitado para EKS y ECS Fargate"
echo "=== Proceso completado ==="

