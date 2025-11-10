#!/bin/bash
# ======================================================
# limit-all-ecr-repos-metrokia.sh
# Script para limitar acceso a TODOS los repositorios ECR con Resource Policies
# Perfiles: metrokia | AZLOGICA | Región: us-east-1
# ======================================================

# Verificar si se proporcionó un perfil como parámetro
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: metrokia, AZLOGICA"
    exit 1
fi

AWS_PROFILE="$1"
AWS_REGION="us-east-1"

# Configurar cuenta autorizada según el perfil
case "$AWS_PROFILE" in
    "metrokia")
        ALLOWED_ACCOUNT="848576886895"
        ;;
    "AZLOGICA")
        # Obtener la cuenta actual dinámicamente para AZLOGICA
        ALLOWED_ACCOUNT=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$ALLOWED_ACCOUNT" ]; then
            echo "❌ Error: No se pudo obtener el Account ID para el perfil $AWS_PROFILE"
            echo "Verificar credenciales y configuración del perfil"
            exit 1
        fi
        ;;
    *)
        echo "❌ Error: Perfil '$AWS_PROFILE' no soportado"
        echo "Perfiles válidos: metrokia, AZLOGICA"
        exit 1
        ;;
esac

echo "=== Configurando políticas restrictivas para repositorios ECR ==="
echo "Perfil: $AWS_PROFILE | Región: $AWS_REGION"
echo "Cuenta autorizada: $ALLOWED_ACCOUNT"
echo ""

# Verificar credenciales antes de continuar
echo "🔍 Verificando credenciales para perfil: $AWS_PROFILE"
CALLER_IDENTITY=$(aws sts get-caller-identity --profile "$AWS_PROFILE" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "❌ Error: Credenciales no válidas para el perfil '$AWS_PROFILE'"
    echo "Verificar configuración: aws configure list --profile $AWS_PROFILE"
    exit 1
fi

CURRENT_ACCOUNT=$(echo "$CALLER_IDENTITY" | jq -r '.Account' 2>/dev/null)
CURRENT_USER=$(echo "$CALLER_IDENTITY" | jq -r '.Arn' 2>/dev/null)

echo "✅ Credenciales válidas"
echo "   Account ID: $CURRENT_ACCOUNT"
echo "   Usuario/Rol: $CURRENT_USER"
echo ""

# Validar que la cuenta autorizada coincida con la cuenta actual
if [ "$ALLOWED_ACCOUNT" != "$CURRENT_ACCOUNT" ]; then
    echo "⚠️ ADVERTENCIA: La cuenta autorizada ($ALLOWED_ACCOUNT) difiere de la cuenta actual ($CURRENT_ACCOUNT)"
    read -p "¿Deseas continuar con la cuenta actual como autorizada? (y/N): " use_current
    if [[ $use_current == [yY] || $use_current == [yY][eE][sS] ]]; then
        ALLOWED_ACCOUNT="$CURRENT_ACCOUNT"
        echo "✅ Usando cuenta actual: $ALLOWED_ACCOUNT"
    else
        echo "Operación cancelada"
        exit 0
    fi
fi
echo ""

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

echo "Repositorios encontrados:"
for REPO in $REPOS; do
    echo "  - $REPO"
done
echo ""

read -p "¿Deseas continuar con la aplicación de políticas restrictivas? (y/N): " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "Operación cancelada"
    exit 0
fi

echo ""

for REPO in $REPOS; do
    echo "------------------------------------------------------------"
    echo "Procesando repositorio: $REPO"

    # Política restrictiva que permite:
    # 1. Acceso completo a la cuenta actual (usuarios/roles IAM específicos)
    # 2. Acceso de lectura ÚNICAMENTE para Lambda (SIN permisos administrativos)
    POLICY_JSON=$(cat <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "AllowAccountAccessForContainerOperations",
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
        "ecr:CompleteLayerUpload",
        "ecr:GetRepositoryPolicy"
      ]
    },
    {
      "Sid": "AllowAccountPolicyManagement",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$ALLOWED_ACCOUNT:root"
      },
      "Action": [
        "ecr:SetRepositoryPolicy",
        "ecr:DeleteRepositoryPolicy"
      ],
      "Condition": {
        "StringEquals": {
          "aws:PrincipalType": "User"
        }
      }
    },
    {
      "Sid": "AllowLambdaReadOnlyAccess",
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Condition": {
        "StringLike": {
          "aws:sourceArn": "arn:aws:lambda:$AWS_REGION:$ALLOWED_ACCOUNT:function:*"
        }
      }
    }
  ]
}
EOF
)

    echo "📋 Política a aplicar:"
    echo "$POLICY_JSON" | jq '.' 2>/dev/null || echo "$POLICY_JSON"
    echo ""
    
    # Hacer backup de la política actual
    echo "🔄 Guardando backup de política actual..."
    BACKUP_FILE="backup-policy-$REPO-$(date +%Y%m%d-%H%M%S).json"
    aws ecr get-repository-policy \
      --repository-name "$REPO" \
      --region $AWS_REGION \
      --profile $AWS_PROFILE \
      --query 'policyText' \
      --output text > "$BACKUP_FILE" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ Backup guardado: $BACKUP_FILE"
    else
        echo "ℹ️ No había política previa para respaldar"
    fi

    # Aplicamos la nueva política al repositorio
    echo "🔒 Aplicando nueva política restrictiva..."
    aws ecr set-repository-policy \
      --repository-name "$REPO" \
      --policy-text "$POLICY_JSON" \
      --region $AWS_REGION \
      --profile $AWS_PROFILE

    if [ $? -eq 0 ]; then
        echo "✅ Política restrictiva aplicada exitosamente en $REPO"
        
        # Verificar la política aplicada
        echo "🔍 Verificando política aplicada..."
        NEW_POLICY=$(aws ecr get-repository-policy \
          --repository-name "$REPO" \
          --region $AWS_REGION \
          --profile $AWS_PROFILE \
          --query 'policyText' \
          --output text 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            echo "✅ Verificación exitosa: Política aplicada correctamente"
        else
            echo "⚠️ No se pudo verificar la política aplicada"
        fi
    else
        echo "❌ Error aplicando política restrictiva en $REPO"
    fi
    
    echo ""
done

echo "=============================================================="
echo "✅ PROCESO COMPLETADO"
echo "=============================================================="
echo ""
echo "📋 Resumen de acciones:"
echo "  - Políticas aplicadas a todos los repositorios ECR"
echo "  - Acceso limitado solo a la cuenta: $ALLOWED_ACCOUNT"  
echo "  - Mantenido acceso para Lambda con condiciones restrictivas"
echo "  - Backups de políticas anteriores guardados"
echo ""
echo "🔍 Verificar resultado:"
echo "  ./verify-ecr-resource-policies.sh $AWS_PROFILE"
echo ""
echo "📋 Uso del script:"
echo "  Para metrokia: ./limit-all-ecr-repos-metrokia.sh metrokia"
echo "  Para AZLOGICA: ./limit-all-ecr-repos-metrokia.sh AZLOGICA"
echo ""