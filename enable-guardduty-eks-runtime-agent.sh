#!/bin/bash
# Habilita GuardDuty Runtime Protection y despliega automáticamente el agente en EKS existentes
PROFILE="xxxxxxxx"
REGION="us-east-1"

echo "=== Habilitando GuardDuty Runtime Protection (EKS) en $REGION ==="

# 1️⃣ Verificar/crear detector
DETECTOR_ID=$(aws guardduty list-detectors --region "$REGION" --profile "$PROFILE" --query 'DetectorIds[0]' --output text)
if [ "$DETECTOR_ID" == "None" ] || [ -z "$DETECTOR_ID" ]; then
    echo "No hay detector. Creando uno nuevo..."
    DETECTOR_ID=$(aws guardduty create-detector --enable --region "$REGION" --profile "$PROFILE" --query 'DetectorId' --output text)
    echo "✔ Detector creado: $DETECTOR_ID"
else
    echo "✔ Detector existente: $DETECTOR_ID"
fi

# 2️⃣ Habilitar Runtime Protection
echo "Activando EKS Runtime Monitoring..."
aws guardduty update-detector --detector-id "$DETECTOR_ID" --features Name=EKS_RUNTIME_MONITORING,Status=ENABLED --region "$REGION" --profile "$PROFILE"
echo "✔ Runtime Protection habilitado"

# 3️⃣ Instalar agente en EKS existentes
CLUSTERS=$(aws eks list-clusters --region "$REGION" --profile "$PROFILE" --query 'clusters' --output text)
if [ -z "$CLUSTERS" ]; then
    echo "No se encontraron clústeres EKS en $REGION"
    exit 0
fi

for CLUSTER in $CLUSTERS; do
    echo "-> Verificando add-on GuardDuty en cluster: $CLUSTER"
    EXISTS=$(aws eks describe-addon --cluster-name "$CLUSTER" --addon-name amazon-guardduty-agent --region "$REGION" --profile "$PROFILE" 2>/dev/null)
    if [ -n "$EXISTS" ]; then
        echo "   ✔ Add-on ya instalado en $CLUSTER"
    else
        echo "   -> Instalando add-on en $CLUSTER"
        aws eks create-addon --cluster-name "$CLUSTER" --addon-name amazon-guardduty-agent --region "$REGION" --profile "$PROFILE" || echo "   ⚠ Error instalando add-on en $CLUSTER"
    fi
done

echo "===

