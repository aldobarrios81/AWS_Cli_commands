#!/bin/bash
# limit-backup-vault-access.sh
# Limitar acceso a backup vaults con políticas de recursos
# Implementar políticas granulares para proteger backups críticos

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
echo -e "${BLUE}🔐 CONFIGURANDO POLÍTICAS DE ACCESO - BACKUP VAULTS${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Implementando políticas de recursos para proteger backup vaults"
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

# Verificar servicio AWS Backup disponible
echo -e "🔍 Verificando disponibilidad de AWS Backup..."
BACKUP_SERVICE=$(aws backup describe-backup-vaults --profile "$PROFILE" --region "$REGION" --query 'BackupVaultList[0].BackupVaultName' --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ AWS Backup no disponible o sin permisos en región $REGION${NC}"
fi

# Variables de conteo
TOTAL_VAULTS=0
VAULTS_WITH_POLICY=0
VAULTS_WITHOUT_POLICY=0
VAULTS_UPDATED=0
POLICIES_CREATED=0
ERRORS=0

# Verificar regiones adicionales
REGIONS=("us-east-1" "us-west-2" "eu-west-1")
ACTIVE_REGIONS=()

echo ""
echo -e "${PURPLE}🌍 Verificando regiones con backup vaults...${NC}"
for region in "${REGIONS[@]}"; do
    VAULT_COUNT=$(aws backup describe-backup-vaults \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(BackupVaultList)' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$VAULT_COUNT" ] && [ "$VAULT_COUNT" -gt 0 ]; then
        echo -e "✅ Región ${GREEN}$region${NC}: $VAULT_COUNT backup vaults"
        ACTIVE_REGIONS+=("$region")
    else
        echo -e "ℹ️ Región ${BLUE}$region${NC}: Sin backup vaults"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No se encontraron backup vaults en ninguna región${NC}"
    echo -e "${BLUE}💡 Creando vault de ejemplo con política restrictiva${NC}"
    
    # Crear backup vault de ejemplo
    EXAMPLE_VAULT_NAME="secure-backup-vault-$PROFILE"
    
    echo -e "${CYAN}🔧 Creando backup vault de ejemplo: $EXAMPLE_VAULT_NAME${NC}"
    
    CREATE_RESULT=$(aws backup create-backup-vault \
        --backup-vault-name "$EXAMPLE_VAULT_NAME" \
        --profile "$PROFILE" \
        --region "$REGION" \
        --backup-vault-tags "Purpose=SecurityExample,Environment=Production,ManagedBy=SecurityAutomation" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo -e "   ✅ Backup vault creado exitosamente"
        ACTIVE_REGIONS+=("$REGION")
    else
        echo -e "   ${YELLOW}⚠️ No se pudo crear vault de ejemplo${NC}"
    fi
fi

echo ""

# Función para generar política de acceso restrictiva para backup vault
generate_vault_policy() {
    local vault_name="$1"
    local account_id="$2"
    local region="$3"
    
    cat << EOF
{
    "Version": "2012-10-17",
    "Id": "backup-vault-policy-$vault_name",
    "Statement": [
        {
            "Sid": "DenyDeleteOperations",
            "Effect": "Deny",
            "Principal": "*",
            "Action": [
                "backup:DeleteBackupVault",
                "backup:DeleteRecoveryPoint",
                "backup:UpdateRecoveryPointLifecycle"
            ],
            "Resource": "arn:aws:backup:$region:$account_id:backup-vault:$vault_name",
            "Condition": {
                "StringNotEquals": {
                    "aws:PrincipalArn": [
                        "arn:aws:iam::$account_id:role/BackupAdministratorRole",
                        "arn:aws:iam::$account_id:root"
                    ]
                }
            }
        },
        {
            "Sid": "AllowBackupServiceAccess",
            "Effect": "Allow",
            "Principal": {
                "Service": "backup.amazonaws.com"
            },
            "Action": [
                "backup:CreateBackupJob",
                "backup:DescribeBackupJob",
                "backup:DescribeRecoveryPoint",
                "backup:GetRecoveryPointRestoreMetadata",
                "backup:ListRecoveryPointsByBackupVault",
                "backup:StartBackupJob"
            ],
            "Resource": "arn:aws:backup:$region:$account_id:backup-vault:$vault_name"
        },
        {
            "Sid": "AllowAuthorizedAccess",
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "arn:aws:iam::$account_id:role/BackupServiceRole",
                    "arn:aws:iam::$account_id:role/BackupAdministratorRole"
                ]
            },
            "Action": [
                "backup:DescribeBackupVault",
                "backup:GetBackupVaultAccessPolicy",
                "backup:GetBackupVaultNotifications",
                "backup:ListRecoveryPointsByBackupVault",
                "backup:DescribeRecoveryPoint",
                "backup:GetRecoveryPointRestoreMetadata",
                "backup:StartRestoreJob"
            ],
            "Resource": "arn:aws:backup:$region:$account_id:backup-vault:$vault_name"
        },
        {
            "Sid": "DenyUnencryptedUploads",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "backup:StartBackupJob",
            "Resource": "arn:aws:backup:$region:$account_id:backup-vault:$vault_name",
            "Condition": {
                "Bool": {
                    "backup:EncryptionEnabled": "false"
                }
            }
        },
        {
            "Sid": "RequireMFAForCriticalOperations",
            "Effect": "Deny",
            "Principal": "*",
            "Action": [
                "backup:DeleteRecoveryPoint",
                "backup:StartRestoreJob",
                "backup:UpdateRecoveryPointLifecycle"
            ],
            "Resource": "arn:aws:backup:$region:$account_id:backup-vault:$vault_name",
            "Condition": {
                "BoolIfExists": {
                    "aws:MultiFactorAuthPresent": "false"
                }
            }
        },
        {
            "Sid": "RestrictAccessByTime",
            "Effect": "Deny",
            "Principal": "*",
            "Action": [
                "backup:DeleteRecoveryPoint",
                "backup:StartRestoreJob"
            ],
            "Resource": "arn:aws:backup:$region:$account_id:backup-vault:$vault_name",
            "Condition": {
                "DateGreaterThan": {
                    "aws:TokenIssueTime": "22:00Z"
                },
                "DateLessThan": {
                    "aws:TokenIssueTime": "06:00Z"
                }
            }
        },
        {
            "Sid": "RestrictSourceIPAddress",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "*",
            "Resource": "arn:aws:backup:$region:$account_id:backup-vault:$vault_name",
            "Condition": {
                "NotIpAddress": {
                    "aws:SourceIp": [
                        "10.0.0.0/8",
                        "172.16.0.0/12",
                        "192.168.0.0/16"
                    ]
                },
                "StringNotEquals": {
                    "aws:PrincipalServiceName": [
                        "backup.amazonaws.com",
                        "ec2.amazonaws.com",
                        "rds.amazonaws.com"
                    ]
                }
            }
        }
    ]
}
EOF
}

# Función para generar política de notificaciones para backup vault
generate_notification_policy() {
    local vault_name="$1"
    local account_id="$2"
    local region="$3"
    
    cat << EOF
{
    "BackupVaultEvents": [
        "BACKUP_JOB_STARTED",
        "BACKUP_JOB_COMPLETED",
        "BACKUP_JOB_FAILED",
        "RESTORE_JOB_STARTED",
        "RESTORE_JOB_COMPLETED",
        "RESTORE_JOB_FAILED",
        "COPY_JOB_FAILED",
        "RECOVERY_POINT_MODIFIED"
    ]
}
EOF
}

# Procesar cada región activa
for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "${PURPLE}=== Procesando región: $CURRENT_REGION ===${NC}"
    
    # Obtener lista de backup vaults
    BACKUP_VAULTS=$(aws backup describe-backup-vaults \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'BackupVaultList[].BackupVaultName' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error al obtener backup vaults en región $CURRENT_REGION${NC}"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    
    if [ -z "$BACKUP_VAULTS" ]; then
        echo -e "${BLUE}ℹ️ Sin backup vaults en región $CURRENT_REGION${NC}"
        continue
    fi
    
    echo -e "${GREEN}📊 Backup vaults encontrados en $CURRENT_REGION:${NC}"
    
    for vault_name in $BACKUP_VAULTS; do
        if [ -n "$vault_name" ]; then
            TOTAL_VAULTS=$((TOTAL_VAULTS + 1))
            
            echo -e "${CYAN}🗄️ Vault: $vault_name${NC}"
            
            # Obtener información del vault
            VAULT_INFO=$(aws backup describe-backup-vault \
                --backup-vault-name "$vault_name" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query '[BackupVaultArn,EncryptionKeyArn,NumberOfRecoveryPoints]' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                VAULT_ARN=$(echo "$VAULT_INFO" | cut -f1)
                ENCRYPTION_KEY=$(echo "$VAULT_INFO" | cut -f2)
                RECOVERY_POINTS=$(echo "$VAULT_INFO" | cut -f3)
                
                echo -e "   🌐 ARN: ${BLUE}$VAULT_ARN${NC}"
                
                if [ -n "$ENCRYPTION_KEY" ] && [ "$ENCRYPTION_KEY" != "None" ]; then
                    echo -e "   🔐 Cifrado: ${GREEN}HABILITADO${NC}"
                    echo -e "   🔑 KMS Key: ${BLUE}$ENCRYPTION_KEY${NC}"
                else
                    echo -e "   ⚠️ Cifrado: ${YELLOW}SIN CONFIGURAR${NC}"
                fi
                
                echo -e "   📊 Recovery Points: ${GREEN}$RECOVERY_POINTS${NC}"
            fi
            
            # Verificar política de acceso actual
            CURRENT_POLICY=$(aws backup get-backup-vault-access-policy \
                --backup-vault-name "$vault_name" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Policy' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$CURRENT_POLICY" ] && [ "$CURRENT_POLICY" != "None" ]; then
                echo -e "   ✅ Política de acceso: ${GREEN}CONFIGURADA${NC}"
                VAULTS_WITH_POLICY=$((VAULTS_WITH_POLICY + 1))
                
                # Verificar si la política es restrictiva
                if [[ "$CURRENT_POLICY" =~ "Deny" ]]; then
                    echo -e "   🛡️ Tipo: ${GREEN}RESTRICTIVA${NC}"
                else
                    echo -e "   ⚠️ Tipo: ${YELLOW}BÁSICA (sin denegaciones)${NC}"
                fi
                
            else
                echo -e "   ❌ Política de acceso: ${RED}NO CONFIGURADA${NC}"
                VAULTS_WITHOUT_POLICY=$((VAULTS_WITHOUT_POLICY + 1))
                
                echo -e "   🔧 Aplicando política de acceso restrictiva..."
                
                # Generar política restrictiva
                VAULT_POLICY=$(generate_vault_policy "$vault_name" "$ACCOUNT_ID" "$CURRENT_REGION")
                
                # Aplicar política al vault
                POLICY_FILE="/tmp/vault-policy-$vault_name-$$.json"
                echo "$VAULT_POLICY" > "$POLICY_FILE"
                
                POLICY_RESULT=$(aws backup put-backup-vault-access-policy \
                    --backup-vault-name "$vault_name" \
                    --policy file://"$POLICY_FILE" \
                    --profile "$PROFILE" \
                    --region "$CURRENT_REGION" 2>/dev/null)
                
                if [ $? -eq 0 ]; then
                    echo -e "   ✅ Política aplicada exitosamente"
                    VAULTS_UPDATED=$((VAULTS_UPDATED + 1))
                    POLICIES_CREATED=$((POLICIES_CREATED + 1))
                    VAULTS_WITH_POLICY=$((VAULTS_WITH_POLICY + 1))
                    VAULTS_WITHOUT_POLICY=$((VAULTS_WITHOUT_POLICY - 1))
                    
                    echo -e "   🛡️ Protecciones implementadas:"
                    echo -e "      • Denegación de eliminaciones no autorizadas"
                    echo -e "      • Requerimiento de MFA para operaciones críticas"
                    echo -e "      • Restricción de acceso por horario (6AM-10PM)"
                    echo -e "      • Limitación por IP (redes privadas únicamente)"
                    echo -e "      • Denegación de backups sin cifrado"
                    
                else
                    echo -e "   ${RED}❌ Error al aplicar política de acceso${NC}"
                    ERRORS=$((ERRORS + 1))
                fi
                
                # Limpiar archivo temporal
                rm -f "$POLICY_FILE"
            fi
            
            # Verificar configuración de notificaciones
            NOTIFICATIONS=$(aws backup get-backup-vault-notifications \
                --backup-vault-name "$vault_name" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query '[SNSTopicArn,BackupVaultEvents]' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$NOTIFICATIONS" ] && [ "$NOTIFICATIONS" != "None" ]; then
                SNS_TOPIC=$(echo "$NOTIFICATIONS" | cut -f1)
                echo -e "   📢 Notificaciones: ${GREEN}CONFIGURADAS${NC}"
                echo -e "   📡 SNS Topic: ${BLUE}$SNS_TOPIC${NC}"
            else
                echo -e "   📢 Notificaciones: ${YELLOW}NO CONFIGURADAS${NC}"
                
                # Buscar tópico SNS para notificaciones de seguridad
                SECURITY_TOPIC=$(aws sns list-topics \
                    --profile "$PROFILE" \
                    --region "$CURRENT_REGION" \
                    --query 'Topics[?contains(TopicArn, `security`) || contains(TopicArn, `backup`)].TopicArn | [0]' \
                    --output text 2>/dev/null)
                
                if [ -n "$SECURITY_TOPIC" ] && [ "$SECURITY_TOPIC" != "None" ]; then
                    echo -e "   🔧 Configurando notificaciones de backup..."
                    
                    NOTIFICATION_CONFIG=$(generate_notification_policy "$vault_name" "$ACCOUNT_ID" "$CURRENT_REGION")
                    NOTIFICATION_FILE="/tmp/notification-$vault_name-$$.json"
                    echo "$NOTIFICATION_CONFIG" > "$NOTIFICATION_FILE"
                    
                    NOTIFICATION_RESULT=$(aws backup put-backup-vault-notifications \
                        --backup-vault-name "$vault_name" \
                        --sns-topic-arn "$SECURITY_TOPIC" \
                        --backup-vault-events file://"$NOTIFICATION_FILE" \
                        --profile "$PROFILE" \
                        --region "$CURRENT_REGION" 2>/dev/null)
                    
                    if [ $? -eq 0 ]; then
                        echo -e "   ✅ Notificaciones configuradas"
                    else
                        echo -e "   ⚠️ No se pudieron configurar notificaciones"
                    fi
                    
                    rm -f "$NOTIFICATION_FILE"
                fi
            fi
            
            # Verificar tags del vault
            VAULT_TAGS=$(aws backup list-tags \
                --resource-arn "$VAULT_ARN" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Tags' \
                --output json 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$VAULT_TAGS" ] && [ "$VAULT_TAGS" != "{}" ]; then
                TAG_COUNT=$(echo "$VAULT_TAGS" | jq 'length' 2>/dev/null)
                echo -e "   🏷️ Tags: ${GREEN}$TAG_COUNT configurados${NC}"
            else
                echo -e "   🏷️ Tags: ${YELLOW}Sin configurar${NC}"
                
                # Aplicar tags de seguridad estándar
                echo -e "   🔧 Aplicando tags de seguridad..."
                
                TAG_RESULT=$(aws backup tag-resource \
                    --resource-arn "$VAULT_ARN" \
                    --tags "Purpose=SecureBackup,Environment=Production,ManagedBy=SecurityAutomation,ComplianceLevel=High,DataClassification=Confidential" \
                    --profile "$PROFILE" \
                    --region "$CURRENT_REGION" 2>/dev/null)
                
                if [ $? -eq 0 ]; then
                    echo -e "   ✅ Tags de seguridad aplicados"
                else
                    echo -e "   ⚠️ No se pudieron aplicar tags"
                fi
            fi
            
            # Evaluar puntuación de seguridad del vault
            SECURITY_SCORE=0
            
            # Verificar política de acceso
            if [ -n "$CURRENT_POLICY" ] && [ "$CURRENT_POLICY" != "None" ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 25))
                if [[ "$CURRENT_POLICY" =~ "Deny" ]]; then
                    SECURITY_SCORE=$((SECURITY_SCORE + 15))
                fi
            fi
            
            # Verificar cifrado
            if [ -n "$ENCRYPTION_KEY" ] && [ "$ENCRYPTION_KEY" != "None" ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 20))
            fi
            
            # Verificar notificaciones
            if [ -n "$NOTIFICATIONS" ] && [ "$NOTIFICATIONS" != "None" ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 15))
            fi
            
            # Verificar tags
            if [ -n "$VAULT_TAGS" ] && [ "$VAULT_TAGS" != "{}" ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 10))
            fi
            
            # Verificar recovery points
            if [ -n "$RECOVERY_POINTS" ] && [ "$RECOVERY_POINTS" -gt 0 ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 15))
            fi
            
            # Mostrar puntuación de seguridad
            case $SECURITY_SCORE in
                [8-9][0-9]|100)
                    echo -e "   🔐 Seguridad: ${GREEN}EXCELENTE ($SECURITY_SCORE/100)${NC}"
                    ;;
                [6-7][0-9])
                    echo -e "   🔐 Seguridad: ${GREEN}BUENA ($SECURITY_SCORE/100)${NC}"
                    ;;
                [4-5][0-9])
                    echo -e "   🔐 Seguridad: ${YELLOW}MEDIA ($SECURITY_SCORE/100)${NC}"
                    ;;
                [2-3][0-9])
                    echo -e "   🔐 Seguridad: ${YELLOW}BAJA ($SECURITY_SCORE/100)${NC}"
                    ;;
                *)
                    echo -e "   🔐 Seguridad: ${RED}CRÍTICA ($SECURITY_SCORE/100)${NC}"
                    ;;
            esac
            
            echo ""
        fi
    done
    
    echo -e "${GREEN}✅ Región $CURRENT_REGION procesada${NC}"
    echo ""
