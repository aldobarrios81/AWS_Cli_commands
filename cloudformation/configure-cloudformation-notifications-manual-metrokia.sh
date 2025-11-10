#!/bin/bash
# Configurar notificaciones manualmente para stacks que requieren parámetros
# Generado para perfil: metrokia

PROFILE="metrokia"
REGION="us-east-1"
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:848576886895:cloudformation-stack-notifications"

echo "Configurando notificaciones manualmente para stacks problemáticos..."
echo "SNS Topic ARN: $SNS_TOPIC_ARN"
echo ""

# Stacks que requieren configuración manual
FAILED_STACKS=(prod-things-StackGildemeister prod-things-StackScrum prod-things-stackDeepEye prod-things-StackTeamManager prod-things-StackBaik prod-things-StackEvolucion prod-things-StackRpcol prod-things-StackGunnebo prod-things-StackIOT prod-things-StackRANSA test-things-StackMetrokia test-things-API prod-things-StackMetrokia prod-things-API az-things-StackMetrokia prod-metrokia-my-stack)

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
