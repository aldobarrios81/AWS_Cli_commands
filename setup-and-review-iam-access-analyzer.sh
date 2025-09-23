#!/bin/bash
# Revisar hallazgos de IAM Access Analyzer usando un analyzer existente
# Perfil fijo: xxxxxx
# Región fija: us-east-1

PROFILE="xxxxxxxx"
REGION="us-east-1"
ANALYZER_ARN="arn:aws:access-analyzer:us-east-1:xxxxxxxxxxxxx:analyzer/default-access-analyzer"

echo "=== Revisando IAM Access Analyzer findings en $REGION ==="
echo "Analyzer: $ANALYZER_ARN"

# Listar hallazgos activos
ACTIVE_FINDINGS=$(aws accessanalyzer list-findings \
    --analyzer-arn "$ANALYZER_ARN" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "findings[?status=='ACTIVE'].id" \
    --output text)

if [ -z "$ACTIVE_FINDINGS" ]; then
    echo "✔ No hay hallazgos activos en $REGION."
    exit 0
fi

echo "✔ Hallazgos activos encontrados: "
aws accessanalyzer list-findings \
    --analyzer-arn "$ANALYZER_ARN" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --output table \
    --query 'findings[*].{Id:id, Resource:resource, Status:status, CreatedAt:createdAt, UpdatedAt:updatedAt, Principal:principal, Action:actions}'

# Preguntar si se desean archivar
read -p "¿Deseas archivar todos los hallazgos activos? (y/n): " ARCHIVE

if [[ "$ARCHIVE" =~ ^[Yy]$ ]]; then
    for FINDING_ID in $ACTIVE_FINDINGS; do
        aws accessanalyzer update-findings \
            --analyzer-arn "$ANALYZER_ARN" \
            --region "$REGION" \
            --profile "$PROFILE" \
            --status ARCHIVED \
            --ids "$FINDING_ID"
        echo "✔ Hallazgo $FINDING_ID archivado"
    done
    echo "✅ Todos los hallazgos activos han sido archivados."
else
    echo "✋ No se archivaron hallazgos."
fi