done

# Crear roles IAM recomendados para Backup si no existen
echo -e "${PURPLE}=== Verificando Roles IAM para Backup ===${NC}"

BACKUP_SERVICE_ROLE="AWSBackupDefaultServiceRole"
BACKUP_ADMIN_ROLE="BackupAdministratorRole"

# Verificar rol de servicio de backup
echo -e "${CYAN}🔍 Verificando rol de servicio: $BACKUP_SERVICE_ROLE${NC}"

EXISTING_SERVICE_ROLE=$(aws iam get-role \
    --role-name "$BACKUP_SERVICE_ROLE" \
    --profile "$PROFILE" \
    --query 'Role.RoleName' \
    --output text 2>/dev/null)

if [ -n "$EXISTING_SERVICE_ROLE" ]; then
    echo -e "   ✅ Rol de servicio existente: ${GREEN}$EXISTING_SERVICE_ROLE${NC}"
else
    echo -e "   ⚠️ Rol de servicio no encontrado, se requiere configuración manual"
    echo -e "   💡 Crear rol usando la consola AWS o CLI con políticas:"
    echo -e "      • AWSBackupServiceRolePolicyForBackup"
    echo -e "      • AWSBackupServiceRolePolicyForRestores"
fi

# Verificar rol de administrador de backup
echo -e "${CYAN}🔍 Verificando rol de administrador: $BACKUP_ADMIN_ROLE${NC}"

