#!/usr/bin/env bash
set -euo pipefail

# Verificar que se proporcione el perfil como parámetro
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
    exit 1
fi

PROFILE="$1"
DEFAULT_REGION="us-east-1"

# Verificar credenciales
if ! aws sts get-caller-identity --profile "$PROFILE" > /dev/null 2>&1; then
    echo "❌ Error: Credenciales no válidas para perfil '$PROFILE'"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$PROFILE")

echo "=== Habilitando Amazon Macie en todas las regiones ==="
echo "Perfil: $PROFILE  |  Account ID: $ACCOUNT_ID  |  Región inicial: $DEFAULT_REGION"

# 1. Obtener todas las regiones habilitadas
REGIONS=$(aws ec2 describe-regions \
    --region "$DEFAULT_REGION" \
    --profile "$PROFILE" \
    --query "Regions[].RegionName" \
    --output text)

# 2. Habilitar Macie en cada región
for region in $REGIONS; do
    echo
    echo "-> Región: $region"

    STATUS=$(aws macie2 get-macie-session \
        --region "$region" \
        --profile "$PROFILE" \
        --query "status" \
        --output text 2>/dev/null || true)

    if [[ "$STATUS" == "ENABLED" ]]; then
        echo "   Macie ya está habilitado en $region."
    else
        echo "   Habilitando Macie en $region..."
        aws macie2 enable-macie \
            --region "$region" \
            --profile "$PROFILE"
        echo "   Macie habilitado en $region."
    fi
done

echo
echo "=== Macie habilitado en todas las regiones habilitadas de tu cuenta ==="

