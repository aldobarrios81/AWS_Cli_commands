#!/bin/bash
# verify-ecr-resource-policies.sh
# Verificar políticas de acceso (Resource Policies) en repositorios ECR
# Validar que todos los repositorios tengan políticas restrictivas configuradas

if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia"
    exit 1
fi

# Configuración del perfil
PROFILE="$1"
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
echo -e "${BLUE}🔒 VERIFICACIÓN ECR RESOURCE POLICIES${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo ""

# Verificar credenciales
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Credenciales no válidas para perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo ""

# Variables de conteo
TOTAL_REPOSITORIES=0
REPOSITORIES_WITH_POLICIES=0
REPOSITORIES_WITHOUT_POLICIES=0
REPOSITORIES_WITH_RESTRICTIVE_POLICIES=0
REPOSITORIES_WITH_OPEN_POLICIES=0

# Función para analizar política JSON
analyze_policy() {
    local policy_text="$1"
    local repo_name="$2"
    
    # Verificar si la política permite acceso público
    if echo "$policy_text" | grep -q '"Principal": "\*"'; then
        echo -e "   ❌ RIESGO ALTO: ${RED}Política permite acceso público${NC}"
        return 3  # Política pública
    fi
    
    # Verificar si permite todos los principals AWS
    if echo "$policy_text" | grep -q '"Principal": {"AWS": "\*"}'; then
        echo -e "   ❌ RIESGO ALTO: ${RED}Política permite cualquier cuenta AWS${NC}"
        return 3  # Política muy abierta
    fi
    
    # Verificar si tiene principals específicos
    if echo "$policy_text" | grep -q '"Principal"'; then
        # Contar principals específicos
        principal_count=$(echo "$policy_text" | grep -o '"arn:aws:iam::[0-9]*:' | wc -l)
        
        if [ "$principal_count" -gt 0 ]; then
            echo -e "   ✅ Política restrictiva: ${GREEN}$principal_count cuenta(s) específica(s)${NC}"
            
            # Mostrar las cuentas autorizadas
            echo -e "   📋 Cuentas autorizadas:"
            echo "$policy_text" | grep -o '"arn:aws:iam::[0-9]*:root"' | sed 's/"arn:aws:iam::\([0-9]*\):root"/   - \1/' | head -5
            
            # Verificar si incluye la cuenta actual
            if echo "$policy_text" | grep -q "arn:aws:iam::$ACCOUNT_ID:"; then
                echo -e "   ✅ Incluye cuenta actual: ${GREEN}$ACCOUNT_ID${NC}"
            else
                echo -e "   ⚠️ No incluye cuenta actual: ${YELLOW}$ACCOUNT_ID${NC}"
            fi
            
            return 1  # Política restrictiva
        fi
    fi
    
    # Verificar si tiene Effect Deny (más restrictivo)
    if echo "$policy_text" | grep -q '"Effect": "Deny"'; then
        echo -e "   ✅ Política con denegaciones: ${GREEN}Extra restrictiva${NC}"
        return 1  # Política restrictiva
    fi
    
    echo -e "   ⚠️ Política no estándar: ${YELLOW}Revisar manualmente${NC}"
    return 2  # Política no estándar
}

