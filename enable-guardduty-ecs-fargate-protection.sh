#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
REGION="us-east-1"
PROFILE="azcenit"

echo "=== Habilitando GuardDuty Runtime Protection para ECS Fargate ==="
echo "Proveedor: $PROVIDER"
echo "Región: $REGION"
echo "Perfil: $PROFILE"
echo

# Verificar si GuardDuty ya está habilitado en la región
echo "Verificando estado de GuardDuty en $REGION..."
detector=$(wsl aws guardduty list-detectors \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "DetectorIds[0]" \
    --output text 2>/dev/null || echo "None")

if [[ "$detector" == "None" || "$detector" == "null" ]]; then
    echo "GuardDuty no está habilitado. Creando detector..."
    detector=$(wsl aws guardduty create-detector \
        --enable \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query "DetectorId" \
        --output text)
    echo "✔ Detector de GuardDuty creado: $detector"
else
    echo "Detector existente encontrado: $detector"
fi

# Habilitar Runtime Protection específicamente para ECS Fargate
echo "Habilitando Runtime Protection para ECS/Fargate..."
wsl aws guardduty update-detector \
    --detector-id "$detector" \
    --features '[
        {
            "Name":"RUNTIME_MONITORING",
            "Status":"ENABLED",
            "AdditionalConfiguration":[
                {
                    "Name":"ECS_FARGATE_AGENT_MANAGEMENT",
                    "Status":"ENABLED"
                }
            ]
        }
    ]' \
    --region "$REGION" \
    --profile "$PROFILE"

echo "✔ Runtime Protection habilitado para ECS Fargate"

# Verificar configuraciones específicas de ECS
echo
echo "Verificando configuración de ECS Fargate..."
detector_info=$(wsl aws guardduty get-detector \
    --detector-id "$detector" \
    --region "$REGION" \
    --profile "$PROFILE")

echo "Configuración del detector:"
echo "$detector_info" | grep -E '"Status"|"Name"|"ECS_FARGATE"' || echo "Información de features disponible en la respuesta JSON"

echo
echo "✅ GuardDuty Runtime Protection para ECS Fargate configurado exitosamente en $REGION"
echo
echo "Notas importantes:"
echo "- Runtime Protection monitorea contenedores ECS Fargate automáticamente"
echo "- Los agentes se despliegan automáticamente en tareas nuevas"
echo "- Puede tomar algunos minutos en activarse completamente"
echo
echo "=== Proceso completado ==="