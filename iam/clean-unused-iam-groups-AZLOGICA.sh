#!/bin/bash
# clean-unused-iam-groups-AZLOGICA.sh
# SOLO IDENTIFICA grupos IAM sin usuarios ni actividad para perfil AZLOGICA

PROFILE="AZLOGICA"
REGION="us-east-1"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔍 IDENTIFICACIÓN DE GRUPOS IAM SIN USO${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo -e "Modo: ${YELLOW}SOLO ANÁLISIS (NO ELIMINA)${NC}"
echo ""

# Verificar credenciales
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Credenciales no válidas para perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo ""

# Arrays para almacenar resultados
UNUSED_GROUPS=()
GROUPS_WITH_USERS=()
GROUPS_WITH_POLICIES=()
PROTECTED_GROUPS=()

echo -e "${PURPLE}🔍 Analizando grupos IAM...${NC}"
echo ""

# Obtener lista de todos los grupos
GROUPS=$(aws iam list-groups --profile "$PROFILE" --query 'Groups[*].GroupName' --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error al obtener lista de grupos IAM${NC}"
    exit 1
fi

for GROUP_NAME in $GROUPS; do
    # Saltear si el nombre está vacío
    if [ -z "$GROUP_NAME" ]; then
        continue
    fi
    
    echo -e "${CYAN}📋 Analizando grupo: ${GREEN}$GROUP_NAME${NC}"
    
    # Verificar si es un grupo protegido del sistema
    if [[ "$GROUP_NAME" =~ ^(aws-|AWS|Admin|Administrator|Root|Security|Compliance) ]]; then
        echo -e "   ${YELLOW}🛡️ Grupo protegido del sistema - OMITIDO${NC}"
        PROTECTED_GROUPS+=("$GROUP_NAME")
        continue
    fi
    
    # Obtener usuarios del grupo
    USER_COUNT=$(aws iam get-group \
        --group-name "$GROUP_NAME" \
        --profile "$PROFILE" \
        --query 'Users | length(@)' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "   ${RED}❌ Error al obtener información del grupo${NC}"
        continue
    fi
    
    # Validar que USER_COUNT sea un número
    if ! [[ "$USER_COUNT" =~ ^[0-9]+$ ]]; then
        echo -e "   ${RED}❌ Error: USER_COUNT no es un número válido: '$USER_COUNT'${NC}"
        continue
    fi
    
    if [ "$USER_COUNT" -gt 0 ]; then
        echo -e "   👥 ${GREEN}$USER_COUNT usuario(s)${NC} - EN USO"
        GROUPS_WITH_USERS+=("$GROUP_NAME")
        continue
    fi
    
    # Verificar políticas inline
    INLINE_POLICIES=$(aws iam list-group-policies \
        --group-name "$GROUP_NAME" \
        --profile "$PROFILE" \
        --query 'PolicyNames | length(@)' \
        --output text 2>/dev/null)
    
    # Verificar políticas administradas
    MANAGED_POLICIES=$(aws iam list-attached-group-policies \
        --group-name "$GROUP_NAME" \
        --profile "$PROFILE" \
        --query 'AttachedPolicies | length(@)' \
        --output text 2>/dev/null)
    
    if [ "$INLINE_POLICIES" -gt 0 ] || [ "$MANAGED_POLICIES" -gt 0 ]; then
        echo -e "   📜 ${YELLOW}Tiene políticas adjuntas (inline: $INLINE_POLICIES, managed: $MANAGED_POLICIES)${NC} - MANTENER"
        GROUPS_WITH_POLICIES+=("$GROUP_NAME")
        continue
    fi
    
    # Grupo sin usuarios ni políticas
    echo -e "   ${RED}🗑️ Sin usuarios ni políticas${NC} - CANDIDATO PARA ELIMINACIÓN"
    UNUSED_GROUPS+=("$GROUP_NAME")
done

# Mostrar resumen
echo ""
echo "=================================================================="
echo -e "${BLUE}📊 RESUMEN DEL ANÁLISIS${NC}"
echo "=================================================================="
echo -e "${GREEN}✅ Grupos con usuarios: ${#GROUPS_WITH_USERS[@]}${NC}"
echo -e "${YELLOW}📜 Grupos con políticas (sin usuarios): ${#GROUPS_WITH_POLICIES[@]}${NC}"
echo -e "${PURPLE}🛡️ Grupos protegidos: ${#PROTECTED_GROUPS[@]}${NC}"
echo -e "${RED}🗑️ Grupos sin uso (candidatos): ${#UNUSED_GROUPS[@]}${NC}"
echo ""

# Detallar grupos sin uso
if [ ${#UNUSED_GROUPS[@]} -gt 0 ]; then
    echo -e "${RED}🗑️ GRUPOS CANDIDATOS PARA ELIMINACIÓN:${NC}"
    echo "================================================"
    for group_name in "${UNUSED_GROUPS[@]}"; do
        echo -e "  • ${RED}$group_name${NC}"
    done
    echo ""
    echo -e "${YELLOW}📝 NOTA: Estos grupos NO fueron eliminados (solo identificados)${NC}"
else
    echo -e "${GREEN}🎉 ¡Excelente! No se encontraron grupos sin uso${NC}"
fi

# Mostrar grupos con políticas pero sin usuarios para revisión
if [ ${#GROUPS_WITH_POLICIES[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}📜 GRUPOS CON POLÍTICAS PERO SIN USUARIOS (revisar manualmente):${NC}"
    echo "================================================================"
    for group_name in "${GROUPS_WITH_POLICIES[@]}"; do
        echo -e "  • ${YELLOW}$group_name${NC}"
    done
fi

echo ""
echo "=================================================================="
echo -e "${GREEN}🎯 ANÁLISIS COMPLETADO${NC}"
echo "=================================================================="
echo -e "${BLUE}💡 Los grupos identificados como 'sin uso' pueden eliminarse si no se necesitan${NC}"
echo ""
