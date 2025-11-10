#!/bin/bash
# verify-ecr-kms-encryption.sh
# Verificar configuraciones de cifrado KMS en repositorios ECR
# Validar que los repositorios usen cifrado KMS en lugar de AES256 por defecto

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
echo -e "${BLUE}🔍 VERIFICACIÓN ECR KMS ENCRYPTION${NC}"
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
KMS_REPOSITORIES=0
AES256_REPOSITORIES=0
TOTAL_KMS_KEYS=0
REGIONS_WITH_ECR=0

# Verificar regiones con repositorios ECR
REGIONS=("us-east-1" "us-west-2" "eu-west-1" "ap-southeast-1")
ACTIVE_REGIONS=()

echo -e "${PURPLE}🌍 Verificando regiones con repositorios ECR...${NC}"
for region in "${REGIONS[@]}"; do
    ECR_COUNT=$(aws ecr describe-repositories \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(repositories)' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$ECR_COUNT" ] && [ "$ECR_COUNT" -gt 0 ]; then
        echo -e "✅ Región ${GREEN}$region${NC}: $ECR_COUNT repositorios"
        ACTIVE_REGIONS+=("$region")
        REGIONS_WITH_ECR=$((REGIONS_WITH_ECR + 1))
    else
        echo -e "ℹ️ Región ${BLUE}$region${NC}: Sin repositorios ECR"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No se encontraron repositorios ECR en ninguna región${NC}"
    echo -e "${BLUE}💡 No hay repositorios para verificar cifrado${NC}"
    exit 0
fi

echo ""

# Análisis de claves KMS disponibles
echo -e "${PURPLE}=== Análisis de Claves KMS ===${NC}"

for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "🔑 Verificando claves KMS en región: ${CYAN}$CURRENT_REGION${NC}"
    
    # Buscar claves KMS específicas para ECR
    ECR_KMS_ALIASES=$(aws kms list-aliases \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'Aliases[?contains(AliasName, `ecr-encryption`) || contains(AliasName, `ecr`)].[AliasName,TargetKeyId]' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$ECR_KMS_ALIASES" ] && [ "$ECR_KMS_ALIASES" != "None" ]; then
        echo -e "   ✅ Claves KMS para ECR encontradas:"
        
        while IFS=$'\t' read -r alias_name key_id; do
            if [ -n "$alias_name" ] && [ "$alias_name" != "None" ]; then
                TOTAL_KMS_KEYS=$((TOTAL_KMS_KEYS + 1))
                echo -e "      🔐 ${GREEN}$alias_name${NC} → $key_id"
                
                # Verificar estado de la clave
                KEY_STATE=$(aws kms describe-key \
                    --key-id "$key_id" \
                    --profile "$PROFILE" \
                    --region "$CURRENT_REGION" \
                    --query 'KeyMetadata.KeyState' \
                    --output text 2>/dev/null)
                
                if [ "$KEY_STATE" == "Enabled" ]; then
                    echo -e "         ✅ Estado: ${GREEN}Habilitada${NC}"
                else
                    echo -e "         ⚠️ Estado: ${YELLOW}$KEY_STATE${NC}"
                fi
                
                # Verificar uso de la clave
                KEY_USAGE=$(aws kms describe-key \
                    --key-id "$key_id" \
                    --profile "$PROFILE" \
                    --region "$CURRENT_REGION" \
                    --query 'KeyMetadata.KeyUsage' \
                    --output text 2>/dev/null)
                
                echo -e "         🎯 Uso: ${BLUE}$KEY_USAGE${NC}"
            fi
        done <<< "$ECR_KMS_ALIASES"
    else
        echo -e "   ⚠️ No se encontraron claves KMS específicas para ECR"
        
        # Verificar clave por defecto de ECR
        DEFAULT_ECR_KEY=$(aws kms describe-key \
            --key-id "alias/aws/ecr" \
            --profile "$PROFILE" \
            --region "$CURRENT_REGION" \
            --query 'KeyMetadata.KeyId' \
            --output text 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$DEFAULT_ECR_KEY" ]; then
            echo -e "   ✅ Clave por defecto AWS ECR disponible: ${GREEN}alias/aws/ecr${NC}"
        fi
    fi
    
    echo ""
done

# Procesar cada región activa
for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "${PURPLE}=== Análisis repositorios región: $CURRENT_REGION ===${NC}"
    
    # Obtener repositorios ECR con información de cifrado
    ECR_REPOSITORIES=$(aws ecr describe-repositories \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'repositories[].[repositoryName,repositoryUri,encryptionConfiguration.encryptionType,encryptionConfiguration.kmsKey,createdAt,imageTagMutability,imageScanningConfiguration.scanOnPush]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error al obtener repositorios ECR en región $CURRENT_REGION${NC}"
        continue
    fi
    
    echo -e "${GREEN}📦 Repositorios ECR en $CURRENT_REGION:${NC}"
    
    while IFS=$'\t' read -r repo_name repo_uri encryption_type kms_key created_at tag_mutability scan_on_push; do
        if [ -n "$repo_name" ] && [ "$repo_name" != "None" ]; then
            TOTAL_REPOSITORIES=$((TOTAL_REPOSITORIES + 1))
            
            echo -e "${CYAN}📋 Repositorio: $repo_name${NC}"
            echo -e "   🌐 URI: ${BLUE}$repo_uri${NC}"
            echo -e "   📅 Creado: ${BLUE}$(echo "$created_at" | cut -d'T' -f1)${NC}"
            
            # Analizar tipo de cifrado
            if [ "$encryption_type" == "KMS" ]; then
                echo -e "   ✅ Cifrado: ${GREEN}KMS${NC}"
                KMS_REPOSITORIES=$((KMS_REPOSITORIES + 1))
                
                if [ -n "$kms_key" ] && [ "$kms_key" != "None" ]; then
                    echo -e "   🔑 Clave KMS: ${GREEN}$kms_key${NC}"
                    
                    # Verificar si es clave personalizada o AWS managed
                    if [[ "$kms_key" =~ "alias/aws/ecr" ]]; then
                        echo -e "      📋 Tipo: ${BLUE}AWS Managed Key${NC}"
                    elif [[ "$kms_key" =~ "ecr-encryption-key" ]]; then
                        echo -e "      📋 Tipo: ${GREEN}Customer Managed Key (Optimizada)${NC}"
                    else
                        echo -e "      📋 Tipo: ${YELLOW}Customer Managed Key${NC}"
                    fi
                    
                    # Verificar acceso a la clave
                    KEY_ACCESS=$(aws kms describe-key \
                        --key-id "$kms_key" \
                        --profile "$PROFILE" \
                        --region "$CURRENT_REGION" \
                        --query 'KeyMetadata.KeyState' \
                        --output text 2>/dev/null)
                    
                    if [ $? -eq 0 ] && [ "$KEY_ACCESS" == "Enabled" ]; then
                        echo -e "      ✅ Acceso: ${GREEN}Verificado${NC}"
                    else
                        echo -e "      ⚠️ Acceso: ${YELLOW}Limitado o problemático${NC}"
                    fi
                else
                    echo -e "   ⚠️ Clave KMS: ${YELLOW}No especificada${NC}"
                fi
                
            elif [ "$encryption_type" == "AES256" ] || [ -z "$encryption_type" ] || [ "$encryption_type" == "None" ]; then
                echo -e "   ⚠️ Cifrado: ${YELLOW}AES256 (Por defecto)${NC}"
                AES256_REPOSITORIES=$((AES256_REPOSITORIES + 1))
                echo -e "   💡 Recomendación: ${YELLOW}Migrar a KMS para mayor seguridad${NC}"
                
            else
                echo -e "   ❓ Cifrado: ${YELLOW}Desconocido ($encryption_type)${NC}"
            fi
            
            # Análisis de configuración de seguridad completa
            SECURITY_FEATURES=0
            
            # Verificar cifrado KMS
            if [ "$encryption_type" == "KMS" ]; then
                SECURITY_FEATURES=$((SECURITY_FEATURES + 1))
            fi
            
            # Verificar inmutabilidad de tags
            if [ "$tag_mutability" == "IMMUTABLE" ]; then
                echo -e "   ✅ Tag Immutability: ${GREEN}Habilitado${NC}"
                SECURITY_FEATURES=$((SECURITY_FEATURES + 1))
            else
                echo -e "   ⚠️ Tag Immutability: ${YELLOW}Deshabilitado${NC}"
            fi
            
            # Verificar scanning automático
            if [ "$scan_on_push" == "True" ]; then
                echo -e "   ✅ Scan on Push: ${GREEN}Habilitado${NC}"
                SECURITY_FEATURES=$((SECURITY_FEATURES + 1))
            else
                echo -e "   ⚠️ Scan on Push: ${YELLOW}Deshabilitado${NC}"
            fi
            
            # Puntuación de seguridad
            case $SECURITY_FEATURES in
                3)
                    echo -e "   🔐 Puntuación de seguridad: ${GREEN}MÁXIMA (3/3)${NC}"
                    ;;
                2)
                    echo -e "   🔐 Puntuación de seguridad: ${YELLOW}ALTA (2/3)${NC}"
                    ;;
                1)
                    echo -e "   🔐 Puntuación de seguridad: ${YELLOW}MEDIA (1/3)${NC}"
                    ;;
                0)
                    echo -e "   🔐 Puntuación de seguridad: ${RED}BÁSICA (0/3)${NC}"
                    ;;
            esac
            
            # Información de imágenes
            IMAGE_COUNT=$(aws ecr list-images \
                --repository-name "$repo_name" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'length(imageIds)' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$IMAGE_COUNT" ]; then
                echo -e "   📊 Total imágenes: ${BLUE}$IMAGE_COUNT${NC}"
                
                if [ "$IMAGE_COUNT" -gt 0 ] && [ "$encryption_type" != "KMS" ]; then
                    echo -e "      ⚠️ ${YELLOW}Imágenes almacenadas sin cifrado KMS${NC}"
                fi
            fi
            
            echo ""
        fi
    done <<< "$ECR_REPOSITORIES"
    
    echo -e "${GREEN}✅ Región $CURRENT_REGION analizada${NC}"
    echo ""
done

# Generar reporte de verificación
VERIFICATION_REPORT="ecr-kms-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "account_id": "$ACCOUNT_ID",
  "regions_analyzed": ${#ACTIVE_REGIONS[@]},
  "active_regions": [$(printf '"%s",' "${ACTIVE_REGIONS[@]}" | sed 's/,$//')]],
  "summary": {
    "total_repositories": $TOTAL_REPOSITORIES,
    "kms_encrypted_repositories": $KMS_REPOSITORIES,
    "aes256_repositories": $AES256_REPOSITORIES,
    "total_kms_keys": $TOTAL_KMS_KEYS,
    "kms_compliance": "$(if [ $TOTAL_REPOSITORIES -eq 0 ]; then echo "NO_REPOSITORIES"; elif [ $AES256_REPOSITORIES -eq 0 ]; then echo "FULLY_COMPLIANT"; else echo "NON_COMPLIANT"; fi)"
  },
  "recommendations": [
    "Migrar repositorios AES256 a cifrado KMS",
    "Crear claves KMS dedicadas para ECR",
    "Implementar políticas de cifrado corporativas",
    "Configurar rotación automática de claves",
    "Monitorear uso de claves KMS",
    "Establecer controles de acceso granular"
  ]
}
EOF

echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Comandos de remediación
if [ $AES256_REPOSITORIES -gt 0 ]; then
    echo -e "${PURPLE}=== Comandos de Remediación ===${NC}"
    echo -e "${CYAN}🔧 Para configurar cifrado KMS:${NC}"
    echo -e "${BLUE}./enable-ecr-kms-encryption.sh $PROFILE${NC}"
    
    echo -e "${CYAN}🔧 Para crear nuevos repositorios con KMS:${NC}"
    for region in "${ACTIVE_REGIONS[@]}"; do
        echo -e "${BLUE}./create-ecr-repository-with-kms-$region.sh [nombre-repo]${NC}"
    done
fi

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN ECR KMS ENCRYPTION ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "🌍 Regiones con ECR: ${GREEN}$REGIONS_WITH_ECR${NC} (${ACTIVE_REGIONS[*]})"
echo -e "📦 Total repositorios: ${GREEN}$TOTAL_REPOSITORIES${NC}"

if [ $TOTAL_REPOSITORIES -gt 0 ]; then
    echo -e "🔑 Con cifrado KMS: ${GREEN}$KMS_REPOSITORIES${NC}"
    if [ $AES256_REPOSITORIES -gt 0 ]; then
        echo -e "⚠️ Con AES256: ${YELLOW}$AES256_REPOSITORIES${NC}"
    fi
    echo -e "🔐 Claves KMS disponibles: ${GREEN}$TOTAL_KMS_KEYS${NC}"
    
    # Calcular porcentaje de cumplimiento
    KMS_PERCENT=$((KMS_REPOSITORIES * 100 / TOTAL_REPOSITORIES))
    echo -e "📈 Cumplimiento KMS: ${GREEN}$KMS_PERCENT%${NC}"
fi

echo ""

# Estado final
if [ $TOTAL_REPOSITORIES -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN REPOSITORIOS ECR${NC}"
    echo -e "${BLUE}💡 No hay repositorios para verificar${NC}"
elif [ $AES256_REPOSITORIES -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE SEGURO${NC}"
    echo -e "${BLUE}💡 Todos los repositorios usan cifrado KMS${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: REQUIERE MIGRACIÓN KMS${NC}"
    echo -e "${YELLOW}💡 Ejecutar: ./enable-ecr-kms-encryption.sh $PROFILE${NC}"
fi

echo -e "📋 Reporte: ${GREEN}$VERIFICATION_REPORT${NC}"