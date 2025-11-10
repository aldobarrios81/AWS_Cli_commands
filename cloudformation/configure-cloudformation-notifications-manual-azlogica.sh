#!/bin/bash
# Configurar notificaciones manualmente para stacks que requieren parámetros
# Generado para perfil: azlogica

PROFILE="azlogica"
REGION="us-east-1"
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:ACCOUNT_ID:cloudformation-stack-notifications"

echo "Configurando notificaciones manualmente para stacks problemáticos..."
echo "SNS Topic ARN: $SNS_TOPIC_ARN"
echo ""

# Obtener Account ID dinámicamente
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$ACCOUNT_ID" ]; then
    SNS_TOPIC_ARN="arn:aws:sns:us-east-1:$ACCOUNT_ID:cloudformation-stack-notifications"
    echo "Account ID detectado: $ACCOUNT_ID"
    echo "SNS Topic ARN actualizado: $SNS_TOPIC_ARN"
else
    echo "Advertencia: No se pudo obtener Account ID. Actualiza manualmente el ARN."
fi

echo ""

# Obtener stacks que requieren configuración manual dinámicamente
echo "Obteniendo lista de stacks CloudFormation..."
FAILED_STACKS=($(aws cloudformation list-stacks --profile "$PROFILE" --region "$REGION" --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE --query 'StackSummaries[].StackName' --output text 2>/dev/null | tr '\t' '\n' | grep -v "^$"))

if [ ${#FAILED_STACKS[@]} -eq 0 ]; then
    echo "No se encontraron stacks para configurar manualmente."
    exit 0
fi

echo "Stacks encontrados para configuración manual:"
for stack in "${FAILED_STACKS[@]}"; do
    echo "  - $stack"
done
echo ""

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