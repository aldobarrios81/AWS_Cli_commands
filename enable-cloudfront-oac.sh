#!/bin/bash
set -euo pipefail

PROFILE="xxxxxxx"
REGION="us-east-1"   # CloudFront es global, pero mantenemos coherencia

echo "=== Creando/activando Origin Access Control en CloudFront ==="

DISTS=$(aws cloudfront list-distributions \
  --profile "$PROFILE" \
  --region "$REGION" \
  --query 'DistributionList.Items[].Id' \
  --output text)

if [ -z "$DISTS" ]; then
  echo "No se encontraron distribuciones."
  exit 0
fi

for DIST_ID in $DISTS; do
  echo
  echo ">>> Procesando distribución: $DIST_ID"

  CONFIG_JSON=$(aws cloudfront get-distribution-config \
    --id "$DIST_ID" \
    --profile "$PROFILE" \
    --region "$REGION")

  ETAG=$(echo "$CONFIG_JSON" | jq -r '.ETag')
  DIST_CONFIG=$(echo "$CONFIG_JSON" | jq '.DistributionConfig')

  # Detectar orígenes S3 en cualquier región
  ORIGIN_IDS=$(echo "$DIST_CONFIG" | \
    jq -r '.Origins.Items[] | select(.DomainName | test("s3(\\.[a-z0-9-]+)?\\.amazonaws\\.com$")) | .Id')

  if [ -z "$ORIGIN_IDS" ]; then
    echo "   No hay orígenes S3 en esta distribución. Se omite."
    continue
  fi

  for ORIGIN_ID in $ORIGIN_IDS; do
    echo "   -> Origen S3: $ORIGIN_ID"

    # 🔑 Crear Origin Access Control SIN SignedHeaders
    OAC_NAME="OAC-$DIST_ID-$ORIGIN_ID"
    OAC_ID=$(aws cloudfront create-origin-access-control \
      --origin-access-control-config "Name=$OAC_NAME,Description=Auto OAC for $DIST_ID,OriginAccessControlOriginType=s3,SigningBehavior=always,SigningProtocol=sigv4" \
      --profile "$PROFILE" \
      --region "$REGION" \
      --query 'OriginAccessControl.Id' \
      --output text)

    echo "      OAC creado: $OAC_ID"

    # Asociar el OAC al origen
    DIST_CONFIG=$(echo "$DIST_CONFIG" | \
      jq --arg ORIGIN "$ORIGIN_ID" --arg OAC "$OAC_ID" '
        .Origins.Items |= map(
          if .Id == $ORIGIN then . + {OriginAccessControlId: $OAC} else . end
        )')
  done

  TMPFILE=$(mktemp)
  echo "$DIST_CONFIG" > "$TMPFILE"

  aws cloudfront update-distribution \
    --id "$DIST_ID" \
    --if-match "$ETAG" \
    --distribution-config file://"$TMPFILE" \
    --profile "$PROFILE" \
    --region "$REGION"

  rm "$TMPFILE"
  echo "   OAC habilitado en la distribución $DIST_ID."
done

echo
echo "=== Proceso completado ==="

