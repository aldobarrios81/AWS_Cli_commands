#!/bin/bash
# enable-lambda-dlq-filtered.sh
# Configura Dead-Letter Queue para Lambdas no gestionadas por AppSync

REGION="us-east-1"
PROFILE="xxxxxxx"
DLQ_NAME="Lambda-DLQ"

echo "=== Configurando Dead-Letter Queue para Lambda Functions en $REGION ==="

# Crear DLQ si no existe
DLQ_URL=$(aws sqs get-queue-url --queue-name "$DLQ_NAME" --region $REGION --profile $PROFILE --query 'QueueUrl' --output text 2>/dev/null)
if [ -z "$DLQ_URL" ]; then
    echo "-> DLQ '$DLQ_NAME' no existe. Creando..."
    DLQ_URL=$(aws sqs create-queue --queue-name "$DLQ_NAME" --region $REGION --profile $PROFILE --query 'QueueUrl' --output text)
    echo "   ✔ DLQ creada: $DLQ_URL"
else
    echo "✔ DLQ '$DLQ_NAME' ya existe: $DLQ_URL"
fi

DLQ_ARN=$(aws sqs get-queue-attributes --queue-url "$DLQ_URL" --attribute-names QueueArn --region $REGION --profile $PROFILE --query 'Attributes.QueueArn' --output text)
echo "✔ ARN de DLQ: $DLQ_ARN"

# Listar Lambdas
LAMBDA_LIST=$(aws lambda list-functions --region $REGION --profile $PROFILE --query 'Functions[].FunctionName' --output text)

CONFIGURED=()
SKIPPED=()

for FUNCTION in $LAMBDA_LIST; do
    if [[ "$FUNCTION" == *"AppSync"* ]]; then
        echo "-> Omitiendo Lambda gestionada por AppSync: $FUNCTION"
        SKIPPED+=("$FUNCTION")
        continue
    fi

    echo "-> Configurando DLQ para Lambda: $FUNCTION"
    aws lambda update-function-configuration \
        --function-name "$FUNCTION" \
        --dead-letter-config TargetArn="$DLQ_ARN" \
        --region $REGION --profile $PROFILE >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "   ✔ DLQ configurada para $FUNCTION"
        CONFIGURED+=("$FUNCTION")
    else
        echo "   ⚠ Error configurando DLQ para $FUNCTION"
        SKIPPED+=("$FUNCTION")
    fi
done

# Resumen
echo "=== Resumen DLQ Lambda ==="
echo "✔ Configuradas:"
for f in "${CONFIGURED[@]}"; do
    echo "   - $f"
done

echo "⚠ Omitidas o con error:"
for f in "${SKIPPED[@]}"; do
    echo "   - $f"
done

echo "✅ Proceso completado"

