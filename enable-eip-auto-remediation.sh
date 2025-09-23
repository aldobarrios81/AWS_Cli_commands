#!/bin/bash
# enable-eip-auto-remediation.sh
# Auto-remediation: Libera Elastic IPs no asociadas
# Perfil y región
PROFILE="xxxx"
REGION="us-east-1"
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:xxxxxxxx:network-alerts"

echo "=== Auto-Remediation EIPs no asociadas ==="
echo "Perfil: $PROFILE | Región: $REGION"

# Listar todas las EIPs
EIPS=$(aws ec2 describe-addresses --query 'Addresses[?AssociationId==`null`].AllocationId' --output text --profile $PROFILE --region $REGION)

if [[ -z "$EIPS" ]]; then
    echo "✔ No hay EIPs no asociadas"
else
    for ALLOC_ID in $EIPS; do
        echo "-> Liberando EIP: $ALLOC_ID"
        aws ec2 release-address --allocation-id $ALLOC_ID --profile $PROFILE --region $REGION
        echo "   ✔ EIP liberada: $ALLOC_ID"
        
        # Opcional: notificar via SNS
        if [[ ! -z $SNS_TOPIC_ARN ]]; then
            aws sns publish --topic-arn $SNS_TOPIC_ARN \
                --message "Se liberó Elastic IP no asociada: $ALLOC_ID en $REGION" \
                --profile $PROFILE
            echo "   ✔ Notificación enviada a SNS"
        fi
    done
fi

echo "=== Proceso completado ✅ ==="

