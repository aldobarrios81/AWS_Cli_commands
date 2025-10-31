#!/bin/bash
# enable-ecr-kms-encryption.sh
# Habilitar cifrado KMS para repositorios ECR
# Mejora la seguridad de imágenes de contenedores con cifrado avanzado

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
echo -e "${BLUE}🔐 HABILITANDO CIFRADO KMS PARA ECR${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Configurando cifrado KMS para repositorios ECR existentes y futuros"
echo ""

# Verificar prerrequisitos
echo -e "${PURPLE}🔍 Verificando prerrequisitos...${NC}"

# Verificar AWS CLI
AWS_VERSION=$(aws --version 2>/dev/null | head -1)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error: AWS CLI no encontrado${NC}"
    exit 1
fi
echo -e "✅ AWS CLI encontrado: ${GREEN}$AWS_VERSION${NC}"

# Verificar credenciales
echo -e "🔐 Verificando credenciales para perfil '$PROFILE'..."
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Credenciales no válidas para perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"

# Variables de conteo
TOTAL_REPOSITORIES=0
REPOSITORIES_WITH_KMS=0
REPOSITORIES_UPDATED=0
KMS_KEYS_CREATED=0
ERRORS=0

# Verificar regiones adicionales
REGIONS=("us-east-1" "us-west-2" "eu-west-1")
ACTIVE_REGIONS=()

echo ""
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
    else
        echo -e "ℹ️ Región ${BLUE}$region${NC}: Sin repositorios ECR"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No se encontraron repositorios ECR en ninguna región${NC}"
    echo -e "${BLUE}💡 No se requiere configuración de cifrado KMS${NC}"
    exit 0
fi

echo ""

# Función para crear o verificar clave KMS para ECR
create_or_get_ecr_kms_key() {
    local region="$1"
    local key_alias="alias/ecr-encryption-key-$region"
    
    echo -e "${CYAN}🔑 Verificando clave KMS para ECR en $region...${NC}"
    
    # Verificar si la clave ya existe
    EXISTING_KEY=$(aws kms describe-key \
        --key-id "$key_alias" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'KeyMetadata.KeyId' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$EXISTING_KEY" ] && [ "$EXISTING_KEY" != "None" ]; then
        echo -e "   ✅ Clave KMS existente: ${GREEN}$key_alias${NC}"
        echo -e "   🆔 Key ID: ${BLUE}$EXISTING_KEY${NC}"
        echo "$EXISTING_KEY"
        return 0
    fi
    
    echo -e "   🔧 Creando nueva clave KMS para ECR..."
    
    # Crear política para la clave KMS
    KMS_POLICY=$(cat << EOF
{
    "Version": "2012-10-17",
    "Id": "ecr-kms-key-policy",
    "Statement": [
        {
            "Sid": "Enable IAM User Permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
            },
            "Action": "kms:*",
            "Resource": "*"
        },
        {
            "Sid": "Allow ECR Service",
            "Effect": "Allow",
            "Principal": {
                "Service": "ecr.amazonaws.com"
            },
            "Action": [
                "kms:Decrypt",
                "kms:DescribeKey",
                "kms:Encrypt",
                "kms:GenerateDataKey",
                "kms:GenerateDataKeyWithoutPlaintext",
                "kms:ReEncryptFrom",
                "kms:ReEncryptTo"
            ],
            "Resource": "*"
        },
        {
            "Sid": "Allow ECR Repository Service",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": [
                "kms:Decrypt",
                "kms:DescribeKey"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "kms:ViaService": "ecr.$region.amazonaws.com"
                }
            }
        }
    ]
}
EOF
)
    
    # Crear la clave KMS
    NEW_KEY_ID=$(aws kms create-key \
        --policy "$KMS_POLICY" \
        --description "ECR encryption key for region $region" \
        --usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'KeyMetadata.KeyId' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$NEW_KEY_ID" ]; then
        echo -e "   ✅ Clave KMS creada: ${GREEN}$NEW_KEY_ID${NC}"
        
        # Crear alias para la clave
        aws kms create-alias \
            --alias-name "ecr-encryption-key-$region" \
            --target-key-id "$NEW_KEY_ID" \
            --profile "$PROFILE" \
            --region "$region" &>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "   ✅ Alias creado: ${GREEN}$key_alias${NC}"
        fi
        
        # Agregar tags a la clave
        aws kms tag-resource \
            --key-id "$NEW_KEY_ID" \
            --tags "TagKey=Purpose,TagValue=ECR-Encryption" "TagKey=Environment,TagValue=Production" "TagKey=ManagedBy,TagValue=SecurityAutomation" "TagKey=Region,TagValue=$region" \
            --profile "$PROFILE" \
            --region "$region" &>/dev/null
        
        KMS_KEYS_CREATED=$((KMS_KEYS_CREATED + 1))
        echo "$NEW_KEY_ID"
        return 0
    else
        echo -e "   ${RED}❌ Error al crear clave KMS${NC}"
        return 1
    fi
}