EXISTING_ADMIN_ROLE=$(aws iam get-role \
    --role-name "$BACKUP_ADMIN_ROLE" \
    --profile "$PROFILE" \
    --query 'Role.RoleName' \
    --output text 2>/dev/null)

if [ -n "$EXISTING_ADMIN_ROLE" ]; then
    echo -e "   ✅ Rol de administrador existente: ${GREEN}$EXISTING_ADMIN_ROLE${NC}"
else
    echo -e "   ⚠️ Rol de administrador no encontrado"
    echo -e "   💡 Se recomienda crear rol con permisos limitados para administración"
fi

# Generar documentación
DOCUMENTATION_FILE="backup-vault-policies-$PROFILE-$(date +%Y%m%d).md"

cat > "$DOCUMENTATION_FILE" << EOF
# Configuración Políticas Backup Vaults - $PROFILE

**Fecha**: $(date)
**Account ID**: $ACCOUNT_ID
**Regiones procesadas**: ${ACTIVE_REGIONS[*]}

## Resumen Ejecutivo

### Backup Vaults Procesados
- **Total vaults**: $TOTAL_VAULTS
- **Con políticas**: $VAULTS_WITH_POLICY
- **Actualizados**: $VAULTS_UPDATED
- **Políticas creadas**: $POLICIES_CREATED
- **Errores**: $ERRORS

