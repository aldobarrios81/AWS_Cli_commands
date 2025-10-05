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
ANALYZER_ARN=$(wsl aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --output json | grep -A3 -B3 "$ANALYZER_NAME" | grep '"arn":' | cut -d'"' -f4)

if [ -z "$ANALYZER_ARN" ]; then
    echo "❌ Error: No se encontró el analyzer '$ANALYZER_NAME'. Ejecuta primero el script para habilitar Access Analyzer."
    exit 1
fi

echo "✔ Analyzer encontrado: $ANALYZER_ARN"
echo

# Obtener estadísticas generales
echo "Obteniendo estadísticas de findings..."
ALL_FINDINGS=$(wsl aws accessanalyzer list-findings \
    --analyzer-arn "$ANALYZER_ARN" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "findings" \
    --output json 2>/dev/null || echo "[]")

TOTAL_FINDINGS=$(echo "$ALL_FINDINGS" | grep -o '"id":' | wc -l)
ACTIVE_FINDINGS_COUNT=$(echo "$ALL_FINDINGS" | grep -A5 -B5 '"status": "ACTIVE"' | grep -o '"id":' | wc -l)
ARCHIVED_FINDINGS_COUNT=$(echo "$ALL_FINDINGS" | grep -A5 -B5 '"status": "ARCHIVED"' | grep -o '"id":' | wc -l)

echo "Estadísticas de Findings:"
echo "- Total de findings: $TOTAL_FINDINGS"
echo "- Findings activos: $ACTIVE_FINDINGS_COUNT"
echo "- Findings archivados: $ARCHIVED_FINDINGS_COUNT"
echo

if [ "$ACTIVE_FINDINGS_COUNT" -eq 0 ]; then
    echo "✅ No hay hallazgos activos en $REGION."
    echo "   Esto significa que no se detectaron recursos compartidos externamente."
else
    echo "⚠️  Hallazgos activos encontrados:"
    echo
    
    # Mostrar findings activos con detalles
    wsl aws accessanalyzer list-findings \
        --analyzer-arn "$ANALYZER_ARN" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --filter '{"status":{"eq":["ACTIVE"]}}' \
        --query 'findings[*].{Id:id,ResourceType:resourceType,Resource:resource,Status:status,CreatedAt:createdAt}' \
        --output table
    
    echo
    echo "Detalles de cada finding activo:"
    echo "================================"
    
    # Obtener IDs de findings activos
    ACTIVE_FINDING_IDS=$(wsl aws accessanalyzer list-findings \
        --analyzer-arn "$ANALYZER_ARN" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --filter '{"status":{"eq":["ACTIVE"]}}' \
        --query "findings[].id" \
        --output text)
    
    # Mostrar detalles de cada finding
    for FINDING_ID in $ACTIVE_FINDING_IDS; do
        echo
        echo "Finding ID: $FINDING_ID"
        echo "------------------------"
        wsl aws accessanalyzer get-finding \
            --analyzer-arn "$ANALYZER_ARN" \
            --id "$FINDING_ID" \
            --region "$REGION" \
            --profile "$PROFILE" \
            --query 'finding.{ResourceType:resourceType,Resource:resource,Principal:principal,Action:action,Condition:condition}' \
            --output json | sed 's/^/  /'
    done
    
    echo
    echo "⚠️  IMPORTANTE: Revisa cada finding para determinar si el acceso externo es intencional."
    echo "   Si algún finding representa un acceso no deseado, toma medidas correctivas inmediatas."
    echo
    
    # Preguntar si se desean archivar (solo si hay findings activos)
    read -p "¿Deseas archivar todos los hallazgos activos después de revisarlos? (y/N): " ARCHIVE
    
    if [[ "$ARCHIVE" =~ ^[Yy]$ ]]; then
        echo "Archivando findings activos..."
        for FINDING_ID in $ACTIVE_FINDING_IDS; do
            wsl aws accessanalyzer update-findings \
                --analyzer-arn "$ANALYZER_ARN" \
                --region "$REGION" \
                --profile "$PROFILE" \
                --status ARCHIVED \
                --ids "$FINDING_ID"
            echo "✔ Finding $FINDING_ID archivado"
        done
        echo "✅ Todos los hallazgos activos han sido archivados."
    else
        echo "✋ No se archivaron hallazgos. Recuerda revisarlos regularmente."
    fi
fi

echo
echo "=== Revisión completada ==="
echo "Para futuras revisiones, ejecuta este script regularmente para mantener"
echo "la seguridad de tu cuenta AWS."

