#!/bin/bash

# Auto-remediación para Elastic IPs no asociadas
# Detecta y libera automáticamente EIPs sin usar para evitar costos

set -e

PROFILE="azcenit"
REGION="us-east-1"
DRY_RUN="false"  # Cambiar a "true" para simulación sin ejecutar cambios

echo "=== Implementando Auto-Remediación para Elastic IPs No Asociadas ==="
echo "Perfil: $PROFILE | Región: $REGION"
echo "Modo: $([ "$DRY_RUN" = "true" ] && echo "🧪 SIMULACIÓN (Dry Run)" || echo "🚀 EJECUCIÓN REAL")"
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

echo ""
echo "=== Escaneando Elastic IPs no asociadas ==="

# Obtener todas las Elastic IPs
eips_json=$(aws ec2 describe-addresses --profile $PROFILE --region $REGION --output json)
total_eips=$(echo "$eips_json" | jq '.Addresses | length')

echo "📊 Total Elastic IPs encontradas: $total_eips"

if [ "$total_eips" -eq 0 ]; then
    echo "✅ No hay Elastic IPs en esta región"
    echo ""
    echo "=== Auto-Remediación EIP Completada ✅ ==="
    exit 0
fi

echo ""

# Contadores
unattached_eips=0
attached_eips=0
remediated_eips=0
failed_remediations=0

# Crear archivo temporal para logs
echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting EIP remediation scan for account $ACCOUNT_ID" > /tmp/eip-remediation-$PROFILE.log

# Procesar cada EIP
while IFS= read -r eip; do
    public_ip=$(echo "$eip" | jq -r '.PublicIp')
    allocation_id=$(echo "$eip" | jq -r '.AllocationId')
    instance_id=$(echo "$eip" | jq -r '.InstanceId // "null"')
    association_id=$(echo "$eip" | jq -r '.AssociationId // "null"')
    network_interface_id=$(echo "$eip" | jq -r '.NetworkInterfaceId // "null"')
    domain=$(echo "$eip" | jq -r '.Domain')
    
    echo "-> Analizando EIP: $public_ip ($allocation_id)"
    
    # Verificar si está asociada
    if [ "$instance_id" != "null" ] || [ "$network_interface_id" != "null" ] || [ "$association_id" != "null" ]; then
        echo "   ✔ EIP asociada"
        if [ "$instance_id" != "null" ]; then
            echo "   📋 Instancia EC2: $instance_id"
        fi
        if [ "$network_interface_id" != "null" ]; then
            echo "   📋 Network Interface: $network_interface_id"
        fi
        attached_eips=$((attached_eips + 1))
    else
        echo "   ⚠ EIP NO ASOCIADA - Candidata para auto-remediación"
        unattached_eips=$((unattached_eips + 1))
        
        # Obtener información adicional si existe
        tags=$(echo "$eip" | jq -r '.Tags // [] | map(.Key + "=" + .Value) | join(", ")')
        if [ "$tags" != "" ]; then
            echo "   🏷️  Tags: $tags"
        fi
        
        echo "   💰 Generando costos mientras no esté asociada"
        
        if [ "$DRY_RUN" = "true" ]; then
            echo "   🧪 DRY RUN: Sería liberada (aws ec2 release-address --allocation-id $allocation_id)"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - DRY RUN - Would release EIP: $public_ip, AllocationId: $allocation_id" >> /tmp/eip-remediation-$PROFILE.log
            remediated_eips=$((remediated_eips + 1))
        else
            echo "   🔄 Aplicando auto-remediación: liberando EIP..."
            
            # Liberar la EIP
            if aws ec2 release-address \
                --allocation-id "$allocation_id" \
                --profile "$PROFILE" \
                --region "$REGION" 2>/dev/null; then
                echo "   ✅ EIP liberada exitosamente: $public_ip"
                remediated_eips=$((remediated_eips + 1))
                
                # Log de la acción para auditoria
                echo "$(date '+%Y-%m-%d %H:%M:%S') - EIP Released - IP: $public_ip, AllocationId: $allocation_id, Account: $ACCOUNT_ID" >> /tmp/eip-remediation-$PROFILE.log
            else
                echo "   ❌ Error liberando EIP: $public_ip"
                failed_remediations=$((failed_remediations + 1))
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAILED - Could not release EIP: $public_ip, AllocationId: $allocation_id" >> /tmp/eip-remediation-$PROFILE.log
            fi
        fi
    fi
    echo ""