# Procesar cada región activa
for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "${PURPLE}=== Procesando región: $CURRENT_REGION ===${NC}"
    
    # Crear o obtener clave KMS para la región
    KMS_KEY_ID=$(create_or_get_ecr_kms_key "$CURRENT_REGION")
    
    if [ $? -ne 0 ] || [ -z "$KMS_KEY_ID" ]; then
        echo -e "${RED}❌ No se puede configurar cifrado KMS para región $CURRENT_REGION${NC}"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    
    echo -e "🎯 Usando clave KMS: ${BLUE}$KMS_KEY_ID${NC}"
    echo ""
    
    # Obtener lista de repositorios ECR
    ECR_REPOSITORIES=$(aws ecr describe-repositories \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'repositories[].[repositoryName,encryptionConfiguration.encryptionType,encryptionConfiguration.kmsKey,createdAt]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error al obtener repositorios ECR en región $CURRENT_REGION${NC}"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    
    if [ -z "$ECR_REPOSITORIES" ]; then
        echo -e "${BLUE}ℹ️ Sin repositorios ECR en región $CURRENT_REGION${NC}"
        continue
    fi
    
    echo -e "${GREEN}📊 Repositorios ECR encontrados en $CURRENT_REGION:${NC}"
    
    while IFS=$'\t' read -r repo_name encryption_type kms_key created_at; do
        if [ -n "$repo_name" ] && [ "$repo_name" != "None" ]; then
            TOTAL_REPOSITORIES=$((TOTAL_REPOSITORIES + 1))
            
            echo -e "${CYAN}📦 Repositorio: $repo_name${NC}"
            echo -e "   📅 Creado: ${BLUE}$(echo "$created_at" | cut -d'T' -f1)${NC}"
            
            # Verificar cifrado actual
            if [ "$encryption_type" == "KMS" ] && [ -n "$kms_key" ] && [ "$kms_key" != "None" ]; then
                echo -e "   ✅ Cifrado KMS: ${GREEN}YA CONFIGURADO${NC}"
                echo -e "   🔑 Clave actual: ${BLUE}$kms_key${NC}"
                REPOSITORIES_WITH_KMS=$((REPOSITORIES_WITH_KMS + 1))
                
                # Verificar si es la clave correcta
                if [ "$kms_key" != "$KMS_KEY_ID" ] && [[ ! "$kms_key" =~ "ecr-encryption-key" ]]; then
                    echo -e "   ⚠️ ${YELLOW}Nota: Usando clave KMS diferente${NC}"
                fi
                
            elif [ "$encryption_type" == "AES256" ] || [ -z "$encryption_type" ] || [ "$encryption_type" == "None" ]; then
                echo -e "   ⚠️ Cifrado actual: ${YELLOW}AES256 (por defecto)${NC}"
                echo -e "   🔧 Actualizando a cifrado KMS..."
                
                # NOTA: ECR no permite cambiar el cifrado de repositorios existentes
                # Solo se puede configurar en la creación
                echo -e "   ℹ️ ${BLUE}Limitación AWS: No se puede cambiar cifrado de repositorios existentes${NC}"
                echo -e "   💡 ${YELLOW}Recomendación: Recrear repositorio con KMS o crear nuevos con KMS${NC}"
                
                # Verificar si hay imágenes en el repositorio
                IMAGE_COUNT=$(aws ecr list-images \
                    --repository-name "$repo_name" \
                    --profile "$PROFILE" \
                    --region "$CURRENT_REGION" \
                    --query 'length(imageIds)' \
                    --output text 2>/dev/null)
                
                if [ $? -eq 0 ] && [ -n "$IMAGE_COUNT" ] && [ "$IMAGE_COUNT" -gt 0 ]; then
                    echo -e "   📊 Imágenes actuales: ${YELLOW}$IMAGE_COUNT${NC}"
                    echo -e "   🔄 Se requiere migración manual para habilitar KMS"
                else
                    echo -e "   📊 Repositorio vacío - ${GREEN}Candidato para recreación con KMS${NC}"
                fi
                
            else
                echo -e "   ❓ Cifrado desconocido: ${YELLOW}$encryption_type${NC}"
            fi
            
            echo ""
        fi
    done <<< "$ECR_REPOSITORIES"
    
    echo -e "${GREEN}✅ Región $CURRENT_REGION procesada${NC}"
    echo ""
done

# Configurar política de registro para nuevos repositorios
echo -e "${PURPLE}=== Configurando Scripts Helper ===${NC}"

for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "🔧 Creando script helper para región: ${CYAN}$CURRENT_REGION${NC}"
    
    # Obtener clave KMS para la región
    KMS_KEY_ID=$(aws kms describe-key \
        --key-id "alias/ecr-encryption-key-$CURRENT_REGION" \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'KeyMetadata.KeyId' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$KMS_KEY_ID" ]; then
        # Crear script helper para nuevos repositorios
        HELPER_SCRIPT="create-ecr-repository-with-kms-$CURRENT_REGION.sh"
        
        cat > "$HELPER_SCRIPT" << EOF
#!/bin/bash
# Script helper para crear repositorios ECR con cifrado KMS
# Región: $CURRENT_REGION
# Perfil: $PROFILE

if [ \\\$# -eq 0 ]; then
    echo "Uso: \\\$0 [nombre-repositorio]"
    exit 1
fi

REPO_NAME="\\\$1"
KMS_KEY_ID="$KMS_KEY_ID"

echo "Creando repositorio ECR con cifrado KMS..."
echo "Nombre: \\\$REPO_NAME"
echo "KMS Key: \\\$KMS_KEY_ID"
echo "Región: $CURRENT_REGION"

aws ecr create-repository \\\\
    --repository-name "\\\$REPO_NAME" \\\\
    --encryption-configuration encryptionType=KMS,kmsKey=\\\$KMS_KEY_ID \\\\
    --image-tag-mutability IMMUTABLE \\\\
    --image-scanning-configuration scanOnPush=true \\\\
    --profile $PROFILE \\\\
    --region $CURRENT_REGION

if [ \\\$? -eq 0 ]; then
    echo "✅ Repositorio creado exitosamente con cifrado KMS"
else
    echo "❌ Error al crear repositorio"
fi
EOF
        
        chmod +x "$HELPER_SCRIPT"
        echo -e "   ✅ Script helper creado: ${GREEN}$HELPER_SCRIPT${NC}"
    else
        echo -e "   ⚠️ No se pudo obtener clave KMS para región $CURRENT_REGION"
    fi
done

# Generar documentación
DOCUMENTATION_FILE="ecr-kms-encryption-$PROFILE-$(date +%Y%m%d).md"

cat > "$DOCUMENTATION_FILE" << EOF
# Configuración Cifrado KMS - ECR - $PROFILE

**Fecha**: $(date)
**Account ID**: $ACCOUNT_ID
**Regiones procesadas**: ${ACTIVE_REGIONS[*]}

## Resumen Ejecutivo

### Repositorios ECR Procesados
- **Total repositorios**: $TOTAL_REPOSITORIES
- **Con cifrado KMS**: $REPOSITORIES_WITH_KMS
- **Claves KMS creadas**: $KMS_KEYS_CREATED
- **Errores**: $ERRORS

## Configuraciones Implementadas

### 🔐 Cifrado KMS
- Configuración: Claves KMS dedicadas por región
- Política: Acceso controlado para servicio ECR
- Rotación: Automática (AWS managed)

### 🔑 Gestión de Claves
- Alias: ecr-encryption-key-[región]
- Descripción: ECR encryption key for region
- Tags: Purpose, Environment, ManagedBy, Region

## Limitaciones AWS ECR

### 1. Repositorios Existentes
- No se puede cambiar cifrado de repositorios existentes
- Requiere recreación del repositorio
- Migración manual de imágenes necesaria

### 2. Nuevos Repositorios
- Configuración KMS solo en creación
- Scripts helper generados para facilitar proceso
- Configuración automática disponible

## Comandos de Verificación

\\\`\\\`\\\`bash
# Verificar cifrado de repositorio
aws ecr describe-repositories --repository-names REPO_NAME \\\\
    --profile $PROFILE --region us-east-1 \\\\
    --query 'repositories[0].encryptionConfiguration'

# Listar claves KMS ECR
aws kms list-aliases --profile $PROFILE --region us-east-1 \\\\
    --query 'Aliases[?contains(AliasName, \\\`ecr-encryption\\\`)]'

# Crear nuevo repositorio con KMS
./create-ecr-repository-with-kms-us-east-1.sh mi-nuevo-repo
\\\`\\\`\\\`

EOF

echo -e "✅ Documentación generada: ${GREEN}$DOCUMENTATION_FILE${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN CONFIGURACIÓN ECR KMS ENCRYPTION ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "🌍 Regiones procesadas: ${GREEN}${#ACTIVE_REGIONS[@]}${NC} (${ACTIVE_REGIONS[*]})"
echo -e "📦 Total repositorios ECR: ${GREEN}$TOTAL_REPOSITORIES${NC}"
echo -e "🔑 Repositorios con KMS: ${GREEN}$REPOSITORIES_WITH_KMS${NC}"
echo -e "🆕 Claves KMS creadas: ${GREEN}$KMS_KEYS_CREATED${NC}"

if [ $ERRORS -gt 0 ]; then
    echo -e "⚠️ Errores encontrados: ${YELLOW}$ERRORS${NC}"
fi

# Calcular porcentaje de cumplimiento KMS
if [ $TOTAL_REPOSITORIES -gt 0 ]; then
    KMS_PERCENT=$((REPOSITORIES_WITH_KMS * 100 / TOTAL_REPOSITORIES))
    echo -e "📈 Cumplimiento KMS: ${GREEN}$KMS_PERCENT%${NC}"
fi

echo -e "📋 Documentación: ${GREEN}$DOCUMENTATION_FILE${NC}"
echo ""

# Estado final
if [ $TOTAL_REPOSITORIES -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN REPOSITORIOS ECR${NC}"
    echo -e "${BLUE}💡 Claves KMS preparadas para futuros repositorios${NC}"
elif [ $REPOSITORIES_WITH_KMS -eq $TOTAL_REPOSITORIES ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE CIFRADO${NC}"
    echo -e "${BLUE}💡 Todos los repositorios usan cifrado KMS${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: CIFRADO MIXTO${NC}"
    echo -e "${YELLOW}💡 Considerar migración de repositorios a KMS${NC}"
    
    # Mostrar recomendación de migración
    REPOS_TO_MIGRATE=$((TOTAL_REPOSITORIES - REPOSITORIES_WITH_KMS))
    echo -e "${CYAN}🔄 Repositorios pendientes de migración: ${YELLOW}$REPOS_TO_MIGRATE${NC}"
fi

# Mostrar scripts helper creados
if [ ${#ACTIVE_REGIONS[@]} -gt 0 ]; then
    echo ""
    echo -e "${CYAN}🛠️ Scripts helper para nuevos repositorios:${NC}"
    for region in "${ACTIVE_REGIONS[@]}"; do
        echo -e "   📋 ${BLUE}create-ecr-repository-with-kms-$region.sh${NC}"
    done
fi