# Verificar disponibilidad de ECR
echo -e "${PURPLE}🔍 Verificando disponibilidad de ECR...${NC}"
ECR_TEST=$(aws ecr describe-repositories --profile "$PROFILE" --region "$REGION" --max-items 1 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ ECR no disponible en región $REGION${NC}"
    
    # Verificar otras regiones principales
    MAIN_REGIONS=("us-west-2" "eu-west-1" "ap-southeast-1")
    for region in "${MAIN_REGIONS[@]}"; do
        echo -e "   🔍 Verificando región: ${BLUE}$region${NC}"
        TEST_RESULT=$(aws ecr describe-repositories --profile "$PROFILE" --region "$region" --max-items 1 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            echo -e "   ✅ ECR disponible en: ${GREEN}$region${NC}"
            REGION="$region"
            break
        else
            echo -e "   ❌ No disponible en: $region"
        fi
    done
fi

echo ""

# Análisis de repositorios ECR
echo -e "${PURPLE}=== Análisis de Resource Policies ECR ===${NC}"

# Obtener lista completa de repositorios
ECR_REPOSITORIES=$(aws ecr describe-repositories \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'repositories[].[repositoryName,repositoryUri,createdAt]' \
    --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Error al obtener repositorios ECR${NC}"
    exit 1
elif [ -z "$ECR_REPOSITORIES" ] || [ "$ECR_REPOSITORIES" == "None" ]; then
    echo -e "${GREEN}✅ No se encontraron repositorios ECR${NC}"
    TOTAL_REPOSITORIES=0
else
    echo -e "${GREEN}📊 Analizando Resource Policies en repositorios ECR:${NC}"
    echo ""
    
    while IFS=$'\t' read -r repo_name repo_uri created_at; do
        if [ -n "$repo_name" ] && [ "$repo_name" != "None" ]; then
            TOTAL_REPOSITORIES=$((TOTAL_REPOSITORIES + 1))
            
            echo -e "${CYAN}📦 Repositorio: $repo_name${NC}"
            echo -e "   🌐 URI: ${BLUE}$repo_uri${NC}"
            echo -e "   📅 Creado: ${BLUE}$(echo "$created_at" | cut -d'T' -f1)${NC}"
            
            # Verificar política del repositorio
            REPO_POLICY=$(aws ecr get-repository-policy \
                --repository-name "$repo_name" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query 'policyText' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$REPO_POLICY" ] && [ "$REPO_POLICY" != "None" ]; then
                echo -e "   ✅ Resource Policy: ${GREEN}CONFIGURADA${NC}"
                REPOSITORIES_WITH_POLICIES=$((REPOSITORIES_WITH_POLICIES + 1))
                
                # Analizar la política
                analyze_policy "$REPO_POLICY" "$repo_name"
                policy_status=$?
                
                case $policy_status in
                    1)  # Política restrictiva
                        REPOSITORIES_WITH_RESTRICTIVE_POLICIES=$((REPOSITORIES_WITH_RESTRICTIVE_POLICIES + 1))
                        ;;
                    3)  # Política abierta/pública
                        REPOSITORIES_WITH_OPEN_POLICIES=$((REPOSITORIES_WITH_OPEN_POLICIES + 1))
                        ;;
                esac
                
                # Mostrar un extracto de la política (primeras líneas)
                echo -e "   📜 Extracto de política:"
                echo "$REPO_POLICY" | jq '.' 2>/dev/null | head -10 | sed 's/^/      /'
                
                if [ $(echo "$REPO_POLICY" | jq '.' 2>/dev/null | wc -l) -gt 10 ]; then
                    echo -e "      ${BLUE}... (política truncada)${NC}"
                fi
                
            else
                echo -e "   ❌ Resource Policy: ${RED}NO CONFIGURADA${NC}"
                echo -e "   ⚠️ RIESGO: ${YELLOW}Repositorio usa permisos por defecto${NC}"
                echo -e "   💡 Recomendación: ${BLUE}Configurar política restrictiva${NC}"
                REPOSITORIES_WITHOUT_POLICIES=$((REPOSITORIES_WITHOUT_POLICIES + 1))
            fi
            
            # Verificar configuraciones adicionales de seguridad
            echo -e "   🔍 Verificaciones adicionales de seguridad:"
            
            # Tag immutability
            TAG_MUTABILITY=$(aws ecr describe-repositories \
                --repository-names "$repo_name" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query 'repositories[0].imageTagMutability' \
                --output text 2>/dev/null)
            
            if [ "$TAG_MUTABILITY" == "IMMUTABLE" ]; then
                echo -e "      ✅ Tag Immutability: ${GREEN}HABILITADO${NC}"
            else
                echo -e "      ⚠️ Tag Immutability: ${YELLOW}DESHABILITADO${NC}"
            fi
            
            # Scan on push
            SCAN_ON_PUSH=$(aws ecr describe-repositories \
                --repository-names "$repo_name" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query 'repositories[0].imageScanningConfiguration.scanOnPush' \
                --output text 2>/dev/null)
            
            if [ "$SCAN_ON_PUSH" == "True" ]; then
                echo -e "      ✅ Scan on Push: ${GREEN}HABILITADO${NC}"
            else
                echo -e "      ⚠️ Scan on Push: ${YELLOW}DESHABILITADO${NC}"
            fi
            
            # Encriptación
            ENCRYPTION_TYPE=$(aws ecr describe-repositories \
                --repository-names "$repo_name" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query 'repositories[0].encryptionConfiguration.encryptionType' \
                --output text 2>/dev/null)
            
            if [ -n "$ENCRYPTION_TYPE" ] && [ "$ENCRYPTION_TYPE" != "None" ]; then
                echo -e "      ✅ Encriptación: ${GREEN}$ENCRYPTION_TYPE${NC}"
            else
                echo -e "      ℹ️ Encriptación: ${BLUE}AES256 (por defecto)${NC}"
            fi
            
            # Estado general de seguridad del repositorio
            SECURITY_SCORE=0
            
            # Puntuación basada en configuraciones
            if [ -n "$REPO_POLICY" ] && [ "$REPO_POLICY" != "None" ]; then
                if [ $policy_status -eq 1 ]; then
                    SECURITY_SCORE=$((SECURITY_SCORE + 3))  # Política restrictiva
                elif [ $policy_status -eq 2 ]; then
                    SECURITY_SCORE=$((SECURITY_SCORE + 1))  # Política no estándar
                else
                    SECURITY_SCORE=$((SECURITY_SCORE - 2))  # Política abierta
                fi
            else
                SECURITY_SCORE=$((SECURITY_SCORE - 3))  # Sin política
            fi
            
            if [ "$TAG_MUTABILITY" == "IMMUTABLE" ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 1))
            fi
            
            if [ "$SCAN_ON_PUSH" == "True" ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 1))
            fi
            
            # Mostrar puntuación de seguridad
            if [ $SECURITY_SCORE -ge 4 ]; then
                echo -e "   🔐 Puntuación de seguridad: ${GREEN}EXCELENTE ($SECURITY_SCORE/5)${NC}"
            elif [ $SECURITY_SCORE -ge 2 ]; then
                echo -e "   🔐 Puntuación de seguridad: ${YELLOW}BUENA ($SECURITY_SCORE/5)${NC}"
            elif [ $SECURITY_SCORE -ge 0 ]; then
                echo -e "   🔐 Puntuación de seguridad: ${YELLOW}REGULAR ($SECURITY_SCORE/5)${NC}"
            else
                echo -e "   🔐 Puntuación de seguridad: ${RED}REQUIERE ATENCIÓN ($SECURITY_SCORE/5)${NC}"
            fi
            
            echo ""
        fi
    done <<< "$ECR_REPOSITORIES"
