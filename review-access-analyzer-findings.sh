#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
REGION="us-east-1"
PROFILE="azcenit"
ANALYZER_NAME="default-analyzer"

echo "=== Revisando IAM Access Analyzer Findings ==="
echo "Proveedor: $PROVIDER"
echo "Región: $REGION"
echo "Perfil: $PROFILE"
echo

# Obtener el ARN del analyzer
echo "Obteniendo información del analyzer..."
ANALYZER_ARN="arn:aws:access-analyzer:$REGION:$(wsl aws sts get-caller-identity --profile $PROFILE --query Account --output text):analyzer/$ANALYZER_NAME"

echo "✔ Analyzer: $ANALYZER_ARN"
echo

# Verificar que el analyzer existe
analyzer_status=$(wsl aws accessanalyzer get-analyzer \
    --analyzer-name "$ANALYZER_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'analyzer.status' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$analyzer_status" == "NOT_FOUND" ]; then
    echo "❌ Error: Analyzer '$ANALYZER_NAME' no encontrado."
    echo "   Ejecuta primero: ./enable-iam-access-analyzer.sh"
    exit 1
fi

echo "✔ Analyzer Status: $analyzer_status"
echo

# Obtener findings
echo "Obteniendo findings..."
findings_output=$(wsl aws accessanalyzer list-findings \
    --analyzer-arn "$ANALYZER_ARN" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --output json)

# Contar findings por estado
total_findings=$(echo "$findings_output" | grep -o '"id":' | wc -l)
active_findings=$(echo "$findings_output" | grep -A10 -B10 '"status": "ACTIVE"' | grep -o '"id":' | wc -l)

echo "📊 Estadísticas de Findings:"
echo "- Total de findings: $total_findings"
echo "- Findings activos: $active_findings"
echo

if [ "$active_findings" -eq 0 ]; then
    echo "✅ Excelente! No hay findings activos."
    echo "   Esto significa que:"
    echo "   • No se detectaron recursos compartidos externamente"
    echo "   • Las políticas IAM están configuradas correctamente"
    echo "   • No hay accesos no autorizados detectados"
    
    if [ "$total_findings" -gt 0 ]; then
        echo
        echo "📋 Findings archivados existentes: $((total_findings - active_findings))"
        echo "   Estos fueron revisados previamente y marcados como seguros."
    fi
else
    echo "⚠️  ATENCIÓN: Se encontraron $active_findings findings activos"
    echo
    echo "Detalles de findings activos:"
    echo "============================="
    
    # Mostrar tabla resumida de findings activos
    wsl aws accessanalyzer list-findings \
        --analyzer-arn "$ANALYZER_ARN" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --filter '{"status":{"eq":["ACTIVE"]}}' \
        --query 'findings[*].{ID:id,ResourceType:resourceType,Resource:resource,CreatedAt:createdAt}' \
        --output table
    
    echo
    echo "🔍 Para ver detalles completos de un finding específico, usa:"
    echo "wsl aws accessanalyzer get-finding --analyzer-arn $ANALYZER_ARN --id <FINDING-ID> --region $REGION --profile $PROFILE"
    
    echo
    echo "📝 Acciones recomendadas:"
    echo "1. Revisa cada finding para determinar si el acceso es intencional"
    echo "2. Si el acceso NO es intencional, revoca los permiissos inmediatamente"
    echo "3. Si el acceso ES intencional, archiva el finding"
    echo "4. Documenta la justificación para accesos externos legítimos"
    
    echo
    read -p "¿Deseas ver los detalles completos de todos los findings activos? (y/N): " SHOW_DETAILS
    
    if [[ "$SHOW_DETAILS" =~ ^[Yy]$ ]]; then
        echo
        echo "📋 Detalles completos de findings activos:"
        echo "========================================"
        
        # Obtener IDs de findings activos
        active_ids=$(echo "$findings_output" | grep -B5 -A5 '"status": "ACTIVE"' | grep '"id":' | cut -d'"' -f4)
        
        for finding_id in $active_ids; do
            echo
            echo "🔍 Finding ID: $finding_id"
            echo "-------------------------"
            wsl aws accessanalyzer get-finding \
                --analyzer-arn "$ANALYZER_ARN" \
                --id "$finding_id" \
                --region "$REGION" \
                --profile "$PROFILE" \
                --output json | jq -r '.finding | 
                "Resource Type: \(.resourceType)
Resource: \(.resource)
Principal: \(.principal // "N/A")
Action: \(.action // [] | join(", "))
Condition: \(.condition // {} | if . == {} then "None" else . end)
Created: \(.createdAt)
Updated: \(.updatedAt)"'
        done
    fi
fi

echo
echo "⏰ Última ejecución: $(date)"
echo
echo "💡 Recomendaciones:"
echo "- Ejecuta este script regularmente (semanal o mensualmente)"
echo "- Configura alertas automáticas para nuevos findings"
echo "- Mantén documentación de todos los accesos externos aprobados"
echo
echo "=== Revisión completada ===