#!/bin/bash
# Habilita GuardDuty EKS Runtime Protection en todos los clústeres EKS existentes
# Perfil: xxxxxx | Región fija: us-east-1

PROFILE="xxxxxx"
REGION="us-east-1"

echo "=== Habilitando GuardDuty y EKS Runtime Protection en $REGION ==="

# 1️⃣ Verificar si ya existe un detector
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

# 2️⃣ Habilitar solo EKS Runtime Monitoring
echo "Activando EKS Runtime Monitoring..."
aws guardduty update-detector \
  --detector-id "$DETECTOR_ID" \
  --features Name=EKS_RUNTIME_MONITORING,Status=ENABLED \
  --region "$REGION" \
  --profile "$PROFILE"

echo "✔ GuardDuty EKS Runtime Monitoring habilitado"

# 3️⃣ Listar todos los clústeres EKS existentes
CLUSTERS=$(aws eks list-clusters --region "$REGION" --profile "$PROFILE" --query 'clusters' --output text)

if [ -z "$CLUSTERS" ]; then
    echo "No se encontraron clústeres EKS en $REGION"
    exit 0
fi

# 4️⃣ Instalar add-on GuardDuty en cada clúster
for CLUSTER in $CLUSTERS; do
    echo "-> Verificando add-on GuardDuty en cluster: $CLUSTER"
    EXISTS=$(aws eks describe-addon \
      --cluster-name "$CLUSTER" \
      --addon-name amazon-guardduty-agent \
      --region "$REGION" \
      --profile "$PROFILE" 2>/dev/null)

    if [ -n "$EXISTS" ]; then
        echo "   ✔ Add-on ya instalado en $CLUSTER"
    else
        echo "   -> Instalando add-on en $CLUSTER"
        aws eks create-addon \
          --cluster-name "$CLUSTER" \
          --addon-name amazon-guardduty-agent \
          --region "$REGION" \
          --profile "$PROFILE" || echo "   ⚠ Error instalando add-on en $CLUSTER"
    fi
done

echo "=== Proceso completado ==="

