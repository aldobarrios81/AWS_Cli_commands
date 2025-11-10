#!/bin/bash
# Uso: ./enable-guardduty-eks-runtime.sh <cluster1> [cluster2 cluster3 ...]
# Habilita GuardDuty y EKS Runtime Protection en us-east-1
# Perfil fijo: xxxxxx

PROFILE="xxxxxxx"
REGION="us-east-1"

if [ "$#" -lt 1 ]; then
    echo "Uso: $0 <cluster1> [cluster2 ...]"
    exit 1
fi

echo "=== Habilitando GuardDuty y EKS Runtime Protection en $REGION ==="

# 1️⃣ Verificar si ya hay un detector
DETECTOR_ID=$(aws guardduty list-detectors \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'DetectorIds[0]' \
  --output text)

if [ "$DETECTOR_ID" == "None" ] || [ -z "$DETECTOR_ID" ]; then
    echo "No hay detector. Creando uno nuevo..."
    DETECTOR_ID=$(aws guardduty create-detector \
      --enable \
      --region "$REGION" \
      --profile "$PROFILE" \
      --query 'DetectorId' \
      --output text)
    echo "✔ Detector creado: $DETECTOR_ID"
else
    echo "✔ Detector existente: $DETECTOR_ID"
fi

# 2️⃣ Activar EKS Runtime Monitoring y Add-on Management
echo "Activando EKS Runtime Monitoring y Add-on Management..."
aws guardduty update-detector \
  --detector-id "$DETECTOR_ID" \
  --features Name=EKS_RUNTIME_MONITORING,Status=ENABLED Name=EKS_ADDON_MANAGEMENT,Status=ENABLED \
  --region "$REGION" \
  --profile "$PROFILE"

echo "✔ GuardDuty EKS Runtime Monitoring habilitado"

# 3️⃣ Instalar add-on en cada clúster EKS
for CLUSTER in "$@"; do
    echo "-> Instalando add-on en cluster: $CLUSTER"
    aws eks create-addon \
      --cluster-name "$CLUSTER" \
      --addon-name amazon-guardduty-agent \
      --region "$REGION" \
      --profile "$PROFILE" || echo "   (Posiblemente ya instalado en $CLUSTER)"
done

echo "=== Proceso completado ==="

