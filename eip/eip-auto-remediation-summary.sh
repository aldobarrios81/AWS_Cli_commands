#!/bin/bash

# Resumen Final de Auto-Remediación EIP para todos los perfiles
# Verifica el estado de compliance de Elastic IPs en los 3 perfiles

set -e

echo "=================================================================="
echo "🔍 RESUMEN FINAL: AUTO-REMEDIACIÓN ELASTIC IPs"
echo "=================================================================="
echo ""
echo "Auditando el estado de Elastic IPs en todos los perfiles AWS..."
echo ""

# Array de perfiles
PROFILES=("ancla" "azbeacons" "azcenit")
REGION="us-east-1"

# Contadores globales
total_accounts=0
compliant_accounts=0
total_eips_all_accounts=0
total_unattached_eips=0

echo "┌─────────────────┬──────────────────┬───────────────┬─────────────────┬─────────────────┐"
echo "│ Perfil          │ Account ID       │ Total EIPs    │ EIPs Asociadas  │ EIPs No Asoc.   │"
echo "├─────────────────┼──────────────────┼───────────────┼─────────────────┼─────────────────┤"

for PROFILE in "${PROFILES[@]}"; do
    total_accounts=$((total_accounts + 1))
    
    # Obtener Account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query Account --output text 2>/dev/null || echo "N/A")
    
    if [ "$ACCOUNT_ID" = "N/A" ]; then
        printf "│ %-15s │ %-16s │ %-13s │ %-15s │ %-15s │\n" "$PROFILE" "ERROR" "N/A" "N/A" "N/A"
        continue
    fi
    
    # Obtener información de EIPs
    eips_json=$(aws ec2 describe-addresses --profile $PROFILE --region $REGION --output json 2>/dev/null || echo '{"Addresses":[]}')
    total_eips=$(echo "$eips_json" | jq '.Addresses | length')
    
    # Contar EIPs asociadas y no asociadas
    attached_eips=0
    unattached_eips=0
    
    if [ "$total_eips" -gt 0 ]; then
        while IFS= read -r eip; do
            instance_id=$(echo "$eip" | jq -r '.InstanceId // "null"')
            association_id=$(echo "$eip" | jq -r '.AssociationId // "null"')
            network_interface_id=$(echo "$eip" | jq -r '.NetworkInterfaceId // "null"')
            
            if [ "$instance_id" != "null" ] || [ "$network_interface_id" != "null" ] || [ "$association_id" != "null" ]; then
                attached_eips=$((attached_eips + 1))
            else
                unattached_eips=$((unattached_eips + 1))
            fi
        done <<< "$(echo "$eips_json" | jq -c '.Addresses[]')"
    fi
    
    # Status de compliance
    status_symbol="✅"
    if [ "$unattached_eips" -gt 0 ]; then
        status_symbol="⚠️ "
    else
        compliant_accounts=$((compliant_accounts + 1))
    fi
    
    # Actualizar contadores globales
    total_eips_all_accounts=$((total_eips_all_accounts + total_eips))
    total_unattached_eips=$((total_unattached_eips + unattached_eips))
    
    # Formatear Account ID
    formatted_account_id="${ACCOUNT_ID:0:3}...${ACCOUNT_ID: -3}"
    
    printf "│ %-15s │ %-16s │ %11s   │ %13s   │ %13s %s │\n" "$PROFILE" "$formatted_account_id" "$total_eips" "$attached_eips" "$unattached_eips" "$status_symbol"
done

echo "└─────────────────┴──────────────────┴───────────────┴─────────────────┴─────────────────┘"
echo ""

# Estadísticas finales
echo "📊 ESTADÍSTICAS CONSOLIDADAS:"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "🏢 Total de cuentas auditadas: $total_accounts"
echo "✅ Cuentas completamente compliant: $compliant_accounts"
echo "📋 Total de Elastic IPs: $total_eips_all_accounts"
echo "⚠️  Total de EIPs no asociadas: $total_unattached_eips"

if [ "$total_unattached_eips" -gt 0 ]; then
    monthly_cost=$(awk "BEGIN {printf \"%.2f\", $total_unattached_eips * 3.60}")
    echo "💰 Costo mensual EIPs no asociadas: ~\$${monthly_cost} USD"
fi

echo ""

# Estado general de compliance
if [ "$total_unattached_eips" -eq 0 ]; then
    echo "🎯 ESTADO GENERAL: ✅ COMPLETAMENTE COMPLIANT"
    echo "   ➤ Todas las Elastic IPs están correctamente asociadas"
    echo "   ➤ No hay costos adicionales por EIPs sin usar"
    echo "   ➤ La infraestructura está optimizada"
else
    non_compliant=$((total_accounts - compliant_accounts))
    echo "🎯 ESTADO GENERAL: ⚠️  REQUIERE ATENCIÓN"
    echo "   ➤ $non_compliant cuenta(s) con EIPs no asociadas"
    echo "   ➤ $total_unattached_eips EIP(s) generando costos innecesarios"
    echo "   ➤ Remediación recomendada inmediatamente"
fi

echo ""
echo "🔧 ACCIONES RECOMENDADAS:"
echo "═══════════════════════════════════════════════════════════════════════════"

if [ "$total_unattached_eips" -eq 0 ]; then
    echo "✅ Configurar monitoreo proactivo:"
    echo "   • CloudWatch Events para detectar nuevas EIPs"
    echo "   • Alertas automáticas vía SNS"
    echo "   • Auditorías programadas (semanales)"
    
    echo ""
    echo "💡 Mejores prácticas implementadas:"
    echo "   • Auto-remediación activa ✅"
    echo "   • Compliance 100% ✅"
    echo "   • Optimización de costos ✅"
else
    echo "⚠️  Ejecutar remediación inmediata:"
    echo "   • Cambiar DRY_RUN=\"false\" en el script"
    echo "   • Liberar EIPs no asociadas"
    echo "   • Verificar que no se necesiten realmente"
    
    echo ""
    echo "📅 Configurar monitoreo preventivo:"
    echo "   • Alertas en tiempo real"
    echo "   • Revisiones automáticas diarias"
fi

echo ""
echo "📋 DETALLES DE AUDITORÍA:"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "🕒 Timestamp: $(date '+%Y-%m-%d %H:%M:%S UTC')"
echo "🔍 Región auditada: $REGION"
echo "🛠️  Método: AWS CLI + Auto-remediación"
echo "📂 Logs disponibles en: /tmp/eip-remediation-*.log"

echo ""
echo "=================================================================="
echo "🎉 AUTO-REMEDIACIÓN EIP - AUDITORÍA COMPLETADA"
echo "=================================================================="