fi

echo ""

# Generar reporte de verificación
VERIFICATION_REPORT="ecr-resource-policies-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "region": "$REGION",
  "account_id": "$ACCOUNT_ID",
  "summary": {
    "total_repositories": $TOTAL_REPOSITORIES,
    "repositories_with_policies": $REPOSITORIES_WITH_POLICIES,
    "repositories_without_policies": $REPOSITORIES_WITHOUT_POLICIES,
    "repositories_with_restrictive_policies": $REPOSITORIES_WITH_RESTRICTIVE_POLICIES,
    "repositories_with_open_policies": $REPOSITORIES_WITH_OPEN_POLICIES,
    "policy_compliance": "$(if [ $TOTAL_REPOSITORIES -eq 0 ]; then echo "NO_REPOSITORIES"; elif [ $REPOSITORIES_WITHOUT_POLICIES -eq 0 ] && [ $REPOSITORIES_WITH_OPEN_POLICIES -eq 0 ]; then echo "FULLY_COMPLIANT"; elif [ $REPOSITORIES_WITH_OPEN_POLICIES -gt 0 ]; then echo "HIGH_RISK"; else echo "PARTIAL_COMPLIANCE"; fi)"
  },
  "security_recommendations": [
    "Configurar Resource Policies restrictivas en todos los repositorios",
    "Limitar acceso solo a cuentas específicas autorizadas",
    "Evitar políticas que permitan acceso público (*)", 
    "Implementar principio de menor privilegio",
    "Revisar y auditar políticas regularmente",
    "Habilitar logging de acceso para monitoreo",
    "Usar roles específicos en lugar de permisos amplios"
  ],
  "remediation_commands": [
    "./limit-all-ecr-repos.sh $PROFILE",
    "aws ecr set-repository-policy --repository-name REPO_NAME --policy-text file://restrictive-policy.json --profile $PROFILE"
  ]
}
EOF

echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Comandos de remediación
if [ $REPOSITORIES_WITHOUT_POLICIES -gt 0 ] || [ $REPOSITORIES_WITH_OPEN_POLICIES -gt 0 ]; then
    echo ""
    echo -e "${PURPLE}=== Comandos de Remediación ===${NC}"
    
    if [ $REPOSITORIES_WITHOUT_POLICIES -gt 0 ]; then
        echo -e "${CYAN}🔧 Para configurar políticas restrictivas en todos los repos:${NC}"
        echo -e "${BLUE}./limit-all-ecr-repos.sh $PROFILE${NC}"
    fi
    
    if [ $REPOSITORIES_WITH_OPEN_POLICIES -gt 0 ]; then
        echo -e "${CYAN}🚨 URGENTE - Repositorios con políticas públicas encontrados${NC}"
        echo -e "${RED}Revisar y restringir inmediatamente${NC}"
    fi
    
    echo -e "${CYAN}🔧 Comando manual para repositorio específico:${NC}"
    echo -e "${BLUE}aws ecr set-repository-policy --repository-name REPO_NAME --policy-text '{\"Version\":\"2008-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::ACCOUNT_ID:root\"},\"Action\":[\"ecr:GetDownloadUrlForLayer\",\"ecr:BatchGetImage\",\"ecr:BatchCheckLayerAvailability\"]}]}' --profile $PROFILE${NC}"
fi

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN ECR RESOURCE POLICIES ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account: ${GREEN}$ACCOUNT_ID${NC} | Región: ${GREEN}$REGION${NC}"
echo -e "📦 Total repositorios: ${GREEN}$TOTAL_REPOSITORIES${NC}"

if [ $TOTAL_REPOSITORIES -gt 0 ]; then
    echo -e "✅ Con Resource Policy: ${GREEN}$REPOSITORIES_WITH_POLICIES${NC}"
    if [ $REPOSITORIES_WITHOUT_POLICIES -gt 0 ]; then
        echo -e "❌ Sin Resource Policy: ${RED}$REPOSITORIES_WITHOUT_POLICIES${NC}"
    fi
    if [ $REPOSITORIES_WITH_RESTRICTIVE_POLICIES -gt 0 ]; then
        echo -e "🔒 Políticas restrictivas: ${GREEN}$REPOSITORIES_WITH_RESTRICTIVE_POLICIES${NC}"
    fi
    if [ $REPOSITORIES_WITH_OPEN_POLICIES -gt 0 ]; then
        echo -e "🚨 Políticas abiertas/públicas: ${RED}$REPOSITORIES_WITH_OPEN_POLICIES${NC}"
    fi
    
    # Calcular porcentajes de cumplimiento
    if [ $TOTAL_REPOSITORIES -gt 0 ]; then
        POLICY_COVERAGE=$((REPOSITORIES_WITH_POLICIES * 100 / TOTAL_REPOSITORIES))
        RESTRICTIVE_PERCENT=$((REPOSITORIES_WITH_RESTRICTIVE_POLICIES * 100 / TOTAL_REPOSITORIES))
        
        echo -e "📈 Cobertura de políticas: ${GREEN}$POLICY_COVERAGE%${NC}"
        echo -e "📈 Políticas restrictivas: ${GREEN}$RESTRICTIVE_PERCENT%${NC}"
    fi
fi

echo ""

# Estado final y recomendaciones
if [ $TOTAL_REPOSITORIES -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN REPOSITORIOS ECR${NC}"
    echo -e "${BLUE}💡 No hay repositorios para verificar${NC}"
elif [ $REPOSITORIES_WITH_OPEN_POLICIES -gt 0 ]; then
    echo -e "${RED}🚨 ESTADO: RIESGO ALTO - POLÍTICAS PÚBLICAS DETECTADAS${NC}"
    echo -e "${YELLOW}💡 ACCIÓN INMEDIATA: Restringir acceso público${NC}"
elif [ $REPOSITORIES_WITHOUT_POLICIES -gt 0 ]; then
    echo -e "${RED}⚠️ ESTADO: RIESGO MEDIO - REPOSITORIOS SIN POLÍTICAS${NC}"
    echo -e "${YELLOW}💡 EJECUTAR: ./limit-all-ecr-repos.sh $PROFILE${NC}"
elif [ $REPOSITORIES_WITH_RESTRICTIVE_POLICIES -eq $TOTAL_REPOSITORIES ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE SEGURO${NC}"
    echo -e "${BLUE}💡 Todos los repositorios tienen políticas restrictivas${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: PARCIALMENTE SEGURO${NC}"
    echo -e "${BLUE}💡 Revisar políticas no estándar manualmente${NC}"
fi

echo -e "📋 Reporte detallado: ${GREEN}$VERIFICATION_REPORT${NC}"
echo ""