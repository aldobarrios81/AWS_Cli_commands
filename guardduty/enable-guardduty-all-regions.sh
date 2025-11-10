#!/usr/bin/env bash
set -euo pipefail

# Verificar que se proporcione el perfil como parámetro
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
    echo ""
    echo "Ejemplos:"
    echo "  $0 metrokia"
    echo "  $0 AZLOGICA"
    exit 1
fi

PROFILE="$1"
DEFAULT_REGION="us-east-1"   # Región inicial para listar las demás

echo "=== Habilitando Amazon GuardDuty en región principal ==="
echo "Perfil: $PROFILE  |  Región: $DEFAULT_REGION"
echo ""

# Verificar credenciales y mostrar información de la cuenta
echo "🔍 Verificando credenciales para perfil: $PROFILE"
CALLER_IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "❌ Error: Credenciales no válidas para perfil '$PROFILE'"
    echo "Verificar configuración: aws configure list --profile $PROFILE"
    exit 1
fi

ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account' 2>/dev/null)
CURRENT_USER=$(echo "$CALLER_IDENTITY" | jq -r '.Arn' 2>/dev/null)

echo "✅ Credenciales válidas"
echo "   📋 Account ID: $ACCOUNT_ID"
echo "   👤 Usuario/Rol: $CURRENT_USER"
echo ""

# Trabajar solo en la región principal
REGION="$DEFAULT_REGION"
echo "� Habilitando GuardDuty en región principal: $REGION"
echo ""

# Verificar si GuardDuty ya está habilitado
echo "🔍 Verificando estado actual de GuardDuty..."
DETECTOR_ID=$(aws guardduty list-detectors \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "DetectorIds[0]" \
    --output text 2>/dev/null || echo "None")

if [[ "$DETECTOR_ID" != "None" && -n "$DETECTOR_ID" && "$DETECTOR_ID" != "null" ]]; then
    echo "✅ GuardDuty ya está habilitado"
    echo "   📋 Detector ID: $DETECTOR_ID"
    
    # Obtener información detallada del detector
    echo "   🔍 Obteniendo información del detector..."
    DETECTOR_INFO=$(aws guardduty get-detector \
        --detector-id "$DETECTOR_ID" \
        --region "$REGION" \
        --profile "$PROFILE" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        STATUS=$(echo "$DETECTOR_INFO" | jq -r '.Status' 2>/dev/null)
        SERVICE_ROLE=$(echo "$DETECTOR_INFO" | jq -r '.ServiceRole' 2>/dev/null)
        FINDING_FREQUENCY=$(echo "$DETECTOR_INFO" | jq -r '.FindingPublishingFrequency' 2>/dev/null)
        
        echo "   📊 Estado: $STATUS"
        echo "   🎯 Frecuencia de hallazgos: $FINDING_FREQUENCY"
        echo "   🔐 Service Role: $SERVICE_ROLE"
        
        # Verificar características adicionales
        echo "   🔍 Verificando características avanzadas..."
        FEATURES=$(echo "$DETECTOR_INFO" | jq -r '.Features[]? | "\(.Name): \(.Status)"' 2>/dev/null)
        if [ -n "$FEATURES" ]; then
            echo "   🚀 Características habilitadas:"
            while IFS= read -r feature; do
                echo "      - $feature"
            done <<< "$FEATURES"
        else
            echo "   ⚠️ Solo características básicas habilitadas"
        fi
    fi
    
    echo ""
    read -p "¿Deseas actualizar la configuración de GuardDuty? (y/N): " update_config
    if [[ $update_config == [yY] || $update_config == [yY][eE][sS] ]]; then
        echo "🔄 Actualizando configuración de GuardDuty..."
        
        # Actualizar con características mejoradas
        aws guardduty update-detector \
            --detector-id "$DETECTOR_ID" \
            --enable \
            --finding-publishing-frequency FIFTEEN_MINUTES \
            --features '[
                {"Name":"S3_DATA_EVENTS","Status":"ENABLED"},
                {"Name":"EKS_AUDIT_LOGS","Status":"ENABLED"},
                {"Name":"EBS_MALWARE_PROTECTION","Status":"ENABLED"},
                {"Name":"RDS_LOGIN_EVENTS","Status":"ENABLED"},
                {"Name":"EKS_RUNTIME_MONITORING","Status":"ENABLED"},
                {"Name":"LAMBDA_NETWORK_LOGS","Status":"ENABLED"}
            ]' \
            --region "$REGION" \
            --profile "$PROFILE" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "   ✅ Configuración actualizada con características avanzadas"
        else
            echo "   ⚠️ Algunas características avanzadas pueden no estar disponibles en tu región"
            # Intentar configuración básica mejorada
            aws guardduty update-detector \
                --detector-id "$DETECTOR_ID" \
                --enable \
                --finding-publishing-frequency FIFTEEN_MINUTES \
                --region "$REGION" \
                --profile "$PROFILE"
            echo "   ✅ Configuración básica actualizada"
        fi
    fi
else
    echo "🔨 GuardDuty no está habilitado. Creando detector..."
    
    # Crear detector con características avanzadas
    echo "   🚀 Habilitando con características avanzadas..."
    DETECTOR_ID=$(aws guardduty create-detector \
        --enable \
        --finding-publishing-frequency FIFTEEN_MINUTES \
        --features '[
            {"Name":"S3_DATA_EVENTS","Status":"ENABLED"},
            {"Name":"EKS_AUDIT_LOGS","Status":"ENABLED"},
            {"Name":"EBS_MALWARE_PROTECTION","Status":"ENABLED"},
            {"Name":"RDS_LOGIN_EVENTS","Status":"ENABLED"},
            {"Name":"EKS_RUNTIME_MONITORING","Status":"ENABLED"},
            {"Name":"LAMBDA_NETWORK_LOGS","Status":"ENABLED"}
        ]' \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query "DetectorId" \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$DETECTOR_ID" ] && [ "$DETECTOR_ID" != "None" ]; then
        echo "   ✅ GuardDuty habilitado con características avanzadas"
        echo "   📋 Detector ID: $DETECTOR_ID"
    else
        echo "   ⚠️ Creando con configuración básica..."
        DETECTOR_ID=$(aws guardduty create-detector \
            --enable \
            --finding-publishing-frequency FIFTEEN_MINUTES \
            --region "$REGION" \
            --profile "$PROFILE" \
            --query "DetectorId" \
            --output text)
        
        if [ $? -eq 0 ] && [ -n "$DETECTOR_ID" ] && [ "$DETECTOR_ID" != "None" ]; then
            echo "   ✅ GuardDuty habilitado con configuración básica"
            echo "   📋 Detector ID: $DETECTOR_ID"
        else
            echo "   ❌ Error al habilitar GuardDuty"
            exit 1
        fi
    fi
fi

echo ""
echo "=============================================================="
echo "✅ PROCESO COMPLETADO - AMAZON GUARDDUTY"
echo "=============================================================="
echo ""
echo "📊 Resumen:"
echo "  - Región: $REGION"
echo "  - Account ID: $ACCOUNT_ID"
echo "  - Detector ID: $DETECTOR_ID"
echo "  - Estado: HABILITADO"
echo ""
echo "🔍 Verificación manual:"
echo "  aws guardduty get-detector --detector-id $DETECTOR_ID --region $REGION --profile $PROFILE"
echo ""
echo "🌐 Consola AWS:"
echo "  https://$REGION.console.aws.amazon.com/guardduty/home?region=$REGION"
echo ""
echo "💡 Nota: Los hallazgos de GuardDuty pueden tardar unos minutos en aparecer"
echo ""

