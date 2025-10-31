#!/bin/bash
# lambda-dlq-summary.sh
# Verificar estado de Dead Letter Queues en funciones Lambda para todos los perfiles

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

PROFILES=("ancla" "azbeacons" "azcenit")
REGIONS=("us-east-1" "us-west-2" "eu-west-1")

echo "=================================================================="
echo -e "${BLUE}🔍 RESUMEN LAMBDA DLQ - TODOS LOS PERFILES${NC}"
echo "=================================================================="
echo -e "Fecha: ${GREEN}$(date)${NC}"
echo ""

# Variables de resumen
TOTAL_ACCOUNTS=0
ACCOUNTS_WITH_LAMBDA=0
TOTAL_FUNCTIONS=0
FUNCTIONS_WITH_DLQ=0
FUNCTIONS_WITHOUT_DLQ=0
FUNCTIONAL_FUNCTIONS=0
BROKEN_FUNCTIONS=0

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
    
    PROFILE_HAS_LAMBDA=false
    PROFILE_FUNCTIONS=0
    PROFILE_WITH_DLQ=0
    PROFILE_WITHOUT_DLQ=0
    PROFILE_FUNCTIONAL=0
    PROFILE_BROKEN=0
    
    # Verificar cada región
    for region in "${REGIONS[@]}"; do
        # Obtener funciones Lambda
        LAMBDA_FUNCTIONS=$(aws lambda list-functions \
            --profile "$profile" \
            --region "$region" \
            --query 'Functions[].[FunctionName,State,DeadLetterConfig.TargetArn]' \
            --output text 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            continue
        fi
        
        if [ -z "$LAMBDA_FUNCTIONS" ] || [ "$LAMBDA_FUNCTIONS" == "None" ]; then
            continue
        fi
        
        PROFILE_HAS_LAMBDA=true
        
        echo -e "🌍 Región: ${CYAN}$region${NC}"
        
        while IFS=$'\t' read -r function_name state dlq_arn; do
            if [ -n "$function_name" ] && [ "$function_name" != "None" ]; then
                PROFILE_FUNCTIONS=$((PROFILE_FUNCTIONS + 1))
                
                # Verificar estado de la función
                case $state in
                    "Active")
                        echo -e "  ✅ ${GREEN}$function_name${NC}"
                        PROFILE_FUNCTIONAL=$((PROFILE_FUNCTIONAL + 1))
                        
                        # Verificar DLQ
                        if [ -n "$dlq_arn" ] && [ "$dlq_arn" != "None" ]; then
                            echo -e "     🎯 DLQ: ${GREEN}Configurada${NC}"
                            PROFILE_WITH_DLQ=$((PROFILE_WITH_DLQ + 1))
                        else
                            echo -e "     ⚠️ DLQ: ${YELLOW}No configurada${NC}"
                            PROFILE_WITHOUT_DLQ=$((PROFILE_WITHOUT_DLQ + 1))
                        fi
                        ;;
                    "Failed"|"Pending")
                        echo -e "  ❌ ${RED}$function_name${NC} (Estado: $state)"
                        PROFILE_BROKEN=$((PROFILE_BROKEN + 1))
                        ;;
                    *)
                        echo -e "  ⚠️ ${YELLOW}$function_name${NC} (Estado: $state)"
                        PROFILE_FUNCTIONAL=$((PROFILE_FUNCTIONAL + 1))
                        
                        if [ -n "$dlq_arn" ] && [ "$dlq_arn" != "None" ]; then
                            PROFILE_WITH_DLQ=$((PROFILE_WITH_DLQ + 1))
                        else
                            PROFILE_WITHOUT_DLQ=$((PROFILE_WITHOUT_DLQ + 1))
                        fi
                        ;;
                esac
            fi
        done <<< "$LAMBDA_FUNCTIONS"
    done
    
    if [ "$PROFILE_HAS_LAMBDA" = true ]; then
        ACCOUNTS_WITH_LAMBDA=$((ACCOUNTS_WITH_LAMBDA + 1))
        TOTAL_FUNCTIONS=$((TOTAL_FUNCTIONS + PROFILE_FUNCTIONS))
        FUNCTIONS_WITH_DLQ=$((FUNCTIONS_WITH_DLQ + PROFILE_WITH_DLQ))
        FUNCTIONS_WITHOUT_DLQ=$((FUNCTIONS_WITHOUT_DLQ + PROFILE_WITHOUT_DLQ))
        FUNCTIONAL_FUNCTIONS=$((FUNCTIONAL_FUNCTIONS + PROFILE_FUNCTIONAL))
        BROKEN_FUNCTIONS=$((BROKEN_FUNCTIONS + PROFILE_BROKEN))
        
        echo -e "📊 Resumen perfil:"
        echo -e "   Total funciones: ${BLUE}$PROFILE_FUNCTIONS${NC}"
        echo -e "   Funcionales: ${GREEN}$PROFILE_FUNCTIONAL${NC}"
        if [ $PROFILE_BROKEN -gt 0 ]; then
            echo -e "   Con problemas: ${RED}$PROFILE_BROKEN${NC}"
        fi
        echo -e "   Con DLQ: ${GREEN}$PROFILE_WITH_DLQ${NC}"
        if [ $PROFILE_WITHOUT_DLQ -gt 0 ]; then
            echo -e "   Sin DLQ: ${YELLOW}$PROFILE_WITHOUT_DLQ${NC}"
        fi
        
        # Calcular cumplimiento del perfil
        if [ $PROFILE_FUNCTIONAL -gt 0 ]; then
            PROFILE_COMPLIANCE=$((PROFILE_WITH_DLQ * 100 / PROFILE_FUNCTIONAL))
            echo -e "   Cumplimiento DLQ: ${GREEN}$PROFILE_COMPLIANCE%${NC}"
        fi
    else
        echo -e "✅ Sin funciones Lambda"
    fi
    
    echo ""
