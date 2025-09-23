#!/bin/bash

REGION="us-east-1"
PROFILE="xxxxxxx"
SCOPE="REGIONAL"  # Cambiar a CLOUDFRONT si es global

echo "=== Buscando WAFv2 Web ACLs sin asociación en $REGION ==="

# Listar todos los Web ACLs
WEB_ACLS=$(aws wafv2 list-web-acls \
    --scope $SCOPE \
    --region $REGION \
    --profile $PROFILE \
    --query "WebACLs[].{Name:Name,Id:Id}" \
    --output json)

# Iterar sobre cada Web ACL
for row in $(echo "${WEB_ACLS}" | jq -c '.[]'); do
    NAME=$(echo $row | jq -r '.Name')
    ID=$(echo $row | jq -r '.Id')
    
    echo "-> Revisando Web ACL: $NAME / $ID"

    # Revisar asociaciones
    ASSOCIATIONS=$(aws wafv2 list-resources-for-web-acl \
        --web-acl-arn arn:aws:wafv2:$REGION:xxxxxxxxxxxxx:regional/webacl/$NAME/$ID \
        --region $REGION \
        --profile $PROFILE \
        --query "ResourceArns" \
        --output text)
    
    if [ -z "$ASSOCIATIONS" ]; then
        echo "   ⚡ No tiene asociaciones, eliminando Web ACL..."

        # Obtener LockToken
        LOCK_TOKEN=$(aws wafv2 get-web-acl \
            --name $NAME \
            --scope $SCOPE \
            --id $ID \
            --region $REGION \
            --profile $PROFILE \
            --query "LockToken" \
            --output text)

        # Eliminar Web ACL
        aws wafv2 delete-web-acl \
            --name $NAME \
            --scope $SCOPE \
            --id $ID \
            --lock-token $LOCK_TOKEN \
            --region $REGION \
            --profile $PROFILE

        echo "   ✔ Web ACL eliminada: $NAME / $ID"
    else
        echo "   ⚠ Web ACL tiene asociaciones, no se elimina."
    fi
done

echo "✅ Proceso completado: WAFv2 Web ACLs sin uso eliminadas"

