#!/bin/bash
# ======================================================
# deactivate-iam-access-keys.sh
# Script para desactivar UNA access key activa de cada usuario IAM
# Perfil: azcenit | Región: us-east-1
# ======================================================

AWS_PROFILE="azcenit"
AWS_REGION="us-east-1"

echo "=== Listando usuarios IAM (perfil: $AWS_PROFILE) ==="

# Obtenemos todos los usuarios
USERS=$(aws iam list-users \
  --profile $AWS_PROFILE \
  --query "Users[].UserName" \
  --output text)

if [ -z "$USERS" ]; then
    echo "⚠️ No se encontraron usuarios IAM en la cuenta"
    exit 0
fi

for USER in $USERS; do
    echo "------------------------------------------------------------"
    echo "Procesando usuario: $USER"

    # Obtenemos las access keys activas
    ACTIVE_KEYS=$(aws iam list-access-keys \
      --user-name $USER \
      --profile $AWS_PROFILE \
      --query "AccessKeyMetadata[?Status=='Active'].AccessKeyId" \
      --output text)

    KEY_COUNT=$(echo "$ACTIVE_KEYS" | wc -w)

    if [ "$KEY_COUNT" -eq 0 ]; then
        echo "ℹ️ El usuario $USER no tiene access keys activas"
        continue
    fi

    if [ "$KEY_COUNT" -eq 1 ]; then
        echo "ℹ️ El usuario $USER tiene solo una access key activa (no se desactiva)"
        continue
    fi

    # Si hay más de una key activa, desactivar la primera
    KEY_TO_DEACTIVATE=$(echo "$ACTIVE_KEYS" | awk '{print $1}')

    echo "🔑 Desactivando access key $KEY_TO_DEACTIVATE para $USER"
    aws iam update-access-key \
      --user-name $USER \
      --access-key-id $KEY_TO_DEACTIVATE \
      --status Inactive \
      --profile $AWS_PROFILE

    if [ $? -eq 0 ]; then
        echo "✅ Access key $KEY_TO_DEACTIVATE desactivada para $USER"
    else
        echo "❌ Error desactivando access key $KEY_TO_DEACTIVATE en $USER"
    fi
done

