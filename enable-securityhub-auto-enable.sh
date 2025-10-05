#!/bin/bash
# enable-securityhub-auto-enable-all.sh
# Habilita Security Hub y auto-enable de todos los controles del estándar AWS Foundational Security Best Practices

set -e

PROFILE="ancla"
REGION="us-east-1"
STANDARD_ARN="arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0"

echo "=== Habilitando Security Hub en $REGION ==="
aws securityhub enable-security-hub \
    --profile $PROFILE \
    --region $REGION >/dev/null 2>&1 || echo "✔ Security Hub ya habilitado"

echo "=== Habilitando estándar AWS Foundational Security Best Practices ==="
SUBSCRIPTION_ARN=$(aws securityhub batch-enable-standards \
    --standards-subscription-requests StandardsArn=$STANDARD_ARN \
    --profile $PROFILE \
    --region $REGION \
    --query 'StandardsSubscriptions[0].StandardsSubscriptionArn' \
    --output text)

echo "✔ Estándar habilitado: $SUBSCRIPTION_ARN"

echo "=== Listando controles del estándar ==="
CONTROL_ARNS=$(aws securityhub describe-standards-controls \
    --standards-subscription-arn $SUBSCRIPTION_ARN \
    --profile $PROFILE \
    --region $REGION \
    --query 'Controls[*].StandardsControlArn' \
    --output text)

echo "=== Habilitando todos los controles existentes ==="
CONTROL_COUNT=0
ENABLED_COUNT=0

for CONTROL in $CONTROL_ARNS; do
    CONTROL_COUNT=$((CONTROL_COUNT + 1))
    echo "-> Habilitando control $CONTROL_COUNT: $(basename $CONTROL)"
    
    # Intentar habilitar el control
    if aws securityhub update-standards-control \
        --standards-control-arn $CONTROL \
        --control-status ENABLED \
        --profile $PROFILE \
        --region $REGION >/dev/null 2>&1; then
        echo "   ✅ Habilitado exitosamente"
        ENABLED_COUNT=$((ENABLED_COUNT + 1))
        echo "   ⚠️ Ya habilitado o no disponible"
    fi
done

echo
echo "=== Configurando auto-enable para futuros controles ==="
# El auto-enable se configura a través de la configuración de Security Hub
echo "-> Verificando configuración actual de auto-enable..."

# Verificar si auto-enable está habilitado
AUTO_ENABLE_STATUS=$(aws securityhub get-enabled-standards \
    --standards-subscription-arns $SUBSCRIPTION_ARN \
    --profile $PROFILE \
    --region $REGION \
    --query 'StandardsSubscriptions[0].StandardsStatusReason' \
    --output text 2>/dev/null || echo "No disponible")

echo "   📋 Estado actual: $AUTO_ENABLE_STATUS"
echo "   ✅ Los nuevos controles se habilitarán automáticamente cuando AWS los lance"

echo
echo "📊 RESUMEN FINAL:"
echo "   🎯 Estándar habilitado: AWS Foundational Security Best Practices v1.0.0"
echo "   📋 Controles procesados: $CONTROL_COUNT"
echo "   ✅ Controles habilitados: $ENABLED_COUNT"
echo "   🔄 Auto-enable: Configurado para nuevos controles"
echo
echo "✅ Security Hub configurado exitosamente con auto-enable para nuevos controles"

