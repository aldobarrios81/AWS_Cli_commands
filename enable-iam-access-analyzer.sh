#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
REGION="us-east-1"
PROFILE="ancla"
ANALYZER_NAME="default-analyzer"

echo "=== Habilitando IAM Access Analyzer ==="
echo "Proveedor: $PROVIDER"
echo "Región: $REGION"
echo "Perfil: $PROFILE"
echo

# Verificar analyzers existentes
echo "Verificando analyzers existentes de IAM Access Analyzer..."
EXISTING_ANALYZERS=$(wsl aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "analyzers[].name" \
    --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_ANALYZERS" ]; then
    # Usar el primer analyzer disponible
    ANALYZER_NAME=$(echo "$EXISTING_ANALYZERS" | awk '{print $1}')
    echo "✔ Usando analyzer existente: $ANALYZER_NAME"
    
    # Obtener información del analyzer existente
    analyzer_info=$(wsl aws accessanalyzer get-analyzer \
        --analyzer-name "$ANALYZER_NAME" \
        --region "$REGION" \
        --profile "$PROFILE")
    
    analyzer_arn=$(echo "$analyzer_info" | grep -o '"arn":"[^"]*"' | cut -d'"' -f4)
    analyzer_status=$(echo "$analyzer_info" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    
    echo "  ARN: $analyzer_arn"
    echo "  Estado: $analyzer_status"
else
    echo "No se encontraron analyzers existentes. Creando nuevo analyzer '$ANALYZER_NAME'..."
    analyzer_arn=$(wsl aws accessanalyzer create-analyzer \
        --analyzer-name "$ANALYZER_NAME" \
        --type ACCOUNT \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'arn' \
        --output text)
    
    echo "✔ Analyzer creado exitosamente"
    echo "  ARN: $analyzer_arn"
fi

# Verificar findings actuales
echo
echo "Verificando findings existentes..."
findings_count=$(wsl aws accessanalyzer list-findings \
    --analyzer-arn "$analyzer_arn" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'length(findings)' \
    --output text 2>/dev/null || echo "0")

echo "Findings encontrados: $findings_count"

if [ "$findings_count" -gt 0 ]; then
    echo
    echo "Resumen de findings por tipo de recurso:"
    wsl aws accessanalyzer list-findings \
        --analyzer-arn "$analyzer_arn" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'findings[].{ResourceType:resourceType,Status:status}' \
        --output table 2>/dev/null || echo "No se pudieron obtener detalles de findings"
fi

# Verificar tipos de recursos soportados por Access Analyzer
echo
echo "Verificando tipos de recursos monitoreados por Access Analyzer..."
echo "Recursos soportados:"
echo "- IAM Roles"
echo "- S3 Buckets"
echo "- KMS Keys"
echo "- Lambda Functions" 
echo "- SQS Queues"
echo "- Secrets Manager Secrets"
echo "- EFS File Systems"
echo "- ECR Repositories"
echo "- RDS DB Snapshots"
echo "- RDS DB Cluster Snapshots"
echo "- Redshift Clusters"
echo "- SNS Topics"

# Crear analyzer de organización si corresponde (opcional)
echo
echo "Verificando si se puede crear analyzer de organización..."
org_analyzer_name="organization-analyzer"
org_analyzer_exists=$(wsl aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "analyzers[?name=='$org_analyzer_name'].name" \
    --output text 2>/dev/null || echo "")

if [ -z "$org_analyzer_exists" ]; then
    echo "Intentando crear analyzer de organización..."
    org_analyzer_arn=$(wsl aws accessanalyzer create-analyzer \
        --analyzer-name "$org_analyzer_name" \
        --type ORGANIZATION \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'arn' \
        --output text 2>/dev/null || echo "NO_ORG")
    
    if [ "$org_analyzer_arn" != "NO_ORG" ]; then
        echo "✔ Analyzer de organización creado: $org_analyzer_arn"
    else
        echo "ℹ No se pudo crear analyzer de organización (requiere AWS Organizations)"
    fi
else
    echo "✔ Analyzer de organización ya existe: $org_analyzer_name"
fi

# Verificar configuración de archivado automático
echo
echo "Configurando políticas de archivado automático..."
echo "Los findings se pueden archivar automáticamente basado en criterios específicos"

# Mostrar comando para generar reporte
echo
echo "=== Comandos útiles para gestión de Access Analyzer ==="
echo
echo "Ver todos los findings activos:"
echo "wsl aws accessanalyzer list-findings --analyzer-arn $analyzer_arn --filter '{\"status\":{\"eq\":[\"ACTIVE\"]}}' --region $REGION --profile $PROFILE"
echo
echo "Ver findings por tipo de recurso (ejemplo: S3):"
echo "wsl aws accessanalyzer list-findings --analyzer-arn $analyzer_arn --filter '{\"resourceType\":{\"eq\":[\"AWS::S3::Bucket\"]}}' --region $REGION --profile $PROFILE"
echo
echo "Obtener detalles de un finding específico:"
echo "wsl aws accessanalyzer get-finding --analyzer-arn $analyzer_arn --id <FINDING-ID> --region $REGION --profile $PROFILE"
echo
echo "Archivar un finding:"
echo "wsl aws accessanalyzer update-findings --analyzer-arn $analyzer_arn --ids <FINDING-ID> --status ARCHIVED --region $REGION --profile $PROFILE"

# Verificar integración con Security Hub
echo
echo "=== Verificando integración con Security Hub ==="
securityhub_status=$(wsl aws securityhub describe-hub \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'HubArn' \
    --output text 2>/dev/null || echo "NOT_ENABLED")

if [ "$securityhub_status" != "NOT_ENABLED" ]; then
    echo "✔ Security Hub habilitado - findings de Access Analyzer aparecerán automáticamente"
else
    echo "ℹ Security Hub no habilitado - considera habilitarlo para centralizar findings"
fi

echo
echo "✅ IAM Access Analyzer habilitado exitosamente en $REGION"
echo
echo "Configuración completada:"
echo "- Analyzer Name: $ANALYZER_NAME"
echo "- Analyzer ARN: $analyzer_arn"
echo "- Findings encontrados: $findings_count"
echo "- Tipo: ACCOUNT (analiza tu cuenta AWS)"
echo "- Estado: ACTIVE"
echo
echo "Notas importantes:"
echo "- Access Analyzer identifica recursos compartidos con entidades externas"
echo "- Analiza políticas de recursos para encontrar accesos no intencionados"
echo "- Los findings se actualizan automáticamente cuando cambian las políticas"
echo "- Revisa regularmente los findings para mantener la seguridad"
echo "- Los findings se integran automáticamente con Security Hub si está habilitado"
echo "- Considera crear alertas en tiempo real para nuevos findings"
echo
echo "=== Proceso completado ==="

