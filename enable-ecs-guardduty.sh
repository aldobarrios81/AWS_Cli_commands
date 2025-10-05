#!/bin/bash
set -euo pipefail

PROFILE="azcenit"
REGION="us-east-1"

echo "=== Obteniendo Detector de GuardDuty en $REGION ==="
DETECTOR_ID=$(aws guardduty list-detectors \
  --profile $PROFILE \
  --region $REGION \
  --query "DetectorIds[0]" \
  --output text)

if [ "$DETECTOR_ID" == "None" ] || [ -z "$DETECTOR_ID" ]; then
  echo "No existe detector, creando uno..."
  DETECTOR_ID=$(aws guardduty create-detector \
    --enable \
    --profile $PROFILE \
    --region $REGION \
    --query "DetectorId" \
    --output text)
  echo "Detector creado: $DETECTOR_ID"
else
  echo "Detector existente: $DETECTOR_ID"
fi

echo "=== Habilitando GuardDuty Runtime Protection para ECS Fargate ==="
aws guardduty update-detector \
  --detector-id $DETECTOR_ID \
  --features '[
    {
      "Name": "ECS_FARGATE_RUNTIME_MONITORING",
      "Status": "ENABLED"
    }
  ]' \
  --region $REGION \
  --profile $PROFILE

echo "=== Verificando configuración actual ==="
aws guardduty get-detector \
  --detector-id $DETECTOR_ID \
  --region $REGION \
  --profile $PROFILE \
  --query "Features"