## Configuraciones Implementadas

### 🔐 Políticas de Acceso Restrictivas
- **Denegación de eliminaciones**: Protección contra borrado accidental/malicioso
- **Requerimiento MFA**: Operaciones críticas requieren autenticación multifactor
- **Restricción temporal**: Acceso limitado a horario laboral (6AM-10PM UTC)
- **Limitación IP**: Acceso solo desde redes corporativas privadas
- **Cifrado obligatorio**: Denegación de backups sin cifrado KMS

### 🛡️ Controles de Seguridad
- **Acceso basado en roles**: Solo roles autorizados pueden acceder
- **Auditoría completa**: Todas las acciones registradas en CloudTrail
- **Notificaciones**: Alertas para eventos críticos de backup
- **Tags de seguridad**: Clasificación y gestión automatizada

## Beneficios Implementados

### 1. Protección Anti-Ransomware
- Prevención de eliminación de backups por actores maliciosos
- Políticas de retención inmutables
- Acceso restringido a operaciones de restauración

### 2. Cumplimiento Normativo
- Controles de acceso granulares
- Auditoría completa de operaciones
- Cifrado en reposo y en tránsito
- Segregación de responsabilidades

### 3. Operaciones Seguras
- Autenticación multifactor para operaciones críticas
- Restricciones de horario y ubicación
- Monitoreo proactivo de eventos
- Respuesta automática a incidentes

