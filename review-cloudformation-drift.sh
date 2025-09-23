#!/bin/bash
REGION="us-east-1"
PROFILE="xxxxxx"

echo "=== Revisando Drift en todos los CloudFormation Stacks en $REGION ==="

# Listar todos los stacks
STACKS=$(aws cloudformation list-stacks \
    --region $REGION \
    --profile $PROFILE \
    --query "StackSummaries[?StackStatus!='DELETE_COMPLETE'].StackName" \
    --output text)

for STACK in $STACKS; do
    echo "-> Iniciando detección de drift para stack: $STACK"

    # Iniciar la detección de drift
    DETECT_ID=$(aws cloudformation detect-stack-drift \
        --stack-name $STACK \
        --region $REGION \
        --profile $PROFILE \
        --query "StackDriftDetectionId" \
        --output text)

    # Esperar a que la detección termine
    STATUS="DETECTION_IN_PROGRESS"
    while [ "$STATUS" == "DETECTION_IN_PROGRESS" ]; do
        sleep 5
        STATUS=$(aws cloudformation describe-stack-drift-detection-status \
            --stack-drift-detection-id $DETECT_ID \
            --region $REGION \
            --profile $PROFILE \
            --query "DetectionStatus" \
            --output text)
    done

    # Mostrar el resultado
    DRIFT_STATUS=$(aws cloudformation describe-stack-drift-detection-status \
        --stack-drift-detection-id $DETECT_ID \
        --region $REGION \
        --profile $PROFILE \
        --query "StackDriftStatus" \
        --output text)
    
    echo "   ✔ Drift status para $STACK: $DRIFT_STATUS"
done

echo "=== Revisión de CloudFormation Stack Drift completada ✅ ==="

