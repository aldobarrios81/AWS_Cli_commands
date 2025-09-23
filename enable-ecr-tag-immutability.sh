#!/bin/bash
REGION="us-east-1"
PROFILE="xxxxxxx"

echo "=== Habilitando Tag Immutability en todos los ECR Repositories en $REGION ==="

# Listar todos los repositorios
REPOS=$(aws ecr describe-repositories \
    --region $REGION \
    --profile $PROFILE \
    --query "repositories[].repositoryName" \
    --output text)

for REPO in $REPOS; do
    echo "-> Configurando tag immutability para repositorio: $REPO"

    # Habilitar inmutabilidad de tags
    aws ecr put-image-tag-mutability \
        --repository-name $REPO \
        --image-tag-mutability IMMUTABLE \
        --region $REGION \
        --profile $PROFILE

    echo "   ✔ Tag Immutability habilitado para $REPO"
done

echo "=== Tag Immutability habilitado en todos los repositorios ✅ ==="

