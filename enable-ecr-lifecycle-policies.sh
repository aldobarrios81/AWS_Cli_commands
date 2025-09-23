#!/bin/bash
# enable-ecr-lifecycle-policies.sh
# Habilita Lifecycle Policies en todos los repositorios ECR

REGION="us-east-1"
PROFILE="xxxxxxx"

echo "=== Habilitando Lifecycle Policies para repositorios ECR en $REGION ==="

# Listar todos los repositorios
REPOS=$(aws ecr describe-repositories --profile $PROFILE --region $REGION --query 'repositories[].repositoryName' --output text)

for REPO in $REPOS; do
    echo "-> Configurando Lifecycle Policy para repositorio: $REPO"

    # Policy de ejemplo: conservar solo las 10 imágenes más recientes
    POLICY='{
        "rules": [
            {
                "rulePriority": 1,
                "description": "Mantener solo 10 imágenes más recientes",
                "selection": {
                    "tagStatus": "any",
                    "countType": "imageCountMoreThan",
                    "countNumber": 10
                },
                "action": {
                    "type": "expire"
                }
            }
        ]
    }'

    # Aplicar Lifecycle Policy
    aws ecr put-lifecycle-policy \
        --repository-name "$REPO" \
        --lifecycle-policy-text "$POLICY" \
        --profile $PROFILE \
        --region $REGION

    echo "   ✔ Lifecycle Policy habilitada para $REPO"
done

echo "✅ Lifecycle Policies habilitadas en todos los repositorios ECR"

