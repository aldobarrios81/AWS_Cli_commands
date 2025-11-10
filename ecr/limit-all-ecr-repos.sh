#!/bin/bash
# ======================================================
# limit-all-ecr-repos.sh
# Script para limitar acceso a TODOS los repositorios ECR con Resource Policies
# Perfil: azcenit | Región: us-east-1
# ======================================================

AWS_PROFILE="azcenit"
AWS_REGION="us-east-1"

# Tu cuenta autorizada
ALLOWED_ACCOUNT="044616935970"

echo "=== Listando repositorios ECR en $AWS_REGION (perfil: $AWS_PROFILE) ==="

# Obtenemos todos los repositorios
REPOS=$(aws ecr describe-repositories \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --query "repositories[].repositoryName" \
  --output text)

if [ -z "$REPOS" ]; then
    echo "⚠️ No se encontraron repositorios en la región $AWS_REGION"
    exit 0
fi

for REPO in $REPOS; do
    echo "------------------------------------------------------------"
    echo "Procesando repositorio: $REPO"

    POLICY_JSON=$(cat <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "RestrictAccessPolicy",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$ALLOWED_ACCOUNT:root"
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ]
    }
  ]
}
EOF
)

    # Aplicamos la policy al repositorio
    aws ecr set-repository-policy \
      --repository-name "$REPO" \
      --policy-text "$POLICY_JSON" \
      --region $AWS_REGION \
      --profile $AWS_PROFILE

    if [ $? -eq 0 ]; then
        echo "✅ Restricción aplicada exitosamente en $REPO"
    else
        echo "❌ Error aplicando restricción en $REPO"
    fi
done

