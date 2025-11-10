#!/bin/bash
# Configurar notificaciones manualmente para stacks que requieren parámetros
# Generado para perfil: azcenit

PROFILE="azcenit"
REGION="us-east-1"
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:044616935970:cloudformation-stack-notifications"

echo "Configurando notificaciones manualmente para stacks problemáticos..."
echo "SNS Topic ARN: $SNS_TOPIC_ARN"
echo ""

# Stacks que requieren configuración manual
FAILED_STACKS=(prod-cenit-my-stack)

for stack in "${FAILED_STACKS[@]}"; do
    echo "Stack: $stack"
    echo "Comando sugerido:"
    echo "aws cloudformation update-stack \\"
    echo "  --stack-name $stack \\"
    echo "  --use-previous-template \\"
    echo "  --notification-arns $SNS_TOPIC_ARN \\"
    echo "  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\"
    echo "  --profile $PROFILE \\"
    echo "  --region $REGION"
    echo ""
    echo "Si el stack requiere parámetros, obtenerlos con:"
    echo "aws cloudformation describe-stacks --stack-name $stack --profile $PROFILE --region $REGION --query 'Stacks[0].Parameters'"
    echo ""
    echo "────────────────────────────────────────────────────────"
    echo ""
done
