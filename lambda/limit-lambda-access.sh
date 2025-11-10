#!/bin/bash
# ======================================================
# limit-all-lambdas.sh
# Script para limitar acceso a TODAS las Lambda Functions con Resource Policies
# Perfil: azcenit | Región: us-east-1
# ======================================================

AWS_PROFILE="azcenit"
AWS_REGION="us-east-1"

# Variables de restricción - Ajusta según lo que necesites
STATEMENT_ID="RestrictAccessPolicy"
PRINCIPAL="s3.amazonaws.com"   # Ejemplo: solo S3 puede invocar las Lambdas
SOURCE_ARN="arn:aws:s3:::mi-bucket-ejemplo"  # Bucket autorizado

echo "=== Listando funciones Lambda en $AWS_REGION (perfil: $AWS_PROFILE) ==="

# Obtenemos todas las funciones Lambda
FUNCTIONS=$(aws lambda list-functions \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --query "Functions[].FunctionName" \
  --output text)

if [ -z "$FUNCTIONS" ]; then
    echo "⚠️ No se encontraron funciones Lambda en la región $AWS_REGION"
    exit 0
fi

for FN in $FUNCTIONS; do
    echo "------------------------------------------------------------"
    echo "Procesando función: $FN"

    # Eliminar permiso anterior si existe
    aws lambda remove-permission \
      --function-name "$FN" \
      --statement-id $STATEMENT_ID \
      --region $AWS_REGION \
      --profile $AWS_PROFILE 2>/dev/null

    # Agregar nueva policy de restricción
    aws lambda add-permission \
      --function-name "$FN" \
      --statement-id $STATEMENT_ID \
      --action "lambda:InvokeFunction" \
      --principal $PRINCIPAL \
      --source-arn $SOURCE_ARN \
      --region $AWS_REGION \
      --profile $AWS_PROFILE

    if [ $? -eq 0 ]; then
        echo "✅ Restricción aplicada en $FN"
    else
        echo "❌ Error aplicando restricción en $FN"
    fi
done

