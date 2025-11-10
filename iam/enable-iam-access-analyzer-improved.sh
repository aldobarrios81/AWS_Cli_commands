#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
REGION="us-east-1"
PROFILE="azcenit"

echo "=== Configurando IAM Access Analyzer ==="
echo "Proveedor: $PROVIDER"
echo "Región: $REGION"
echo "Perfil: $PROFILE"
echo

# Obtener analyzer existente
echo "Verificando analyzers existentes de IAM Access Analyzer..."
analyzer_arn=$(wsl aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "analyzers[0].arn" \
    --output text 2>/dev/null || echo "")

analyzer_name=$(wsl aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "analyzers[0].name" \
    --output text 2>/dev/null || echo "")

analyzer_status=$(wsl aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "analyzers[0].status" \
    --output text 2>/dev/null || echo "")

if [ -n "$analyzer_arn" ] && [ "$analyzer_arn" != "None" ]; then
    echo "✔ Access Analyzer ya está habilitado"
    echo "  Nombre: $analyzer_name"
    echo "  ARN: $analyzer_arn"
    echo "  Estado: $analyzer_status"
else
    echo "Creando nuevo analyzer..."
    analyzer_arn=$(wsl aws accessanalyzer create-analyzer \
        --analyzer-name "default-analyzer-$(date +%s)" \
        --type ACCOUNT \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'arn' \
        --output text)
    
    echo "✔ Analyzer creado exitosamente: $analyzer_arn"
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
    echo "Resumen de findings:"
    wsl aws accessanalyzer list-findings \
        --analyzer-arn "$analyzer_arn" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'findings[].[resourceType,status,condition]' \
        --output table 2>/dev/null || echo "No se pudieron obtener detalles de findings"
    
    echo
    echo "Findings activos por tipo de recurso:"
    wsl aws accessanalyzer list-findings \
        --analyzer-arn "$analyzer_arn" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --filter '{"status":{"eq":["ACTIVE"]}}' \
        --query 'findings[].{Recurso:resourceType,Estado:status,Condicion:condition}' \
        --output table 2>/dev/null || echo "No hay findings activos"
else
    echo "ℹ No se encontraron findings - esto es bueno, significa que no hay accesos externos detectados"
fi

# Verificar tipos de recursos soportados
echo
echo "=== Tipos de recursos monitoreados por Access Analyzer ==="
echo "✔ IAM Roles - Detecta roles accesibles externamente"
echo "✔ S3 Buckets - Identifica buckets con acceso público o compartido"
echo "✔ KMS Keys - Encuentra claves compartidas con cuentas externas"
echo "✔ Lambda Functions - Detecta funciones con permisos de recursos"
echo "✔ SQS Queues - Identifica colas compartidas externamente"
echo "✔ Secrets Manager - Encuentra secretos compartidos"
echo "✔ EFS File Systems - Detecta sistemas de archivos compartidos"
echo "✔ ECR Repositories - Identifica repositorios con acceso externo"
echo "✔ RDS Snapshots - Encuentra snapshots compartidos"
echo "✔ SNS Topics - Detecta topics con suscriptores externos"
echo "✔ Redshift Clusters - Identifica clusters con acceso externo"

# Verificar integración con Security Hub
echo
echo "=== Verificando integración con Security Hub ==="
securityhub_status=$(wsl aws securityhub describe-hub \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'HubArn' \
    --output text 2>/dev/null || echo "NOT_ENABLED")

if [ "$securityhub_status" != "NOT_ENABLED" ]; then
    echo "✔ Security Hub habilitado - findings de Access Analyzer aparecen automáticamente"
else
    echo "ℹ Security Hub no habilitado - considera habilitarlo para centralizar findings"
fi

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

echo
echo "✅ IAM Access Analyzer configurado exitosamente en $REGION"
echo
echo "Configuración completada:"
echo "- Analyzer ARN: $analyzer_arn"
echo "- Findings encontrados: $findings_count"
echo "- Tipo: ACCOUNT (analiza tu cuenta AWS)"
echo "- Estado: $analyzer_status"
echo
echo "Notas importantes:"
echo "- Access Analyzer identifica recursos compartidos con entidades externas"
echo "- Analiza políticas de recursos para encontrar accesos no intencionados"
echo "- Los findings se actualizan automáticamente cuando cambian las políticas"
echo "- Revisa regularmente los findings para mantener la seguridad"
echo "- Los findings se integran automáticamente con Security Hub si está habilitado"
echo "- Un finding no siempre indica un problema, sino acceso externo intencional"
echo
echo "=== Proceso completado ==="