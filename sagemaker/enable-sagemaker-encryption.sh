#!/bin/bash
# enable-sagemaker-encryption.sh
# Habilita cifrado At-Rest en SageMaker Notebook Instances

REGION="us-east-1"
PROFILE="xxxxxxx"

# Key KMS que se usará para cifrado. Puede ser "alias/aws/sagemaker" o tu key propia
KMS_KEY="alias/aws/sagemaker"

echo "=== Habilitando cifrado At-Rest para SageMaker Notebooks en $REGION ==="

# Listar todos los notebooks
NOTEBOOKS=$(aws sagemaker list-notebook-instances --region $REGION --profile $PROFILE --query 'NotebookInstances[].NotebookInstanceName' --output text)

for NB in $NOTEBOOKS; do
    echo "-> Verificando notebook: $NB"

    # Obtener información del notebook
    INFO=$(aws sagemaker describe-notebook-instance --notebook-instance-name $NB --region $REGION --profile $PROFILE)
    
    # Revisar si ya está cifrado
    ENCRYPTED=$(echo "$INFO" | jq -r '.KmsKeyId')
    if [ "$ENCRYPTED" != "null" ]; then
        echo "   ✔ Notebook ya tiene cifrado: $ENCRYPTED"
        continue
    fi

    # Actualizar notebook para habilitar cifrado At-Rest
    aws sagemaker update-notebook-instance \
        --notebook-instance-name $NB \
        --kms-key-id $KMS_KEY \
        --region $REGION \
        --profile $PROFILE

    echo "   ✔ Cifrado habilitado para $NB con KMS Key $KMS_KEY"
done

echo "✅ Proceso completado"