done

# Resumen general
echo -e "${PURPLE}=== RESUMEN GENERAL LAMBDA DLQ ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "📊 Total cuentas verificadas: ${GREEN}$TOTAL_ACCOUNTS${NC}"
echo -e "⚡ Cuentas con Lambda: ${GREEN}$ACCOUNTS_WITH_LAMBDA${NC}"
echo -e "📦 Total funciones Lambda: ${GREEN}$TOTAL_FUNCTIONS${NC}"

if [ $TOTAL_FUNCTIONS -gt 0 ]; then
    echo -e "✅ Funciones funcionales: ${GREEN}$FUNCTIONAL_FUNCTIONS${NC}"
    if [ $BROKEN_FUNCTIONS -gt 0 ]; then
        echo -e "❌ Funciones con problemas: ${RED}$BROKEN_FUNCTIONS${NC}"
    fi
    echo -e "🎯 Con DLQ configurada: ${GREEN}$FUNCTIONS_WITH_DLQ${NC}"
    if [ $FUNCTIONS_WITHOUT_DLQ -gt 0 ]; then
        echo -e "⚠️ Sin DLQ: ${YELLOW}$FUNCTIONS_WITHOUT_DLQ${NC}"
    fi
    
    # Calcular porcentajes
    if [ $FUNCTIONAL_FUNCTIONS -gt 0 ]; then
        DLQ_COMPLIANCE=$((FUNCTIONS_WITH_DLQ * 100 / FUNCTIONAL_FUNCTIONS))
        echo -e "📈 Cumplimiento DLQ (funcionales): ${GREEN}$DLQ_COMPLIANCE%${NC}"
    fi
    
    if [ $TOTAL_FUNCTIONS -gt 0 ]; then
        FUNCTIONAL_PERCENT=$((FUNCTIONAL_FUNCTIONS * 100 / TOTAL_FUNCTIONS))
        echo -e "📈 Funciones operativas: ${GREEN}$FUNCTIONAL_PERCENT%${NC}"
    fi
fi

echo ""

# Recomendaciones
echo -e "${PURPLE}=== RECOMENDACIONES ===${NC}"

if [ $FUNCTIONS_WITHOUT_DLQ -gt 0 ]; then
    echo -e "🔧 Configurar DLQ para funciones sin configurar:"
    echo -e "   ${BLUE}./configure-lambda-dead-letter-queues.sh [perfil]${NC}"
fi

if [ $BROKEN_FUNCTIONS -gt 0 ]; then
    echo -e "🛠️ Revisar y reparar funciones con problemas:"
    echo -e "   ${BLUE}aws lambda get-function --function-name [NOMBRE] --profile [PERFIL]${NC}"
fi

if [ $TOTAL_FUNCTIONS -eq 0 ]; then
    echo -e "ℹ️ No hay funciones Lambda para configurar DLQ"
else
    echo -e "📋 Verificar configuraciones específicas:"
    echo -e "   ${BLUE}./verify-lambda-dead-letter-queues.sh [perfil]${NC}"
fi

echo ""

# Estado final
if [ $TOTAL_FUNCTIONS -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN FUNCIONES LAMBDA${NC}"
    echo -e "${BLUE}💡 No hay funciones para configurar DLQ${NC}"
elif [ $FUNCTIONS_WITHOUT_DLQ -eq 0 ] && [ $BROKEN_FUNCTIONS -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE CONFIGURADO${NC}"
    echo -e "${BLUE}💡 Todas las funciones operativas tienen DLQ${NC}"
elif [ $BROKEN_FUNCTIONS -gt 0 ]; then
    echo -e "${RED}⚠️ ESTADO: REQUIERE REPARACIONES${NC}"
    echo -e "${YELLOW}💡 Algunas funciones tienen problemas de configuración${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: REQUIERE CONFIGURACIÓN DLQ${NC}"
    echo -e "${YELLOW}💡 Configurar DLQ para funciones sin configurar${NC}"
fi