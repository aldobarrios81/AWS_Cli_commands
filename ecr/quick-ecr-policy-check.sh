#!/bin/bash
# quick-ecr-policy-check.sh
# Verificación rápida de políticas ECR para el perfil metrokia

PROFILE="metrokia"
REGION="us-east-1"

echo "=== VERIFICACIÓN RÁPIDA ECR RESOURCE POLICIES ==="
echo "Perfil: $PROFILE | Región: $REGION"
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Listar repositorios
echo "Repositorios ECR encontrados:"
aws ecr describe-repositories --profile "$PROFILE" --region "$REGION" --query 'repositories[].[repositoryName,createdAt]' --output table

echo ""
echo "=== Verificación de Resource Policies ==="

# Para cada repositorio, verificar si tiene política
aws ecr describe-repositories --profile "$PROFILE" --region "$REGION" --query 'repositories[].repositoryName' --output text | while read repo; do
    if [ -n "$repo" ]; then
        echo "Repositorio: $repo"
        
        # Verificar política
        policy=$(aws ecr get-repository-policy --repository-name "$repo" --profile "$PROFILE" --region "$REGION" --query 'policyText' --output text 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$policy" ] && [ "$policy" != "None" ]; then
            echo "  ✅ Tiene Resource Policy configurada"
            
            # Verificar si es pública
            if echo "$policy" | grep -q '"Principal": "\*"'; then
                echo "  🚨 RIESGO: Política permite acceso público"
            elif echo "$policy" | grep -q '"Service": "lambda.amazonaws.com"'; then
                echo "  ⚠️ Política para servicio Lambda"
            else
                echo "  ✅ Política parece restrictiva"
            fi
        else
            echo "  ❌ SIN Resource Policy configurada"
        fi
        echo ""
    fi
done

echo "=== Resumen de Configuraciones de Seguridad ==="
# Contar repositorios con/sin políticas
WITH_POLICY=0
WITHOUT_POLICY=0

aws ecr describe-repositories --profile "$PROFILE" --region "$REGION" --query 'repositories[].repositoryName' --output text | while read repo; do
    if [ -n "$repo" ]; then
        policy=$(aws ecr get-repository-policy --repository-name "$repo" --profile "$PROFILE" --region "$REGION" --query 'policyText' --output text 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$policy" ] && [ "$policy" != "None" ]; then
            WITH_POLICY=$((WITH_POLICY + 1))
        else
            WITHOUT_POLICY=$((WITHOUT_POLICY + 1))
        fi
    fi
done

echo "📊 Repositorios con políticas: $WITH_POLICY"
echo "📊 Repositorios sin políticas: $WITHOUT_POLICY"