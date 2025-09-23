#!/bin/bash
# enable-cloudformation-stack-notifications.sh
# Habilita notificaciones solo en stacks compatibles

PROFILE="azbexxxxxxacons"
REGION="us-east-1"
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:xxxxxxxxxx:cloudformation-notifications"

echo "=== Habilitando notificaciones de eventos para CloudFormation Stacks compatibles en $REGION ==="

# Verificar que el topic SNS exista
if ! aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1; then
    echo "❌ SNS Topic no encontrado: $SNS_TOPIC_ARN"
    exit 1
else
    echo "✔ SNS Topic encontrado: $SNS_TOPIC_ARN"
fi

# Obtener stacks compatibles (omitimos Amplify, CDK, SST, DynamoTemplate, etc.)
STACKS=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --region "$REGION" --profile "$PROFILE" \
    | jq -r '.StackSummaries[].StackName' | grep -Ev "(amplify|CDK|SST|DynamoTemplate)")

if [ -z "$STACKS" ]; then
    echo "⚠ No hay stacks compatibles para habilitar notificaciones."
    exit 0
fi

SUCCESS_STACKS=()

for STACK in $STACKS; do
    echo "-> Configurando notificaciones para stack: $STACK"
    if aws cloudformation update-stack --stack-name "$STACK" \
        --notification-arns "$SNS_TOPIC_ARN" \
        --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1; then
        echo "   ✔ Notificaciones habilitadas para $STACK"
        SUCCESS_STACKS+=("$STACK")
    else
        echo "   ⚠ Stack no soporta notificaciones: $STACK (omitido)"
    fi
done

echo "=== Resumen de Notificaciones CloudFormation ==="
if [ ${#SUCCESS_STACKS[@]} -gt 0 ]; then
    echo "✔ Habilitadas en los siguientes stacks:"
    for S in "${SUCCESS_STACKS[@]}"; do
        echo "   - $S"
    done
else
    echo "⚠ No se habilitaron notificaciones en ningún stack compatible."
fi

echo "SNS Topic ARN usado: $SNS_TOPIC_ARN"
echo "✅ Proceso completado"

