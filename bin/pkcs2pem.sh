#!/bin/bash
die() {
    echo -e $* >&2
    exit 1
}

usage() {
    die "usage: $(basename $0) cert.p12 key.p12\nThis will create cert.pem and key.pem"
}

convert() {
    local cert=$1; shift
    local key=$1; shift
    local cert_base=$(basename $cert .p12)
    local key_base=$(basename $key .p12)
    local cert_pem="${cert_base}.pem"
    local key_pem="${key_base}.pem"
    local key_unenc_pem="${key_base}.unencrypted.pem"

    openssl pkcs12 -passin pass: -clcerts -nokeys -out ${cert_pem} -in ${cert} || \
        die "Error converting ${cert} to ${cert_pem}"
    openssl pkcs12 -passin pass: -nocerts -out ${key_pem} -passout pass:dummy -in ${key} || \
        die "Error converting ${key} to ${key_pem}"
    # Remove fake password
    openssl rsa -passin pass:dummy -in ${key_pem} -out ${key_unenc_pem} || \
        die "Error removing passphrase from key file ${key_pem}"
}

[[ $# -eq 2 ]] || usage

CERT_P12="$1"; shift
KEY_P12="$1"; shift

convert "${CERT_P12}" "${KEY_P12}"
