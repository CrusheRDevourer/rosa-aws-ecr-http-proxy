#!/bin/sh

set -e
set -x

if [ -z "$UPSTREAM" ] ; then
  echo "UPSTREAM not set."
  exit 1
fi

if [ -z "$PORT" ] ; then
  echo "PORT not set."
  exit 1
fi

if [ -z "$RESOLVER" ] ; then
  echo "RESOLVER not set."
  exit 1
fi

if [ -z "$AWS_REGION" ] ; then
  echo "AWS_REGION not set."
  exit 1
fi

if [ -z "$AWS_USE_EC2_ROLE_FOR_AUTH" ] || [ "$AWS_USE_EC2_ROLE_FOR_AUTH" != "true" ]; then
  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY not set."
    exit 1
  fi
fi

UPSTREAM_WITHOUT_PORT=$( echo ${UPSTREAM} | sed -r "s/.*:\/\/(.*):.*/\1/g")
echo Using resolver $RESOLVER and $UPSTREAM [$(dig +short  ${UPSTREAM_WITHOUT_PORT})] as upstream.

CACHE_MAX_SIZE=${CACHE_MAX_SIZE:-75g}
echo Using cache max size $CACHE_MAX_SIZE

CACHE_KEY=${CACHE_KEY:='$uri'}
echo Using cache key $CACHE_KEY

SCHEME=http
CONFIG=/usr/local/openresty/nginx/conf/nginx.conf
SSL_CONFIG=/usr/local/openresty/nginx/conf/ssl.conf

if [ "$ENABLE_SSL" ]; then
  sed -i -e s!REGISTRY_HTTP_TLS_CERTIFICATE!"$REGISTRY_HTTP_TLS_CERTIFICATE"!g $SSL_CONFIG
  sed -i -e s!REGISTRY_HTTP_TLS_KEY!"$REGISTRY_HTTP_TLS_KEY"!g $SSL_CONFIG
  SSL_LISTEN="ssl"
  SSL_INCLUDE="include $SSL_CONFIG;"
  SCHEME="https"
fi

# Update nginx config
sed -i -e s@UPSTREAM@"$UPSTREAM"@g $CONFIG
sed -i -e s@PORT@"$PORT"@g $CONFIG
sed -i -e s@RESOLVER@"$RESOLVER"@g $CONFIG
sed -i -e s@CACHE_MAX_SIZE@"$CACHE_MAX_SIZE"@g $CONFIG
sed -i -e s@CACHE_KEY@"$CACHE_KEY"@g $CONFIG
sed -i -e s@SCHEME@"$SCHEME"@g $CONFIG
sed -i -e s@SSL_INCLUDE@"$SSL_INCLUDE"@g $CONFIG
sed -i -e s@SSL_LISTEN@"$SSL_LISTEN"@g $CONFIG

# setup ~/.aws directory
AWS_FOLDER='/aws'
echo "[default]" > ${AWS_FOLDER}/config
echo "region = $AWS_REGION" >> ${AWS_FOLDER}/config

if [ -z "$AWS_USE_EC2_ROLE_FOR_AUTH" ] || [ "$AWS_USE_EC2_ROLE_FOR_AUTH" != "true" ]; then
  echo "[default]" > ${AWS_FOLDER}/credentials
  echo "aws_access_key_id=$AWS_ACCESS_KEY_ID" >> ${AWS_FOLDER}/credentials
  echo "aws_secret_access_key=$AWS_SECRET_ACCESS_KEY" >> ${AWS_FOLDER}/credentials
fi

set +x
# add the auth token in default.conf
AUTH=$(grep  X-Forwarded-User $CONFIG | awk '{print $4}'| uniq|tr -d "\n\r")
TOKEN=$(aws ecr get-authorization-token --query 'authorizationData[*].authorizationToken' --output text)

echo $TOKEN > /tmp/token

set -x

exec "$@"
