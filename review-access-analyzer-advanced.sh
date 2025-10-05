#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
REGION="us-east-1"
PROFILE="azcenit"

echo "=== ANÁLISIS AVANZADO DE IAM ACCESS ANALYZER FINDINGS ==="
echo "Proveedor: $PROVIDER"
echo "Región: $REGION"  
echo "Perfil: $PROFILE"
echo "Fecha: $(date)"
echo

# Obtener analyzer existente automáticamente
echo "🔍 Detectando analyzer de Access Analyzer..."
ANALYZER_ARN=$(wsl aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "analyzers[0].arn" \
    --output text 2>/dev/null || echo "None")

if [ "$ANALYZER_ARN" = "None" ] || [ -z "$ANALYZER_ARN" ]; then
    echo "❌ Error: No se encontró ningún analyzer de Access Analyzer."
    echo "   Ejecuta primero: ./enable-iam-access-analyzer-improved.sh"
    exit 1
fi

ANALYZER_NAME=$(wsl aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "analyzers[0].name" \
    --output text 2>/dev/null)

echo "✔ Analyzer: $ANALYZER_NAME"
echo "✔ ARN: $ANALYZER_ARN"

# Función para contar findings por filtro
count_findings() {
    local filter="$1"
    wsl aws accessanalyzer list-findings \
        --analyzer-arn "$ANALYZER_ARN" \
        --filter "$filter" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'length(findings)' \
        --output text 2>/dev/null || echo "0"
}

# Función para listar findings con detalles
list_findings_detailed() {
    local filter="$1"
    local title="$2"
    local count=$(count_findings "$filter")
    
    if [ "$count" -gt 0 ]; then
        echo
        echo "=== $title ($count findings) ==="
        wsl aws accessanalyzer list-findings \
            --analyzer-arn "$ANALYZER_ARN" \
            --filter "$filter" \
            --region "$REGION" \
            --profile "$PROFILE" \
            --query 'findings[].[id,resourceType,condition,status,createdAt]' \
            --output table 2>/dev/null || echo "Error obteniendo detalles"
    fi
}

echo
echo "📊 RESUMEN EJECUTIVO DE FINDINGS"
echo "================================="

# Estadísticas generales
total_findings=$(count_findings '{}')
active_findings=$(count_findings '{"status":{"eq":["ACTIVE"]}}')
archived_findings=$(count_findings '{"status":{"eq":["ARCHIVED"]}}')

echo "📈 Total de findings: $total_findings"
echo "🚨 Findings ACTIVOS: $active_findings"
echo "📁 Findings ARCHIVADOS: $archived_findings"

# Si no hay findings, mostrar mensaje y salir
if [ "$total_findings" -eq 0 ]; then
    echo
    echo "✅ ¡CONFIGURACIÓN PERFECTA!"
    echo
    echo "   🎯 Estado de Seguridad: ÓPTIMO"
    echo "   🔒 No hay accesos externos detectados"
    echo "   ✨ Todas las políticas están correctamente configuradas"
    echo
    echo "   💡 Recomendaciones:"
    echo "   • Continúa monitoreando regularmente"
    echo "   • Mantén las mejores prácticas actuales"
    echo "   • Revisa este análisis mensualmente"
    echo
    exit 0
fi

echo
echo "🔍 ANÁLISIS DETALLADO POR ESTADO"
echo "================================"

# Findings activos (críticos)
if [ "$active_findings" -gt 0 ]; then
    echo
    echo "🚨 FINDINGS ACTIVOS - REQUIEREN ATENCIÓN INMEDIATA"
    list_findings_detailed '{"status":{"eq":["ACTIVE"]}}' "FINDINGS ACTIVOS"
    
    echo
    echo "🚨 PLAN DE ACCIÓN INMEDIATA:"
    echo "1. 🔍 Investiga cada finding activo individualmente"
    echo "2. 🤔 Determina si el acceso es legítimo o no deseado"
    echo "3. ⚡ Si NO es legítimo: REVOCA permisos INMEDIATAMENTE"
    echo "4. 📝 Si ES legítimo: Documenta justificación y archiva"
    echo "5. 🔐 Implementa controles preventivos adicionales"
fi

# Findings archivados (informativos)
if [ "$archived_findings" -gt 0 ]; then
    list_findings_detailed '{"status":{"eq":["ARCHIVED"]}}' "FINDINGS ARCHIVADOS (Revisados)"
fi

echo
echo "📋 ANÁLISIS POR TIPO DE RECURSO"
echo "==============================="

# Array de tipos de recursos
declare -a resource_types=(
    "AWS::S3::Bucket:S3 Buckets"
    "AWS::IAM::Role:IAM Roles"  
    "AWS::KMS::Key:KMS Keys"
    "AWS::Lambda::Function:Lambda Functions"
    "AWS::SQS::Queue:SQS Queues"
    "AWS::SecretsManager::Secret:Secrets Manager"
    "AWS::EFS::FileSystem:EFS File Systems"
    "AWS::ECR::Repository:ECR Repositories"
    "AWS::RDS::DBSnapshot:RDS Snapshots"
    "AWS::SNS::Topic:SNS Topics"
)

