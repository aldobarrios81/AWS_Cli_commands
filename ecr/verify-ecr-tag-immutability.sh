#!/bin/bash
# verify-ecr-tag-immutability.sh
# Verificar configuraciones de inmutabilidad de tags en repositorios ECR
# Validar que todos los repositorios tengan tags inmutables habilitados

if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit"
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
echo -e "${BLUE}🔍 VERIFICACIÓN ECR TAG IMMUTABILITY${NC}"
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
IMMUTABLE_REPOSITORIES=0
MUTABLE_REPOSITORIES=0
REPOSITORIES_WITH_SCANNING=0
REPOSITORIES_WITH_ENCRYPTION=0

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
echo -e "${PURPLE}=== Análisis de Repositorios ECR ===${NC}"

# Obtener lista completa de repositorios
ECR_REPOSITORIES=$(aws ecr describe-repositories \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'repositories[].[repositoryName,repositoryUri,imageTagMutability,createdAt,imageScanningConfiguration.scanOnPush,encryptionConfiguration.encryptionType]' \
    --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Error al obtener repositorios ECR${NC}"
elif [ -z "$ECR_REPOSITORIES" ] || [ "$ECR_REPOSITORIES" == "None" ]; then
    echo -e "${GREEN}✅ No se encontraron repositorios ECR${NC}"
    TOTAL_REPOSITORIES=0
else
    echo -e "${GREEN}📊 Repositorios ECR encontrados:${NC}"
    
    while IFS=$'\t' read -r repo_name repo_uri tag_mutability created_at scan_on_push encryption_type; do
        if [ -n "$repo_name" ] && [ "$repo_name" != "None" ]; then
            TOTAL_REPOSITORIES=$((TOTAL_REPOSITORIES + 1))
            
            echo -e "${CYAN}📦 Repositorio: $repo_name${NC}"
            echo -e "   🌐 URI: ${BLUE}$repo_uri${NC}"
            echo -e "   📅 Creado: ${BLUE}$(echo "$created_at" | cut -d'T' -f1)${NC}"
            
            # Verificar inmutabilidad de tags
            if [ "$tag_mutability" == "IMMUTABLE" ]; then
                echo -e "   ✅ Tag Immutability: ${GREEN}HABILITADO${NC}"
                IMMUTABLE_REPOSITORIES=$((IMMUTABLE_REPOSITORIES + 1))
            else
                echo -e "   ❌ Tag Immutability: ${RED}DESHABILITADO${NC}"
                MUTABLE_REPOSITORIES=$((MUTABLE_REPOSITORIES + 1))
            fi
            
            # Verificar scanning automático
            if [ "$scan_on_push" == "True" ]; then
                echo -e "   ✅ Scan on Push: ${GREEN}HABILITADO${NC}"
                REPOSITORIES_WITH_SCANNING=$((REPOSITORIES_WITH_SCANNING + 1))
            else
                echo -e "   ⚠️ Scan on Push: ${YELLOW}DESHABILITADO${NC}"
            fi
            
            # Verificar encriptación
            if [ -n "$encryption_type" ] && [ "$encryption_type" != "None" ]; then
                echo -e "   ✅ Encriptación: ${GREEN}$encryption_type${NC}"
                REPOSITORIES_WITH_ENCRYPTION=$((REPOSITORIES_WITH_ENCRYPTION + 1))
            else
                echo -e "   ⚠️ Encriptación: ${YELLOW}Por defecto (AES256)${NC}"
            fi
            
            # Obtener estadísticas de imágenes
            IMAGE_STATS=$(aws ecr describe-image-scan-findings \
                --repository-name "$repo_name" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query '[imageScanFindingsSummary.findingCounts,imageId]' \
                --output text 2>/dev/null)
            
            # Contar imágenes totales
            TOTAL_IMAGES=$(aws ecr list-images \
                --repository-name "$repo_name" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query 'length(imageIds)' \
                --output text 2>/dev/null)
            
            if [ -n "$TOTAL_IMAGES" ] && [ "$TOTAL_IMAGES" -gt 0 ]; then
                echo -e "   📊 Total imágenes: ${BLUE}$TOTAL_IMAGES${NC}"
                
                # Contar imágenes con tags vs sin tags
                TAGGED_IMAGES=$(aws ecr list-images \
                    --repository-name "$repo_name" \
                    --filter tagStatus=TAGGED \
                    --profile "$PROFILE" \
                    --region "$REGION" \
                    --query 'length(imageIds)' \
                    --output text 2>/dev/null)
                
                UNTAGGED_IMAGES=$(aws ecr list-images \
                    --repository-name "$repo_name" \
                    --filter tagStatus=UNTAGGED \
                    --profile "$PROFILE" \
                    --region "$REGION" \
                    --query 'length(imageIds)' \
                    --output text 2>/dev/null)
                
                if [ -n "$TAGGED_IMAGES" ]; then
                    echo -e "   🏷️ Imágenes tagged: ${BLUE}$TAGGED_IMAGES${NC}"
                fi
                
                if [ -n "$UNTAGGED_IMAGES" ] && [ "$UNTAGGED_IMAGES" -gt 0 ]; then
                    echo -e "   📄 Imágenes untagged: ${YELLOW}$UNTAGGED_IMAGES${NC}"
                fi
                
                # Verificar si hay tags duplicados (solo posible si immutability está deshabilitada)
                if [ "$tag_mutability" != "IMMUTABLE" ] && [ -n "$TAGGED_IMAGES" ] && [ "$TAGGED_IMAGES" -gt 0 ]; then
                    echo -e "   ⚠️ Riesgo: ${YELLOW}Posible sobrescritura de tags${NC}"
                fi
            else
                echo -e "   📊 Imágenes: ${BLUE}Repositorio vacío${NC}"
            fi
            
            # Verificar política de lifecycle
            LIFECYCLE_POLICY=$(aws ecr get-lifecycle-policy \
                --repository-name "$repo_name" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query 'lifecyclePolicyText' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$LIFECYCLE_POLICY" ] && [ "$LIFECYCLE_POLICY" != "None" ]; then
                echo -e "   ✅ Lifecycle Policy: ${GREEN}Configurada${NC}"
            else
                echo -e "   ⚠️ Lifecycle Policy: ${YELLOW}No configurada${NC}"
            fi
            
            # Verificar permisos del repositorio
            REPO_POLICY=$(aws ecr get-repository-policy \
                --repository-name "$repo_name" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query 'policyText' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$REPO_POLICY" ] && [ "$REPO_POLICY" != "None" ]; then
                echo -e "   ✅ Repository Policy: ${GREEN}Configurada${NC}"
            else
                echo -e "   ℹ️ Repository Policy: ${BLUE}Por defecto${NC}"
            fi
            
            # Estado general de seguridad del repositorio
            SECURITY_ISSUES=0
            
            if [ "$tag_mutability" != "IMMUTABLE" ]; then
                SECURITY_ISSUES=$((SECURITY_ISSUES + 1))
            fi
            
            if [ "$scan_on_push" != "True" ]; then
                SECURITY_ISSUES=$((SECURITY_ISSUES + 1))
            fi
            
            if [ $SECURITY_ISSUES -eq 0 ]; then
                echo -e "   🔐 Estado de seguridad: ${GREEN}COMPLETO${NC}"
            elif [ $SECURITY_ISSUES -eq 1 ]; then
                echo -e "   🔐 Estado de seguridad: ${YELLOW}PARCIAL${NC}"
            else
                echo -e "   🔐 Estado de seguridad: ${RED}REQUIERE ATENCIÓN${NC}"
            fi
            
            echo ""
        fi
    done <<< "$ECR_REPOSITORIES"
fi

# Verificar configuraciones a nivel de registry
echo -e "${PURPLE}=== Configuraciones de Registry ===${NC}"

# Verificar configuración de scanning a nivel de registry
REGISTRY_SCANNING=$(aws ecr get-registry-scanning-configuration \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'scanningConfiguration.scanType' \
    --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$REGISTRY_SCANNING" ]; then
    echo -e "✅ Registry Scanning: ${GREEN}$REGISTRY_SCANNING${NC}"
else
    echo -e "ℹ️ Registry Scanning: ${BLUE}Configuración estándar${NC}"
fi

# Verificar configuración de replicación
REPLICATION_CONFIG=$(aws ecr describe-registry \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'replicationConfiguration.rules' \
    --output text 2>/dev/null)

if [ -n "$REPLICATION_CONFIG" ] && [ "$REPLICATION_CONFIG" != "None" ] && [ "$REPLICATION_CONFIG" != "[]" ]; then
    echo -e "✅ Replication: ${GREEN}Configurada${NC}"
else
    echo -e "ℹ️ Replication: ${BLUE}No configurada${NC}"
fi

echo ""

# Generar reporte de verificación
VERIFICATION_REPORT="ecr-immutability-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "region": "$REGION",
  "account_id": "$ACCOUNT_ID",
  "summary": {
    "total_repositories": $TOTAL_REPOSITORIES,
    "immutable_repositories": $IMMUTABLE_REPOSITORIES,
    "mutable_repositories": $MUTABLE_REPOSITORIES,
    "repositories_with_scanning": $REPOSITORIES_WITH_SCANNING,
    "repositories_with_encryption": $REPOSITORIES_WITH_ENCRYPTION,
    "immutability_compliance": "$(if [ $TOTAL_REPOSITORIES -eq 0 ]; then echo "NO_REPOSITORIES"; elif [ $MUTABLE_REPOSITORIES -eq 0 ]; then echo "FULLY_COMPLIANT"; else echo "NON_COMPLIANT"; fi)"
  },
  "security_recommendations": [
    "Habilitar tag immutability en todos los repositorios",
    "Configurar scan automático on push",
    "Implementar políticas de lifecycle para limpieza",
    "Usar encriptación KMS para repositorios sensibles",
    "Configurar políticas de acceso restrictivas",
    "Monitorear vulnerabilidades regularmente"
  ]
}
EOF

echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Comandos de remediación
if [ $MUTABLE_REPOSITORIES -gt 0 ]; then
    echo -e "${PURPLE}=== Comandos de Remediación ===${NC}"
    echo -e "${CYAN}🔧 Para habilitar inmutabilidad:${NC}"
    echo -e "${BLUE}./enable-ecr-tag-immutability.sh $PROFILE${NC}"
    
    echo -e "${CYAN}🔧 Comando manual para repositorio específico:${NC}"
    echo -e "${BLUE}aws ecr put-image-tag-mutability --repository-name REPO_NAME --image-tag-mutability IMMUTABLE --profile $PROFILE${NC}"
fi

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN ECR TAG IMMUTABILITY ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account: ${GREEN}$ACCOUNT_ID${NC} | Región: ${GREEN}$REGION${NC}"
echo -e "📦 Total repositorios: ${GREEN}$TOTAL_REPOSITORIES${NC}"

if [ $TOTAL_REPOSITORIES -gt 0 ]; then
    echo -e "✅ Repositorios inmutables: ${GREEN}$IMMUTABLE_REPOSITORIES${NC}"
    if [ $MUTABLE_REPOSITORIES -gt 0 ]; then
        echo -e "❌ Repositorios mutables: ${RED}$MUTABLE_REPOSITORIES${NC}"
    fi
    echo -e "🔍 Con scanning: ${GREEN}$REPOSITORIES_WITH_SCANNING${NC}"
    echo -e "🔐 Con encriptación: ${GREEN}$REPOSITORIES_WITH_ENCRYPTION${NC}"
    
    # Calcular porcentaje de cumplimiento
    if [ $TOTAL_REPOSITORIES -gt 0 ]; then
        IMMUTABILITY_PERCENT=$((IMMUTABLE_REPOSITORIES * 100 / TOTAL_REPOSITORIES))
        SCANNING_PERCENT=$((REPOSITORIES_WITH_SCANNING * 100 / TOTAL_REPOSITORIES))
        
        echo -e "📈 Cumplimiento inmutabilidad: ${GREEN}$IMMUTABILITY_PERCENT%${NC}"
        echo -e "📈 Cumplimiento scanning: ${GREEN}$SCANNING_PERCENT%${NC}"
    fi
fi

echo ""

# Estado final
if [ $TOTAL_REPOSITORIES -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN REPOSITORIOS ECR${NC}"
    echo -e "${BLUE}💡 No hay repositorios para verificar${NC}"
elif [ $MUTABLE_REPOSITORIES -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE SEGURO${NC}"
    echo -e "${BLUE}💡 Todos los repositorios tienen tag immutability${NC}"
else
    echo -e "${RED}⚠️ ESTADO: REQUIERE CONFIGURACIÓN${NC}"
    echo -e "${YELLOW}💡 Ejecutar: ./enable-ecr-tag-immutability.sh $PROFILE${NC}"
fi

echo -e "📋 Reporte: ${GREEN}$VERIFICATION_REPORT${NC}"