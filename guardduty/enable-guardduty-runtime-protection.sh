#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
REGION="us-east-1"
# Aceptar perfil como primer argumento, por compatibilidad con el resto de scripts
PROFILE="${1:-azcenit}"

echo "=== Habilitando GuardDuty Runtime Protection ==="
echo "Proveedor: $PROVIDER"
echo "Región: $REGION"
echo "Perfil: $PROFILE"
echo

# Validar credenciales
echo "🔍 Validando credenciales para perfil: $PROFILE"
if ! aws sts get-caller-identity --profile "$PROFILE" >/dev/null 2>&1; then
    echo "❌ Credenciales invalidas para perfil '$PROFILE'"
    echo "💡 Ejecuta: aws configure list --profile $PROFILE"
    exit 1
fi


# Verificar si GuardDuty ya está habilitado en la región
echo "Verificando estado de GuardDuty en $REGION..."
detector=$(aws guardduty list-detectors \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "DetectorIds[0]" \
    --output text 2>/dev/null || echo "None")

if [[ "$detector" == "None" || "$detector" == "null" ]]; then
    echo "GuardDuty no está habilitado. Creando detector con Runtime Protection..."
    detector=$(aws guardduty create-detector \
        --enable \
        --features '[{"Name":"RUNTIME_MONITORING","Status":"ENABLED"}]' \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query "DetectorId" \
        --output text)
    echo "✔ Detector de GuardDuty creado: $detector"
else
    echo "Detector existente encontrado: $detector"
    echo "Habilitando Runtime Protection..."
    aws guardduty update-detector \
        --detector-id "$detector" \
        --features '[{"Name":"RUNTIME_MONITORING","Status":"ENABLED"}]' \
        --region "$REGION" \
        --profile "$PROFILE"
    echo "✔ Runtime Protection habilitado en el detector existente"
fi

# Verificar el estado final
echo
echo "Verificando configuración final..."
detector_info=$(aws guardduty get-detector \
    --detector-id "$detector" \
    --region "$REGION" \
    --profile "$PROFILE")

status=$(echo "$detector_info" | jq -r '.Status')
runtime_status=$(echo "$detector_info" | jq -r '.Features[] | select(.Name=="RUNTIME_MONITORING") | .Status' 2>/dev/null || echo "NOT_FOUND")

echo "Estado del detector: $status"
echo "Runtime Protection: $runtime_status"

if [[ "$status" == "ENABLED" && "$runtime_status" == "ENABLED" ]]; then
    echo
    echo "✅ GuardDuty Runtime Protection habilitado exitosamente en $REGION"
else
    echo
    echo "❌ Error: Verificar la configuración manualmente"
    exit 1
fi

echo
echo "=== Proceso completado ==="