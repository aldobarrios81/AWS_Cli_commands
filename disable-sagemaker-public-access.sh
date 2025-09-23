#!/bin/bash
# disable-sagemaker-public-access.sh
# Detecta SageMaker Notebook Instances con acceso público y lo deshabilita.

REGION="us-east-1"
PROFILE="xxxxxxx"

echo "=== Revisando SageMaker Notebook Instances con acceso público en $REGION ==="

# Listar todas las notebooks
notebooks=$(aws sagemaker list-notebook-instances \
    --profile $PROFILE \
    --region $REGION \
    --query 'NotebookInstances[].NotebookInstanceName' \
    --output text)

if [ -z "$notebooks" ]; then
    echo "No se encontraron SageMaker Notebook Instances."
    exit 0
fi

for nb in $notebooks; do
    # Obtener configuración de acceso público
    public_access=$(aws sagemaker describe-notebook-instance \
        --profile $PROFILE \
        --region $REGION \
        --notebook-instance-name $nb \
        --query 'DirectInternetAccess' \
        --output text)

    if [ "$public_access" == "Enabled" ]; then
        echo "-> Notebook $nb tiene acceso público habilitado. Deshabilitando..."
        aws sagemaker update-notebook-instance \
            --profile $PROFILE \
            --region $REGION \
            --notebook-instance-name $nb \
            --no-direct-internet-access
        echo "   ✅ Acceso público deshabilitado"
    else
        echo "-> Notebook $nb ya tiene acceso público deshabilitado, se omite."
    fi
done

echo "=== Proceso completado ✅ ==="

