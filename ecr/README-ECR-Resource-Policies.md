# ECR Resource Policies - Limit Access

## Descripción
Scripts para implementar y verificar políticas restrictivas de acceso a repositorios ECR siguiendo la regla: **"Limit Access to ECR repositories with resource policies"**

## Scripts Disponibles

### 1. `limit-all-ecr-repos-metrokia.sh`
**Propósito**: Aplicar políticas restrictivas a TODOS los repositorios ECR
**Perfiles soportados**: `metrokia`, `AZLOGICA`

#### Uso:
```bash
# Para perfil metrokia
./limit-all-ecr-repos-metrokia.sh metrokia

# Para perfil AZLOGICA  
./limit-all-ecr-repos-metrokia.sh AZLOGICA
```

#### Características:
- ✅ Limita acceso solo a la cuenta específica
- ✅ Permite operaciones de container (pull/push)
- ✅ Incluye acceso restringido para Lambda
- ✅ Crea backups de políticas existentes
- ✅ Verificación automática post-aplicación

### 2. `verify-ecr-resource-policies.sh`
**Propósito**: Verificar el estado de las políticas de acceso en repositorios ECR

#### Uso:
```bash
# Para cualquier perfil
./verify-ecr-resource-policies.sh metrokia
./verify-ecr-resource-policies.sh AZLOGICA
```

#### Verificaciones:
- 🔍 Políticas restrictivas vs públicas
- 🔍 Configuraciones de seguridad adicionales
- 🔍 Puntuación de seguridad por repositorio
- 🔍 Reporte de cumplimiento

## Flujo de Trabajo Recomendado

### 1. Verificación Inicial
```bash
./verify-ecr-resource-policies.sh metrokia
./verify-ecr-resource-policies.sh AZLOGICA
```

### 2. Aplicar Políticas Restrictivas
```bash
./limit-all-ecr-repos-metrokia.sh metrokia
./limit-all-ecr-repos-metrokia.sh AZLOGICA
```

### 3. Verificación Final
```bash
./verify-ecr-resource-policies.sh metrokia
./verify-ecr-resource-policies.sh AZLOGICA
```

## Configuración de Cuentas

### Perfil metrokia
- **Account ID**: `848576886895`
- **Configuración**: Hardcodeada en el script

### Perfil AZLOGICA
- **Account ID**: Se obtiene dinámicamente
- **Configuración**: Auto-detecta usando `aws sts get-caller-identity`

## Política de Seguridad Aplicada

```json
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "AllowAccountAccessForContainerOperations",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:root"
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage", 
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:GetRepositoryPolicy"
      ]
    },
    {
      "Sid": "AllowAccountPolicyManagement",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:root"
      },
      "Action": [
        "ecr:SetRepositoryPolicy",
        "ecr:DeleteRepositoryPolicy"
      ],
      "Condition": {
        "StringEquals": {
          "aws:PrincipalType": "User"
        }
      }
    },
    {
      "Sid": "AllowLambdaReadOnlyAccess",
      "Effect": "Allow", 
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Condition": {
        "StringLike": {
          "aws:sourceArn": "arn:aws:lambda:us-east-1:ACCOUNT_ID:function:*"
        }
      }
    }
  ]
}
```

## Beneficios de Seguridad

1. **Acceso Restrictivo**: Solo la cuenta específica puede acceder
2. **Principio de Menor Privilegio**: Permisos mínimos necesarios
3. **Protección contra Acceso Público**: Elimina wildcards (*)
4. **Acceso Controlado para Lambda**: Solo funciones de la misma cuenta
5. **Gestión de Políticas**: Solo usuarios (no roles) pueden modificar políticas

## Archivos de Respaldo

Los scripts crean automáticamente backups de políticas existentes:
- Formato: `backup-policy-REPO_NAME-YYYYMMDD-HHMMSS.json`
- Ubicación: Directorio actual

## Reportes de Verificación

Cada verificación genera un reporte JSON detallado:
- Formato: `ecr-resource-policies-verification-PROFILE-YYYYMMDD-HHMM.json`
- Incluye: Estadísticas, recomendaciones, comandos de remediación

## Troubleshooting

### Error de Credenciales
```bash
# Verificar configuración
aws configure list --profile metrokia
aws configure list --profile AZLOGICA

# Verificar acceso
aws sts get-caller-identity --profile metrokia
aws sts get-caller-identity --profile AZLOGICA
```

### Sin Repositorios ECR
```bash
# Verificar en otras regiones
aws ecr describe-repositories --profile metrokia --region us-west-2
```

### Permisos Insuficientes
Asegurar que el usuario/rol tenga:
- `ecr:GetRepositoryPolicy`
- `ecr:SetRepositoryPolicy`
- `ecr:DescribeRepositories`