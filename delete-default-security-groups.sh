#!/bin/bash
REGION="us-east-1"
PROFILE="xxxxxxxxx"

echo "=== Eliminando Security Groups por defecto en $REGION ==="

# Listar Security Groups por defecto
DEFAULT_SGS=$(aws ec2 describe-security-groups \
    --region $REGION \
    --profile $PROFILE \
    --filters Name=group-name,Values=default \
    --query "SecurityGroups[].GroupId" \
    --output text)

for SG in $DEFAULT_SGS; do
    echo "-> Intentando eliminar Security Group: $SG"

    # Verificar si está asociado a instancias
    ASSOCIATED=$(aws ec2 describe-network-interfaces \
        --region $REGION \
        --profile $PROFILE \
        --filters Name=group-id,Values=$SG \
        --query "NetworkInterfaces" \
        --output text)

    if [ -z "$ASSOCIATED" ]; then
        aws ec2 delete-security-group \
            --group-id $SG \
            --region $REGION \
            --profile $PROFILE
        echo "   ✔ Security Group $SG eliminado"
    else
        echo "   ⚠ Security Group $SG está en uso, no se puede eliminar"
    fi
done

echo "=== Proceso completado ✅ ==="

