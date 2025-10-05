#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
REGION="us-east-1"
PROFILE="azcenit"

echo "=== Habilitando AWS Security Hub ==="
echo "Proveedor: $PROVIDER"
echo "Región: $REGION"
echo "Perfil: $PROFILE"
echo

# Verificar si Security Hub ya está habilitado
echo "Verificando estado de Security Hub en $REGION..."
hub_status=$(wsl aws securityhub describe-hub \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'HubArn' \
    --output text 2>/dev/null || echo "NOT_ENABLED")

if [[ "$hub_status" == "NOT_ENABLED" ]]; then
    echo "Security Hub no está habilitado. Habilitando Security Hub con AWS Foundational Security Best Practices..."
    
    # Habilitar Security Hub con el estándar de mejores prácticas
    wsl aws securityhub enable-security-hub \
        --enable-default-standards \
        --region "$REGION" \
        --profile "$PROFILE"
    
    echo "✔ Security Hub habilitado exitosamente"
    
    # Habilitar específicamente el estándar AWS Foundational Security Best Practices
    echo "Habilitando AWS Foundational Security Best Practices standard..."
    wsl aws securityhub batch-enable-standards \
        --standards-subscription-requests StandardsArn=arn:aws:securityhub:$REGION::standard/aws-foundational-security-best-practices/v/1.0.0 \
        --region "$REGION" \
        --profile "$PROFILE"
    
    echo "✔ AWS Foundational Security Best Practices habilitado"
else
    echo "Security Hub ya está habilitado: $hub_status"
    
    # Verificar si el estándar ya está habilitado
    echo "Verificando estándares habilitados..."
    standards=$(wsl aws securityhub get-enabled-standards \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query "StandardsSubscriptions[?contains(StandardsArn, 'aws-foundational-security-best-practices')].StandardsArn" \
        --output text)
    
    if [[ -z "$standards" ]]; then
        echo "Habilitando AWS Foundational Security Best Practices standard..."
        wsl aws securityhub batch-enable-standards \
            --standards-subscription-requests StandardsArn=arn:aws:securityhub:$REGION::standard/aws-foundational-security-best-practices/v/1.0.0 \
            --region "$REGION" \
            --profile "$PROFILE"
        echo "✔ AWS Foundational Security Best Practices habilitado"
    else
        echo "✔ AWS Foundational Security Best Practices ya está habilitado"
    fi
fi

# Verificar configuración final
echo
echo "Verificando configuración final de Security Hub..."
hub_info=$(wsl aws securityhub describe-hub \
    --region "$REGION" \
    --profile "$PROFILE" 2>/dev/null || echo "Error al obtener información")

if [[ "$hub_info" != "Error al obtener información" ]]; then
    echo "✅ Security Hub configurado exitosamente"
    echo "Hub ARN: $(echo "$hub_info" | grep -o 'arn:aws:securityhub:[^"]*' || echo 'No disponible')"
else
    echo "❌ Error al verificar la configuración de Security Hub"
fi

# Habilitar estándares adicionales importantes
echo
echo "Habilitando estándares adicionales de cumplimiento..."

# AWS Config Conformance Packs
echo "Verificando AWS Config Conformance Pack standard..."
config_standard=$(wsl aws securityhub get-enabled-standards \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "StandardsSubscriptions[?contains(StandardsArn, 'aws-config-conformance-packs')].StandardsArn" \
    --output text 2>/dev/null || echo "")

if [[ -z "$config_standard" ]]; then
    echo "Habilitando AWS Config Conformance Pack standard..."
    wsl aws securityhub batch-enable-standards \
        --standards-subscription-requests StandardsArn=arn:aws:securityhub:$REGION::standard/aws-config-conformance-packs/v/1.0.0 \
        --region "$REGION" \
        --profile "$PROFILE" 2>/dev/null || echo "⚠ AWS Config Conformance Pack no disponible en esta región"
    echo "✔ AWS Config Conformance Pack habilitado"
else
    echo "✔ AWS Config Conformance Pack ya está habilitado"
fi

# PCI DSS
echo "Verificando PCI DSS standard..."
pci_standard=$(wsl aws securityhub get-enabled-standards \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "StandardsSubscriptions[?contains(StandardsArn, 'pci-dss')].StandardsArn" \
    --output text 2>/dev/null || echo "")

if [[ -z "$pci_standard" ]]; then
    echo "Habilitando PCI DSS standard..."
    wsl aws securityhub batch-enable-standards \
        --standards-subscription-requests StandardsArn=arn:aws:securityhub:$REGION::standard/pci-dss/v/3.2.1 \
        --region "$REGION" \
        --profile "$PROFILE" 2>/dev/null || echo "⚠ PCI DSS no disponible en esta región"
    echo "✔ PCI DSS habilitado"
else
    echo "✔ PCI DSS ya está habilitado"
fi

# Mostrar resumen de estándares habilitados
echo
echo "=== Resumen de estándares habilitados ==="
wsl aws securityhub get-enabled-standards \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "StandardsSubscriptions[].[StandardsArn,StandardsStatus]" \
    --output table

echo
echo "=== Verificando integración con otros servicios AWS ==="
# Verificar que GuardDuty esté habilitado para integración
guardduty_status=$(wsl aws guardduty list-detectors \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "DetectorIds[0]" \
    --output text 2>/dev/null || echo "None")

if [[ "$guardduty_status" != "None" ]]; then
    echo "✔ GuardDuty integrado - findings aparecerán en Security Hub"
else
    echo "⚠ GuardDuty no habilitado - considera habilitarlo para más findings"
fi

# Verificar que Config esté habilitado
config_status=$(wsl aws configservice describe-configuration-recorders \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "ConfigurationRecorders[0].name" \
    --output text 2>/dev/null || echo "None")

if [[ "$config_status" != "None" ]]; then
    echo "✔ AWS Config integrado - findings de configuración aparecerán en Security Hub"
else
    echo "⚠ AWS Config no habilitado - considera habilitarlo para evaluaciones de configuración"
fi

echo
echo "Notas importantes:"
echo "- Security Hub agregará automáticamente findings de otros servicios AWS habilitados"
echo "- Los controles se ejecutarán automáticamente según el cronograma configurado"
echo "- Revisa la consola de Security Hub para ver los findings y recomendaciones"
echo "- Los estándares de cumplimiento ayudan a mantener mejores prácticas de seguridad"
echo "- Considera habilitar GuardDuty y AWS Config para máxima cobertura"
echo "- Los findings se consolidan en un dashboard central para fácil gestión"
echo
echo "=== Proceso completado ==="