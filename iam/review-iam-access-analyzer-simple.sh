#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
REGION="us-east-1"
PROFILE="azcenit"

echo "=== Revisando IAM Access Analyzer Findings ==="
echo "Proveedor: $PROVIDER"
echo "Región: $REGION"
echo "Perfil: $PROFILE"
echo

# Obtener analyzer existente automáticamente
echo "Detectando analyzer de Access Analyzer..."
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

analyzer_status=$(wsl aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "analyzers[0].status" \
    --output text 2>/dev/null)

echo "✔ Analyzer detectado: $ANALYZER_NAME"
echo "✔ Analyzer ARN: $ANALYZER_ARN"
echo "✔ Analyzer Status: $analyzer_status"
echo

# Obtener todos los findings
echo
echo "Obteniendo findings..."
findings_count=$(wsl aws accessanalyzer list-findings \
    --analyzer-arn "$ANALYZER_ARN" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'length(findings)' \
    --output text 2>/dev/null || echo "0")

echo "Total de findings encontrados: $findings_count"

if [ "$findings_count" -eq 0 ]; then
    echo
    echo "✅ ¡Excelente! No se encontraron findings activos."
    echo
    echo "   Esto significa que:"
    echo "   • No hay recursos compartidos externamente de manera no deseada"
    echo "   • Las políticas IAM están configuradas correctamente"
    echo "   • No se detectaron accesos externos no autorizados"
    echo "   • Tu configuración de seguridad es óptima"
    echo
else
    echo
    echo "📋 Se encontraron $findings_count findings. Analizando en detalle..."
    echo
    
    # Obtener findings activos
    echo "=== FINDINGS ACTIVOS ==="
    active_findings=$(wsl aws accessanalyzer list-findings \
        --analyzer-arn "$ANALYZER_ARN" \
        --filter '{"status":{"eq":["ACTIVE"]}}' \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'length(findings)' \
        --output text 2>/dev/null || echo "0")
    
    echo "Findings activos: $active_findings"
    
    if [ "$active_findings" -gt 0 ]; then
        echo
        echo "Detalles de findings activos:"
        echo "=============================="
        
        # Mostrar resumen de findings activos por tipo
        wsl aws accessanalyzer list-findings \
            --analyzer-arn "$ANALYZER_ARN" \
            --filter '{"status":{"eq":["ACTIVE"]}}' \
            --region "$REGION" \
            --profile "$PROFILE" \
            --query 'findings[].[id,resourceType,condition,status]' \
            --output table 2>/dev/null || echo "Error obteniendo detalles"
        
        echo
        echo "� ACCIÓN REQUERIDA para findings activos:"
        echo "1. Revisa cada finding individualmente"
        echo "2. Determina si el acceso externo es intencional"
        echo "3. Si NO es intencional: REVOCA los permisos inmediatamente"
        echo "4. Si ES intencional: Documenta la justificación y archiva el finding"
        echo "5. Implementa controles adicionales si es necesario"
    fi
    
    # Obtener findings archivados
    echo
    echo "=== FINDINGS ARCHIVADOS ==="
    archived_findings=$(wsl aws accessanalyzer list-findings \
        --analyzer-arn "$ANALYZER_ARN" \
        --filter '{"status":{"eq":["ARCHIVED"]}}' \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'length(findings)' \
        --output text 2>/dev/null || echo "0")
    
    echo "Findings archivados: $archived_findings"
    
    # Mostrar breakdown por tipo de recurso
    echo
    echo "=== BREAKDOWN POR TIPO DE RECURSO ==="
    echo "S3 Buckets:"
    s3_findings=$(wsl aws accessanalyzer list-findings \
        --analyzer-arn "$ANALYZER_ARN" \
        --filter '{"resourceType":{"eq":["AWS::S3::Bucket"]}}' \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'length(findings)' \
        --output text 2>/dev/null || echo "0")
    echo "  Total: $s3_findings findings"
    
    echo "IAM Roles:"
    iam_findings=$(wsl aws accessanalyzer list-findings \
        --analyzer-arn "$ANALYZER_ARN" \
        --filter '{"resourceType":{"eq":["AWS::IAM::Role"]}}' \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'length(findings)' \
        --output text 2>/dev/null || echo "0")
    echo "  Total: $iam_findings findings"
    
    echo "KMS Keys:"
    kms_findings=$(wsl aws accessanalyzer list-findings \
        --analyzer-arn "$ANALYZER_ARN" \
        --filter '{"resourceType":{"eq":["AWS::KMS::Key"]}}' \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'length(findings)' \
        --output text 2>/dev/null || echo "0")
    echo "  Total: $kms_findings findings"
    
    echo "Lambda Functions:"
    lambda_findings=$(wsl aws accessanalyzer list-findings \
        --analyzer-arn "$ANALYZER_ARN" \
        --filter '{"resourceType":{"eq":["AWS::Lambda::Function"]}}' \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'length(findings)' \
        --output text 2>/dev/null || echo "0")
    echo "  Total: $lambda_findings findings"
fi

echo
echo "📝 Comandos útiles para gestión de findings:"
echo "============================================="
echo
echo "# Ver detalles de un finding específico:"
echo "wsl aws accessanalyzer get-finding --analyzer-arn $ANALYZER_ARN --id <FINDING-ID> --region $REGION --profile $PROFILE"
echo
echo "# Archivar un finding (después de revisar):"
echo "wsl aws accessanalyzer update-findings --analyzer-arn $ANALYZER_ARN --ids <FINDING-ID> --status ARCHIVED --region $REGION --profile $PROFILE"
echo
echo "# Listar solo findings activos:"
echo "wsl aws accessanalyzer list-findings --analyzer-arn $ANALYZER_ARN --filter '{\"status\":{\"eq\":[\"ACTIVE\"]}}' --region $REGION --profile $PROFILE"
echo

echo "⏰ Revisión completada: $(date)"
echo
echo "💡 Recomendación: Ejecuta este script regularmente para mantener la seguridad"
echo "=== Proceso completado ==="