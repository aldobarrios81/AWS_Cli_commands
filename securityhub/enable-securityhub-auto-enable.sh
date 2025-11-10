#!/bin/bash
# enable-securityhub-auto-enable.sh
# Habilita AWS Security Hub con estándares y controles de seguridad

set -e

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
REGION="us-east-1"

echo "=== Habilitando AWS Security Hub ==="
echo "Perfil: $PROFILE | Región: $REGION"
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

# Determinar ARN del estándar según la región
STANDARD_ARN="arn:aws:securityhub:$REGION::standards/aws-foundational-security-best-practices/v/1.0.0"

# Verificar si Security Hub ya está habilitado
echo "🛡️ Verificando estado de Security Hub..."
SH_STATUS=$(aws securityhub describe-hub \
    --profile "$PROFILE" \
    --region "$REGION" 2>/dev/null || echo "NOT_ENABLED")

if [[ "$SH_STATUS" == "NOT_ENABLED" ]]; then
    echo "🔨 Habilitando Security Hub en $REGION..."
    aws securityhub enable-security-hub \
        --enable-default-standards \
        --profile "$PROFILE" \
        --region "$REGION"
    
    if [ $? -eq 0 ]; then
        echo "✅ Security Hub habilitado exitosamente"
        
        # Esperar un momento para que se inicialice
        echo "⏳ Esperando inicialización de Security Hub..."
        sleep 10
    else
        echo "❌ Error habilitando Security Hub"
        exit 1
    fi
else
    echo "✅ Security Hub ya está habilitado"
    
    # Obtener información detallada
    HUB_ARN=$(echo "$SH_STATUS" | jq -r '.HubArn' 2>/dev/null)
    SUBSCRIBED_AT=$(echo "$SH_STATUS" | jq -r '.SubscribedAt' 2>/dev/null)
    AUTO_ENABLE=$(echo "$SH_STATUS" | jq -r '.AutoEnableControls' 2>/dev/null)
    
    echo "   📋 Hub ARN: $HUB_ARN"
    echo "   📅 Habilitado: $(date -d "$SUBSCRIBED_AT" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$SUBSCRIBED_AT")"
    echo "   🔄 Auto-enable controles: $AUTO_ENABLE"
fi

echo ""
echo "📊 Verificando y habilitando estándares de seguridad..."

# Verificar estándares ya habilitados
ENABLED_STANDARDS=$(aws securityhub get-enabled-standards \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query "StandardsSubscriptions" \
    --output json 2>/dev/null || echo "[]")

# Lista de estándares a habilitar
STANDARDS_TO_ENABLE=(
    "arn:aws:securityhub:$REGION::standards/aws-foundational-security-best-practices/v/1.0.0"
    "arn:aws:securityhub:$REGION::standards/cis-aws-foundations-benchmark/v/1.2.0"
)

echo "📋 Estándares a verificar/habilitar:"
for std in "${STANDARDS_TO_ENABLE[@]}"; do
    STD_NAME=$(basename "$std" | cut -d'/' -f1)
    echo "   - $STD_NAME"
done

echo ""

STANDARDS_ENABLED=0
STANDARDS_ALREADY_ENABLED=0