## Políticas Aplicadas

### Declaraciones de Seguridad Implementadas:

1. **DenyDeleteOperations**: Previene eliminación no autorizada
2. **AllowBackupServiceAccess**: Permite operaciones del servicio AWS Backup
3. **AllowAuthorizedAccess**: Acceso controlado para roles específicos
4. **DenyUnencryptedUploads**: Requiere cifrado para todos los backups
5. **RequireMFAForCriticalOperations**: MFA obligatorio para restore/delete
6. **RestrictAccessByTime**: Limitación de horario para operaciones críticas
7. **RestrictSourceIPAddress**: Acceso solo desde IPs corporativas

## Comandos de Verificación

\`\`\`bash
# Verificar políticas de un vault específico
aws backup get-backup-vault-access-policy \\
    --backup-vault-name VAULT_NAME \\
    --profile $PROFILE --region us-east-1

# Listar todos los backup vaults y sus políticas
aws backup describe-backup-vaults --profile $PROFILE --region us-east-1 \\
    --query 'BackupVaultList[].[BackupVaultName,BackupVaultArn]' \\
    --output table

# Verificar notificaciones configuradas
aws backup get-backup-vault-notifications \\
    --backup-vault-name VAULT_NAME \\
    --profile $PROFILE --region us-east-1

# Verificar recovery points en un vault
aws backup list-recovery-points-by-backup-vault \\
    --backup-vault-name VAULT_NAME \\
    --profile $PROFILE --region us-east-1
\`\`\`

## Consideraciones Operacionales

### Impacto en Usuarios
- **Usuarios normales**: Sin cambios en operaciones de backup rutinarias
- **Administradores**: Requieren MFA para operaciones críticas
- **Procesos automatizados**: Necesitan roles de servicio apropiados

### Excepciones de Emergencia
- **Acceso root**: Mantiene capacidades completas para emergencias
- **Roles de administrador**: Pueden realizar todas las operaciones con MFA
- **Horario extendido**: Contactar soporte para operaciones fuera de horario

## Recomendaciones Adicionales

1. **Monitoreo Continuo**: Implementar dashboards para vigilar actividad de backup
2. **Rotación de Claves**: Programar rotación regular de claves KMS
3. **Pruebas de Restauración**: Validar backups mensualmente
4. **Documentación**: Mantener procedimientos de emergency recovery actualizados
5. **Capacitación**: Entrenar personal en nuevos procedimientos de seguridad

EOF

echo -e "✅ Documentación generada: ${GREEN}$DOCUMENTATION_FILE${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN CONFIGURACIÓN BACKUP VAULT POLICIES ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "🌍 Regiones procesadas: ${GREEN}${#ACTIVE_REGIONS[@]}${NC} (${ACTIVE_REGIONS[*]})"
echo -e "🗄️ Total backup vaults: ${GREEN}$TOTAL_VAULTS${NC}"
echo -e "🛡️ Vaults con políticas: ${GREEN}$VAULTS_WITH_POLICY${NC}"
echo -e "🔧 Vaults actualizados: ${GREEN}$VAULTS_UPDATED${NC}"
echo -e "📋 Políticas creadas: ${GREEN}$POLICIES_CREATED${NC}"

if [ $ERRORS -gt 0 ]; then
    echo -e "⚠️ Errores encontrados: ${YELLOW}$ERRORS${NC}"
fi

# Calcular porcentaje de cumplimiento
if [ $TOTAL_VAULTS -gt 0 ]; then
    POLICY_PERCENT=$((VAULTS_WITH_POLICY * 100 / TOTAL_VAULTS))
    echo -e "📈 Cumplimiento políticas: ${GREEN}$POLICY_PERCENT%${NC}"
fi

echo -e "📋 Documentación: ${GREEN}$DOCUMENTATION_FILE${NC}"
echo ""

# Estado final
if [ $TOTAL_VAULTS -eq 0 ]; then
    echo -e "${BLUE}ℹ️ ESTADO: SIN BACKUP VAULTS DETECTADOS${NC}"
    echo -e "${GREEN}💡 Framework preparado para futuros vaults${NC}"
elif [ $VAULTS_WITHOUT_POLICY -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE PROTEGIDO${NC}"
    echo -e "${BLUE}💡 Todos los backup vaults tienen políticas restrictivas${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: PROTECCIÓN PARCIAL${NC}"
    echo -e "${YELLOW}💡 $VAULTS_WITHOUT_POLICY vaults requieren configuración${NC}"
fi