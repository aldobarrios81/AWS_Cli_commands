#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
REGION="us-east-1"
PROFILE="azbeacons"

echo "=== Habilitando GuardDuty Runtime Protection para EC2 con Agentes Automáticos ==="
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

# Habilitar Runtime Protection específicamente para EC2 con gestión automática de agentes
echo
echo "Habilitando Runtime Protection para EC2 con configuración automática de agentes..."
wsl aws guardduty update-detector \
    --detector-id "$detector" \
    --features '[
        {
            "Name":"RUNTIME_MONITORING",
            "Status":"ENABLED",
            "AdditionalConfiguration":[
                {
                    "Name":"EC2_AGENT_MANAGEMENT",
                    "Status":"ENABLED"
                }
            ]
        }
    ]' \
    --region "$REGION" \
    --profile "$PROFILE"

echo "✔ Runtime Protection habilitado para EC2 con gestión automática de agentes"

# Verificar configuraciones específicas de EC2
echo
echo "Verificando configuración de EC2 Runtime Protection..."
detector_info=$(wsl aws guardduty get-detector \
    --detector-id "$detector" \
    --region "$REGION" \
    --profile "$PROFILE")

echo "Configuración del detector:"
echo "$detector_info" | grep -E '"Status"|"Name"|"EC2_AGENT"' || echo "Información de features disponible en la respuesta JSON"

# Mostrar instancias EC2 existentes que se beneficiarán
echo
echo "Verificando instancias EC2 existentes en la región..."
instances=$(wsl aws ec2 describe-instances \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Reservations[].Instances[?State.Name=='running'].{InstanceId:InstanceId,InstanceType:InstanceType,Platform:Platform}" \
    --output table 2>/dev/null || echo "No se pudieron listar las instancias")

if [[ "$instances" != "No se pudieron listar las instancias" ]]; then
    echo "Instancias EC2 running que se beneficiarán del Runtime Protection:"
    echo "$instances"
else
    echo "No se encontraron instancias EC2 running o no se pudieron listar"
fi

echo
echo "✅ GuardDuty Runtime Protection para EC2 configurado exitosamente en $REGION"
echo
echo "Notas importantes:"
echo "- Los agentes GuardDuty se instalarán automáticamente en instancias EC2 existentes"
echo "- Las nuevas instancias EC2 tendrán el agente instalado automáticamente"
echo "- El agente monitorea procesos, conexiones de red y actividad del sistema de archivos"
echo "- Compatible con Amazon Linux, Ubuntu, RHEL, CentOS, SUSE y Windows"
echo "- No requiere configuración manual en las instancias"
echo "- Puede tomar algunos minutos en desplegarse en instancias existentes"
echo
echo "=== Proceso completado ==="