for STANDARD_ARN in "${STANDARDS_TO_ENABLE[@]}"; do
    STD_NAME=$(basename "$STANDARD_ARN" | cut -d'/' -f1)
    echo "🔍 Verificando estándar: $STD_NAME"
    
    # Verificar si ya está habilitado
    IS_ENABLED=$(echo "$ENABLED_STANDARDS" | jq -r --arg arn "$STANDARD_ARN" '.[] | select(.StandardsArn == $arn) | .StandardsArn' 2>/dev/null)
    
    if [ -n "$IS_ENABLED" ] && [ "$IS_ENABLED" != "null" ]; then
        echo "   ✅ Ya está habilitado"
        STANDARDS_ALREADY_ENABLED=$((STANDARDS_ALREADY_ENABLED + 1))
        
        # Obtener información del estándar
        STD_INFO=$(echo "$ENABLED_STANDARDS" | jq -r --arg arn "$STANDARD_ARN" '.[] | select(.StandardsArn == $arn)')
        STD_STATUS=$(echo "$STD_INFO" | jq -r '.StandardsStatus' 2>/dev/null)
        STD_SUB_ARN=$(echo "$STD_INFO" | jq -r '.StandardsSubscriptionArn' 2>/dev/null)
        
        echo "      📊 Estado: $STD_STATUS"
        echo "      🔗 Subscription ARN: $STD_SUB_ARN"
    else
        echo "   🔨 Habilitando estándar..."
        SUBSCRIPTION_RESULT=$(aws securityhub batch-enable-standards \
            --standards-subscription-requests StandardsArn="$STANDARD_ARN" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --output json 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$SUBSCRIPTION_RESULT" ]; then
            echo "   ✅ Estándar habilitado exitosamente"
            STANDARDS_ENABLED=$((STANDARDS_ENABLED + 1))
            
            SUB_ARN=$(echo "$SUBSCRIPTION_RESULT" | jq -r '.StandardsSubscriptions[0].StandardsSubscriptionArn' 2>/dev/null)
            echo "      🔗 Subscription ARN: $SUB_ARN"
        else
            echo "   ❌ Error habilitando estándar"
        fi
    fi
    echo ""
done

# Verificar y configurar auto-enable de controles
echo "🔄 Configurando auto-enable para controles..."
aws securityhub update-organization-configuration \
    --auto-enable \
    --auto-enable-standards SecurityStandard=AWSFoundationalSecurityBestPractices \
    --profile "$PROFILE" \
    --region "$REGION" 2>/dev/null || echo "ℹ️ Auto-enable organizacional no disponible (cuenta individual)"

# Configurar auto-enable para la cuenta actual
aws securityhub update-security-hub-configuration \
    --auto-enable-controls \
    --profile "$PROFILE" \
    --region "$REGION" 2>/dev/null || echo "ℹ️ Auto-enable de controles configurado a nivel de estándar"

echo "✅ Auto-enable configurado para nuevos controles"

# Obtener estadísticas de controles
echo ""
echo "📊 Obteniendo estadísticas de controles..."

TOTAL_CONTROLS=0
ENABLED_CONTROLS=0
DISABLED_CONTROLS=0

# Obtener información actualizada de estándares habilitados
CURRENT_STANDARDS=$(aws securityhub get-enabled-standards \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query "StandardsSubscriptions" \
    --output json 2>/dev/null)

if [ -n "$CURRENT_STANDARDS" ] && [ "$CURRENT_STANDARDS" != "[]" ]; then
    echo "$CURRENT_STANDARDS" | jq -r '.[].StandardsSubscriptionArn' | while read -r sub_arn; do
        if [ -n "$sub_arn" ] && [ "$sub_arn" != "null" ]; then
            STD_NAME=$(echo "$sub_arn" | grep -o '[^/]*\-[^/]*$' | head -1)
            echo "   🔍 Analizando controles de: $STD_NAME"
            
            CONTROLS_INFO=$(aws securityhub describe-standards-controls \
                --standards-subscription-arn "$sub_arn" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query "Controls[].{Status:ControlStatus,Id:ControlId}" \
                --output json 2>/dev/null)
            
            if [ -n "$CONTROLS_INFO" ] && [ "$CONTROLS_INFO" != "[]" ]; then
                STD_TOTAL=$(echo "$CONTROLS_INFO" | jq '. | length')
                STD_ENABLED=$(echo "$CONTROLS_INFO" | jq '[.[] | select(.Status == "ENABLED")] | length')
                STD_DISABLED=$(echo "$CONTROLS_INFO" | jq '[.[] | select(.Status == "DISABLED")] | length')
                
                echo "      📋 Total: $STD_TOTAL | ✅ Habilitados: $STD_ENABLED | ❌ Deshabilitados: $STD_DISABLED"
                
                TOTAL_CONTROLS=$((TOTAL_CONTROLS + STD_TOTAL))
                ENABLED_CONTROLS=$((ENABLED_CONTROLS + STD_ENABLED))
                DISABLED_CONTROLS=$((DISABLED_CONTROLS + STD_DISABLED))
            fi
        fi
    done
fi

# Verificar integraciones automáticas
echo ""
echo "🔗 Verificando integraciones automáticas..."

INTEGRATIONS=$(aws securityhub list-enabled-products-for-import \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query "ProductArns" \
    --output json 2>/dev/null || echo "[]")

if [ -n "$INTEGRATIONS" ] && [ "$INTEGRATIONS" != "[]" ]; then
    INTEGRATION_COUNT=$(echo "$INTEGRATIONS" | jq '. | length')
    echo "✅ Integraciones habilitadas: $INTEGRATION_COUNT"
    
    echo "$INTEGRATIONS" | jq -r '.[]' | while read -r integration; do
        PRODUCT_NAME=$(basename "$integration")
        echo "   - $PRODUCT_NAME"
    done
else
    echo "ℹ️ No hay integraciones de terceros habilitadas"
fi

# Verificar si GuardDuty está integrado
GUARDDUTY_INTEGRATED=$(aws securityhub describe-products \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query "Products[?contains(ProductArn, 'guardduty')].ProductArn" \
    --output text 2>/dev/null)

if [ -n "$GUARDDUTY_INTEGRATED" ]; then
    echo "✅ GuardDuty integrado automáticamente"
else
    echo "ℹ️ GuardDuty no detectado (se integrará automáticamente si está habilitado)"
fi

echo ""
echo "=============================================================="
echo "✅ AWS SECURITY HUB CONFIGURADO EXITOSAMENTE"
echo "=============================================================="
echo ""
echo "📊 Resumen de configuración:"
echo "  - Región: $REGION"
echo "  - Account ID: $ACCOUNT_ID"
echo "  - Estándares habilitados: $((STANDARDS_ENABLED + STANDARDS_ALREADY_ENABLED))"
echo "  - Nuevos estándares: $STANDARDS_ENABLED"
echo "  - Ya habilitados: $STANDARDS_ALREADY_ENABLED"

if [ $TOTAL_CONTROLS -gt 0 ]; then
    echo "  - Total controles: $TOTAL_CONTROLS"
    echo "  - Controles habilitados: $ENABLED_CONTROLS"
    echo "  - Controles deshabilitados: $DISABLED_CONTROLS"
    
    COMPLIANCE_PERCENT=$((ENABLED_CONTROLS * 100 / TOTAL_CONTROLS))
    echo "  - Porcentaje cumplimiento: $COMPLIANCE_PERCENT%"
fi

echo ""
echo "🔍 Verificación manual:"
echo "  aws securityhub describe-hub --profile $PROFILE --region $REGION"
echo "  aws securityhub get-enabled-standards --profile $PROFILE --region $REGION"
echo ""
echo "🌐 Consola Security Hub:"
echo "  https://$REGION.console.aws.amazon.com/securityhub/home?region=$REGION"
echo ""
echo "💡 Próximos pasos recomendados:"
echo "  1. ./enable-securityhub-realtime-alerts.sh $PROFILE (configurar alertas)"
echo "  2. Revisar hallazgos en la consola"
echo "  3. Configurar remediation automática para controles críticos"
echo "  4. Establecer proceso de revisión semanal de hallazgos"
echo ""

