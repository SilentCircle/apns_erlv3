#!/bin/bash

set -e

APNS_TOOLS_REPO=https://github.com/SilentCircle/apns_tools.git

TEST_SUITE_DATA=test/apns_erlv3_SUITE_data
TEST_SUITE_DIR=_build/test/lib/apns_erlv3/${TEST_SUITE_DATA}

TOOLS_DIR=tools/apns_tools
CA_DIR=${TOOLS_DIR}/CA
AUTH_KEY_DIR=${TOOLS_DIR}/apns_auth_keys


die() {
    echo $* >&2
    exit 1
}

upstream_changed() {
    remote_commit=$(git rev-parse 'FETCH_HEAD^{commit}')
    local_commit=$(git rev-parse 'refs/heads/master^{commit}')
    test $local_commit != $remote_commit
}

get_tools() {
    local upstream_did_change=false

    mkdir -p tools
    pushd tools > /dev/null 2>&1

    if [[ -d apns_tools ]]; then
        cd apns_tools
        git checkout -q master
        git fetch -q origin master
        if upstream_changed; then
            git merge --ff FETCH_HEAD
            upstream_did_change=true
        fi
    else
        upstream_did_change=true
        git clone ${APNS_TOOLS_REPO}
        cd apns_tools
        git checkout -q master
    fi

    popd > /dev/null 2>&1
    $upstream_did_change
}

generate_new_certs() {
    local rc=0

    pushd tools/apns_tools > /dev/null 2>&1
    ./fake_apple_certs.sh
    rc=$?
    popd > /dev/null 2>&1
    return $rc
}

assert_dir_exists() {
    local dir="$1"; shift

    [[ -d "$dir" ]] || die "Expected $dir to exist"
}

copy_cert_data() {
    assert_dir_exists "${CA_DIR}"

    mkdir -p ${TEST_SUITE_DIR}
    find ${TEST_SUITE_DIR} -name '*.pem' | xargs rm -f

    cp ${CA_DIR}/*.pem ${TEST_SUITE_DIR}/

    for dir in $CA_DIR ${CA_DIR}/WWDRCA ${CA_DIR}/ISTCA2G1; do
        cp $dir/{certs,private}/*.pem ${TEST_SUITE_DIR}/
    done
}

copy_auth_key_data() {
    assert_dir_exists "${AUTH_KEY_DIR}"

    mkdir -p ${TEST_SUITE_DIR}
    find ${TEST_SUITE_DIR} -name '*.p8' | xargs rm -f

    cp ${AUTH_KEY_DIR}/*.p8 ${TEST_SUITE_DIR}/
}

if get_tools; then
    generate_new_certs || die "Error generating new certs"
else
    echo "Not generating new certs because upstream has not changed."
fi

copy_cert_data
copy_auth_key_data