for item in "${resource_types[@]}"; do
    resource_type="${item%%:*}"
    display_name="${item##*:}"
    
    total=$(count_findings "{\"resourceType\":{\"eq\":[\"$resource_type\"]}}")
    active=$(count_findings "{\"resourceType\":{\"eq\":[\"$resource_type\"]},\"status\":{\"eq\":[\"ACTIVE\"]}}")
    
    if [ "$total" -gt 0 ]; then
        echo "🔹 $display_name: $total total ($active activos)"
        
        if [ "$active" -gt 0 ]; then
            echo "   ⚠️  ATENCIÓN: $active findings activos requieren revisión"
        fi
    fi
done

echo
echo "🎯 ANÁLISIS DE RIESGO"
echo "===================="

if [ "$active_findings" -gt 0 ]; then
    echo "🔴 NIVEL DE RIESGO: ALTO"
    echo "   • $active_findings recursos con acceso externo activo"
    echo "   • Requiere acción inmediata"
    echo "   • Revisar y corregir en las próximas 24 horas"
elif [ "$archived_findings" -gt 0 ]; then
    echo "🟡 NIVEL DE RIESGO: BAJO"
    echo "   • Solo findings archivados (ya revisados)"
    echo "   • Monitoreo continuo recomendado"
else
    echo "🟢 NIVEL DE RIESGO: MÍNIMO"
    echo "   • Sin accesos externos detectados"
    echo "   • Configuración de seguridad óptima"
fi

echo
echo "📈 MÉTRICAS DE CUMPLIMIENTO"
echo "=========================="

compliance_score=100
if [ "$active_findings" -gt 0 ]; then
    compliance_score=$((100 - (active_findings * 10)))
    if [ $compliance_score -lt 0 ]; then
        compliance_score=0
    fi
fi

echo "🎯 Puntuación de Cumplimiento: $compliance_score/100"

if [ $compliance_score -eq 100 ]; then
    echo "   ✅ EXCELENTE - Cumplimiento perfecto"
elif [ $compliance_score -ge 80 ]; then
    echo "   🟡 BUENO - Algunos elementos por revisar"
elif [ $compliance_score -ge 60 ]; then
    echo "   🟠 REGULAR - Requiere atención"
else
    echo "   🔴 CRÍTICO - Acción inmediata requerida"
fi

echo
echo "💡 RECOMENDACIONES ESPECÍFICAS"
echo "============================="

if [ "$active_findings" -gt 0 ]; then
    echo "🚨 INMEDIATAS (24-48 horas):"
    echo "   • Revisar todos los findings activos"
    echo "   • Validar legitimidad de accesos externos"
    echo "   • Revocar permisos no autorizados"
    echo "   • Documentar excepciones aprobadas"
fi

echo "🔄 OPERACIONALES (semanales):"
echo "   • Ejecutar este análisis semanalmente"
echo "   • Monitorear nuevos findings"
echo "   • Revisar findings archivados mensualmente"

echo "🛡️  PREVENTIVAS (continuas):"
echo "   • Implementar least privilege"
echo "   • Usar roles temporales cuando sea posible"
echo "   • Configurar alertas automáticas"
echo "   • Entrenar al equipo en mejores prácticas"

echo
echo "🔧 COMANDOS ÚTILES PARA INVESTIGACIÓN"
echo "====================================="

if [ "$active_findings" -gt 0 ]; then
    echo "# Listar IDs de findings activos:"
    echo "wsl aws accessanalyzer list-findings \\"
    echo "    --analyzer-arn '$ANALYZER_ARN' \\"
    echo "    --filter '{\"status\":{\"eq\":[\"ACTIVE\"]}}' \\"
    echo "    --query 'findings[].id' \\"
    echo "    --region $REGION --profile $PROFILE"
    echo
    echo "# Ver detalles completos de un finding:"
    echo "wsl aws accessanalyzer get-finding \\"
    echo "    --analyzer-arn '$ANALYZER_ARN' \\"
    echo "    --id '<FINDING-ID>' \\"
    echo "    --region $REGION --profile $PROFILE"
    echo
    echo "# Archivar un finding después de revisión:"
    echo "wsl aws accessanalyzer update-findings \\"
    echo "    --analyzer-arn '$ANALYZER_ARN' \\"
    echo "    --ids '<FINDING-ID>' \\"
    echo "    --status ARCHIVED \\"
    echo "    --region $REGION --profile $PROFILE"
fi

echo
echo "📊 PRÓXIMA REVISIÓN PROGRAMADA"
echo "=============================="
next_review=$(date -d "+1 week" "+%Y-%m-%d %H:%M")
echo "📅 Fecha sugerida: $next_review"
echo "🔔 Configura un recordatorio para ejecutar este análisis"

echo
echo "⏰ Análisis completado: $(date)"
echo "🎯 Estado: REVISIÓN COMPLETA"
echo "=============================================="