done <<< "$(echo "$eips_json" | jq -c '.Addresses[]')"

echo "=== Resumen de Auto-Remediación EIP ==="
echo "📊 Total Elastic IPs: $total_eips"
echo "✅ EIPs asociadas: $attached_eips"
echo "⚠️  EIPs no asociadas detectadas: $unattached_eips"

if [ "$DRY_RUN" = "true" ]; then
    echo "🧪 EIPs que serían liberadas: $remediated_eips"
    echo ""
    echo "💡 Para ejecutar la remediación real:"
    echo "   Cambie DRY_RUN=\"false\" en el script"
else
    echo "🔧 EIPs liberadas: $remediated_eips"
    if [ "$failed_remediations" -gt 0 ]; then
        echo "❌ EIPs que fallaron: $failed_remediations"
    fi
fi

# Calcular ahorro estimado (EIP no asociada cuesta ~$0.005/hora = ~$3.60/mes)
if [ "$unattached_eips" -gt 0 ]; then
    monthly_savings=$(awk "BEGIN {printf \"%.2f\", $unattached_eips * 3.60}")
    echo "💰 Ahorro estimado mensual: ~\$${monthly_savings} USD"
fi

if [ "$unattached_eips" -eq 0 ]; then
    echo ""
    echo "🎯 Estado: ✅ COMPLIANT - No hay EIPs sin asociar"
elif [ "$DRY_RUN" = "true" ]; then
    echo ""
    echo "🎯 Estado: ⚠️  NON-COMPLIANT - $unattached_eips EIPs sin asociar detectadas"
    echo "🧪 Ejecute sin DRY_RUN para remediar"
else
    if [ "$failed_remediations" -eq 0 ]; then
        echo ""
        echo "🎯 Estado: ✅ REMEDIADO - Todas las EIPs no asociadas fueron liberadas"
    else
        echo ""
        echo "🎯 Estado: ⚠️  PARCIALMENTE REMEDIADO - $failed_remediations EIPs no pudieron liberarse"
    fi
fi

echo ""
echo "=== Recomendaciones de Monitoreo Continuo ==="
echo "📅 Configurar CloudWatch Event para detectar nuevas EIPs"
echo "⏰ Programar ejecución periódica (diaria/semanal)"
echo "📧 Configurar alertas SNS para notificaciones"
echo "🔍 Implementar tags para excepciones (ej: 'KeepUnattached=true')"

echo ""
echo "=== Configuración de Alertas Proactivas ==="
echo "💡 CloudWatch Alarm para EIPs no asociadas:"
echo "   aws cloudwatch put-metric-alarm \\"
echo "     --alarm-name \"UnattachedElasticIPs\" \\"
echo "     --alarm-description \"Alert when EIPs are unattached\" \\"
echo "     --metric-name \"ElasticIPCount\" \\"
echo "     --namespace \"Custom/EIP\" \\"
echo "     --statistic Sum \\"
echo "     --period 300 \\"
echo "     --threshold 1 \\"
echo "     --comparison-operator GreaterThanOrEqualToThreshold"

echo ""
echo "📋 Log de auditoría: /tmp/eip-remediation-$PROFILE.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - EIP remediation scan completed" >> /tmp/eip-remediation-$PROFILE.log

echo ""
echo "=== Auto-Remediación EIP Completada ✅ ==="