#!/bin/bash
# Habilita IAM Access Analyzer en us-east-1
# Perfil fijo: xxxxxx | Región fija: us-east-1

PROFILE="xxxxxxxx"
REGION="us-east-1"
ANALYZER_NAME="default-analyzer"

echo "=== Habilitando IAM Access Analyzer en $REGION ==="

# Verificar si ya existe el analyzer
EXISTING_ANALYZER=$(aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "analyzers[?name=='$ANALYZER_NAME'].name" \
    --output text)

if [ -n "$EXISTING_ANALYZER" ]; then
    echo "✔ Analyzer '$ANALYZER_NAME' ya existe"
else
    echo "Creando analyzer '$ANALYZER_NAME'..."
    aws accessanalyzer create-analyzer \
        --analyzer-name "$ANALYZER_NAME" \
        --type ACCOUNT \
        --region "$REGION" \
        --profile "$PROFILE"
    echo "✔ Analyzer creado"
fi

echo "=== IAM Access Analyzer habilitado en $REGION ✅ ==="

