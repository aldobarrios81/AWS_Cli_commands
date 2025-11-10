#!/bin/bash
# detach-iam-roles-internet-ec2.sh
# Detecta EC2 con IP pública y roles IAM adjuntos y los desasocia.

REGION="us-east-1"
PROFILE="xxxxxxxxx"

echo "=== Detectando EC2 Internet-Facing con IAM Roles en $REGION ==="

# Obtener todas las instancias con IP pública
instances=$(aws ec2 describe-instances \
    --profile $PROFILE \
    --region $REGION \
    --query 'Reservations[].Instances[?PublicIpAddress!=null].[InstanceId,IamInstanceProfile.Arn]' \
    --output text)

if [ -z "$instances" ]; then
    echo "No se encontraron instancias con IP pública y roles IAM."
    exit 0
fi

echo "$instances" | while read instance_id iam_arn; do
    if [ "$iam_arn" != "None" ] && [ ! -z "$iam_arn" ]; then
        echo "-> Instancia $instance_id tiene rol IAM $iam_arn"
        echo "   Desasociando rol IAM..."
        aws ec2 disassociate-iam-instance-profile \
            --profile $PROFILE \
            --region $REGION \
            --association-id $(aws ec2 describe-iam-instance-profile-associations \
                --profile $PROFILE \
                --region $REGION \
                --query "IamInstanceProfileAssociations[?InstanceId=='$instance_id'].AssociationId" \
                --output text)
        echo "   ✅ Rol desasociado"
    else
        echo "-> Instancia $instance_id no tiene rol IAM, se omite."
    fi
done

echo "=== Proceso completado ✅ ==="

