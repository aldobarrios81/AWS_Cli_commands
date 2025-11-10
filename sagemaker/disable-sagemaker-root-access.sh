#!/bin/bash
REGION="us-east-1"
PROFILE="xxxxxxx"

echo "=== Deshabilitando Root Access en SageMaker Notebook Instances en $REGION ==="

# Listar todas las instancias de SageMaker Notebook
NOTEBOOKS=$(aws sagemaker list-notebook-instances \
    --region $REGION \
    --profile $PROFILE \
    --query "NotebookInstances[].NotebookInstanceName" \
    --output text)

for NOTEBOOK in $NOTEBOOKS; do
    echo "-> Actualizando instancia: $NOTEBOOK"
    aws sagemaker update-notebook-instance \
        --notebook-instance-name $NOTEBOOK \
        --region $REGION \
        --profile $PROFILE \
        --root-access Disabled
    echo "   ✔ Root Access deshabilitado en $NOTEBOOK"
done

echo "=== Root Access deshabilitado en todas las instancias ✅ ==="

