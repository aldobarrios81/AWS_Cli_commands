#!/usr/bin/env bash
# Uso: ./s3-public-check.sh [perfil_aws]
# Ej:  ./s3-public-check.sh azbeacons
# Si no pasas perfil, usa el default.

PROFILE=${1:-default}

echo "Perfil AWS: $PROFILE"
echo "--------------------------------------------"

# Lista todos los buckets
buckets=$(aws s3api list-buckets --query "Buckets[].Name" --output text --profile "$PROFILE")

for bucket in $buckets; do
    echo "Bucket: $bucket"
    echo "--------------------------------------------"

    # 1️⃣ Public Access Block
    pab_status=$(aws s3api get-public-access-block \
        --bucket "$bucket" \
        --query 'PublicAccessBlockConfiguration' \
        --output json \
        --profile "$PROFILE" 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo "  ⚠️  No tiene PublicAccessBlock configurado."
    else
        echo "  PublicAccessBlock: $pab_status"
        # Checar si todos los flags están en true
        for key in BlockPublicAcls IgnorePublicAcls BlockPublicPolicy RestrictPublicBuckets; do
            val=$(echo "$pab_status" | jq -r ".${key}")
            if [ "$val" != "true" ]; then
                echo "  ❌  $key está en $val"
            fi
        done
    fi

    # 2️⃣ ACLs públicas
    acl=$(aws s3api get-bucket-acl \
        --bucket "$bucket" \
        --query 'Grants[?Grantee.URI!=null].Grantee.URI' \
        --output text \
        --profile "$PROFILE" 2>/dev/null)

    if echo "$acl" | grep -q "AllUsers\|AuthenticatedUsers"; then
        echo "  ❌  ACL pública detectada: $acl"
    else
        echo "  ✅  Sin ACL pública."
    fi

    # 3️⃣ Política del bucket
    policy=$(aws s3api get-bucket-policy \
        --bucket "$bucket" \
        --query 'Policy' \
        --output text \
        --profile "$PROFILE" 2>/dev/null)

    if [ $? -eq 0 ]; then
        if echo "$policy" | grep -q '"Principal": "*"'; then
            echo "  ❌  Política permite acceso público (Principal: *)."
        else
            echo "  ✅  Política sin acceso público abierto."
        fi
    else
        echo "  (Sin política de bucket)"
    fi

    echo
done

