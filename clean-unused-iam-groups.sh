#!/bin/bash
# clean-unused-iam-groups-final.sh
# Limpia grupos IAM sin usuarios de forma segura
# Perfil: xxxxxx | Región: us-east-1

PROFILE="azcenit"
REGION="us-east-1"

echo "=== Limpiando grupos IAM sin usuarios en $REGION ==="

# Listar todos los grupos
GROUPS=$(aws iam list-groups --profile $PROFILE --region $REGION --query 'Groups[*].GroupName' --output text)

for GROUP in $GROUPS; do
    # Ignorar nombres vacíos
    if [ -z "$GROUP" ]; then
        continue
    fi

    # Ignorar nombres inválidos (no comienzan con letra o guion bajo)
    if ! [[ "$GROUP" =~ ^[a-zA-Z_].* ]]; then
        continue
    fi

    # Contar usuarios en el grupo
    USER_COUNT=$(aws iam get-group --group-name "$GROUP" --profile $PROFILE --region $REGION --query 'Users | length(@)' --output text 2>/dev/null)

    # Validar que USER_COUNT sea un número
    if ! [[ "$USER_COUNT" =~ ^[0-9]+$ ]]; then
        echo "⚠ Error al obtener usuarios para grupo: $GROUP. Se omite."
        continue
    fi

    if [ "$USER_COUNT" -eq 0 ]; then
        echo "-> Eliminando grupo sin usuarios: $GROUP"
        aws iam delete-group --group-name "$GROUP" --profile $PROFILE --region $REGION
        echo "   ✔ Grupo $GROUP eliminado"
    else
        echo "-> Grupo $GROUP tiene $USER_COUNT usuario(s). Se omite."
    fi
done

echo "=== Limpieza de grupos IAM completada ✅ ==="

