#!/bin/sh
# Regenerates the certificates of the TLS tests. They exist only for those
# tests (a local fake server); the CA keys are not kept.
set -e
cd "$(dirname "$0")"
DAYS=36500
# Relative paths: on Windows openssl is a native program.
export MSYS_NO_PATHCONV=1
T=$(mktemp -d ./tmp.XXXXXX)
trap 'rm -rf "$T"' EXIT

ca() { # name subject
  openssl req -x509 -newkey rsa:2048 -nodes -days $DAYS -subj "/CN=$2" \
    -keyout "$T/$1.key" -out "$1.pem" 2>/dev/null
}
leaf() { # name subject ca extensions
  openssl req -newkey rsa:2048 -nodes -subj "/CN=$2" \
    -keyout "$1-key.pem" -out "$T/$1.csr" 2>/dev/null
  printf '%s\n' "$4" > "$T/$1.ext"
  openssl x509 -req -days $DAYS -in "$T/$1.csr" -CA "$3.pem" -CAkey "$T/$3.key" \
    -CAcreateserial -extfile "$T/$1.ext" -out "$1.pem" 2>/dev/null
}

ca ca 'eloquent test CA'
ca other-ca 'eloquent other test CA'
leaf server localhost ca 'subjectAltName=DNS:localhost,IP:127.0.0.1'
leaf server-other-host other.example ca 'subjectAltName=DNS:other.example'
leaf client eloquent-client ca 'extendedKeyUsage=clientAuth'
openssl pkcs8 -topk8 -v2 aes256 -passout pass:secret \
  -in client-key.pem -out client-key-encrypted.pem
