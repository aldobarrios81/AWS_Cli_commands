# Reporte IAM Instance Profiles - EC2 - ancla

**Fecha**: Sun Oct  5 19:16:25 -05 2025
**Región**: us-east-1
**Account ID**: 621394757845

## Resumen Ejecutivo

### Instancias EC2 Procesadas
- **Total instancias**: 2
- **Con perfil IAM**: 1
- **Sin perfil IAM**: 1
- **Perfiles adjuntados**: 1
- **Instancias detenidas disponibles**: 1

## Configuraciones Implementadas

### ✅ Perfiles IAM Adjuntados
- Perfil por defecto usado: EC2-BasicInstanceProfile-ancla
- Instancias configuradas: 1
- Acceso seguro a servicios AWS sin credenciales hardcoded

### 🔍 Políticas Recomendadas por Perfil
```json
{
  "CloudWatch": "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  "SSM": "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  "S3ReadOnly": "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}
```

## Comandos de Verificación

### Verificar perfiles de instancia
```bash
# Listar instancias con sus perfiles IAM
aws ec2 describe-instances --profile ancla --region us-east-1 \
    --query 'Reservations[].Instances[].[InstanceId,IamInstanceProfile.Arn,Tags[?Key==`Name`].Value|[0]]' \
    --output table

# Verificar perfil específico
aws iam get-instance-profile --instance-profile-name PROFILE_NAME --profile ancla

# Ver roles asociados a perfil
aws iam get-instance-profile --instance-profile-name PROFILE_NAME --profile ancla \
    --query 'InstanceProfile.Roles[].RoleName' --output text
```

### Adjuntar perfil a instancia manualmente
```bash
# Para instancia detenida
aws ec2 associate-iam-instance-profile \
    --instance-id i-xxxxxxxxx \
    --iam-instance-profile Name=PROFILE_NAME \
    --profile ancla --region us-east-1

# Para instancia corriendo (requiere reinicio)
aws ec2 stop-instances --instance-ids i-xxxxxxxxx --profile ancla --region us-east-1
# Esperar que se detenga
aws ec2 associate-iam-instance-profile \
    --instance-id i-xxxxxxxxx \
    --iam-instance-profile Name=PROFILE_NAME \
    --profile ancla --region us-east-1
aws ec2 start-instances --instance-ids i-xxxxxxxxx --profile ancla --region us-east-1
```

## Mejores Prácticas

### 1. Principio de Menor Privilegio
- Crear perfiles específicos por función (web, db, monitoring)
- Adjuntar solo políticas necesarias
- Revisar permisos regularmente

### 2. Perfiles Comunes Recomendados
```bash
# Servidor web básico
- CloudWatchAgentServerPolicy
- AmazonS3ReadOnlyAccess (para assets)

# Servidor de base de datos
- CloudWatchAgentServerPolicy
- AmazonSSMManagedInstanceCore

# Servidor de procesamiento
- CloudWatchAgentServerPolicy
- AmazonS3FullAccess (bucket específico)
- AmazonSQSFullAccess (queue específica)
```

### 3. Monitoreo y Auditoria
- CloudTrail para auditar cambios de perfiles
- Config Rules para verificar cumplimiento
- Alarmas para instancias sin perfil

### 4. Automatización
- Launch Templates con perfiles preconfigurados
- Auto Scaling Groups con perfiles por defecto
- Terraform/CloudFormation para IaC

## Scripts de Creación de Perfiles Personalizados

### Perfil para Servidor Web
```bash
# Crear rol
aws iam create-role --role-name WebServerRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "ec2.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

# Adjuntar políticas
aws iam attach-role-policy --role-name WebServerRole \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

# Crear perfil de instancia
aws iam create-instance-profile --instance-profile-name WebServerProfile

# Asociar rol con perfil
aws iam add-role-to-instance-profile \
    --instance-profile-name WebServerProfile \
    --role-name WebServerRole
```

