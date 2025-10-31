#!/bin/bash
# ecr-immutability-summary.sh
# Verificar estado de tag immutability en todos los perfiles AWS

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

PROFILES=("ancla" "azbeacons" "azcenit")
REGION="us-east-1"

echo "=================================================================="
echo -e "${BLUE}🔍 RESUMEN ECR TAG IMMUTABILITY - TODOS LOS PERFILES${NC}"
echo "=================================================================="
echo -e "Fecha: ${GREEN}$(date)${NC}"
echo ""

# Variables de resumen
TOTAL_ACCOUNTS=0
COMPLIANT_ACCOUNTS=0
TOTAL_REPOSITORIES=0
IMMUTABLE_REPOSITORIES=0

for profile in "${PROFILES[@]}"; do
    echo -e "${PURPLE}=== Perfil: $profile ===${NC}"
    
    # Verificar credenciales
    ACCOUNT_ID=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
        echo -e "❌ Error: Credenciales no válidas para perfil '$profile'"
        continue
    fi
    
    echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
    TOTAL_ACCOUNTS=$((TOTAL_ACCOUNTS + 1))
    
    # Obtener repositorios ECR
    ECR_REPOSITORIES=$(aws ecr describe-repositories \
        --profile "$profile" \
        --region "$REGION" \
        --query 'repositories[].[repositoryName,imageTagMutability]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "⚠️ Error al obtener repositorios ECR"
        continue
    fi
    
    if [ -z "$ECR_REPOSITORIES" ] || [ "$ECR_REPOSITORIES" == "None" ]; then
        echo -e "✅ Sin repositorios ECR"
        COMPLIANT_ACCOUNTS=$((COMPLIANT_ACCOUNTS + 1))
    else
        PROFILE_REPOS=0
        PROFILE_IMMUTABLE=0
        
        while IFS=$'\t' read -r repo_name tag_mutability; do
            if [ -n "$repo_name" ] && [ "$repo_name" != "None" ]; then
                PROFILE_REPOS=$((PROFILE_REPOS + 1))
                TOTAL_REPOSITORIES=$((TOTAL_REPOSITORIES + 1))
                
                if [ "$tag_mutability" == "IMMUTABLE" ]; then
                    echo -e "  ✅ ${GREEN}$repo_name${NC} - IMMUTABLE"
                    PROFILE_IMMUTABLE=$((PROFILE_IMMUTABLE + 1))
                    IMMUTABLE_REPOSITORIES=$((IMMUTABLE_REPOSITORIES + 1))
                else
                    echo -e "  ❌ ${RED}$repo_name${NC} - MUTABLE"
                fi
            fi
        done <<< "$ECR_REPOSITORIES"
        
        if [ $PROFILE_REPOS -eq $PROFILE_IMMUTABLE ]; then
            echo -e "🎉 Estado: ${GREEN}COMPLIANT${NC} ($PROFILE_IMMUTABLE/$PROFILE_REPOS)"
            COMPLIANT_ACCOUNTS=$((COMPLIANT_ACCOUNTS + 1))
        else
            echo -e "⚠️ Estado: ${YELLOW}NO COMPLIANT${NC} ($PROFILE_IMMUTABLE/$PROFILE_REPOS)"
        fi
    fi
    
    echo ""
done

# Resumen general
echo -e "${PURPLE}=== RESUMEN GENERAL ECR TAG IMMUTABILITY ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "📊 Total cuentas verificadas: ${GREEN}$TOTAL_ACCOUNTS${NC}"
echo -e "✅ Cuentas compliant: ${GREEN}$COMPLIANT_ACCOUNTS${NC}"
echo -e "📦 Total repositorios: ${GREEN}$TOTAL_REPOSITORIES${NC}"
echo -e "🔒 Repositorios inmutables: ${GREEN}$IMMUTABLE_REPOSITORIES${NC}"

if [ $TOTAL_ACCOUNTS -gt 0 ]; then
    COMPLIANCE_PERCENT=$((COMPLIANT_ACCOUNTS * 100 / TOTAL_ACCOUNTS))
    echo -e "📈 Cumplimiento general: ${GREEN}$COMPLIANCE_PERCENT%${NC}"
fi

if [ $TOTAL_REPOSITORIES -gt 0 ]; then
    IMMUTABILITY_PERCENT=$((IMMUTABLE_REPOSITORIES * 100 / TOTAL_REPOSITORIES))
    echo -e "📈 Inmutabilidad general: ${GREEN}$IMMUTABILITY_PERCENT%${NC}"
fi

echo ""

# Estado final
if [ $COMPLIANT_ACCOUNTS -eq $TOTAL_ACCOUNTS ]; then
    echo -e "${GREEN}🎉 ESTADO GENERAL: COMPLETAMENTE SEGURO${NC}"
    echo -e "${BLUE}💡 Todas las cuentas tienen ECR tag immutability${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO GENERAL: REQUIERE REVISIÓN${NC}"
    echo -e "${YELLOW}💡 Algunas cuentas necesitan configuración${NC}"
fi

echo ""
echo -e "📋 Para verificación detallada: ${BLUE}./verify-ecr-tag-immutability.sh [perfil]${NC}"
echo -e "🔧 Para configuración: ${BLUE}./enable-ecr-tag-immutability.sh [perfil]${NC}"