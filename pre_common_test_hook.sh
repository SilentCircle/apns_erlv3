#!/bin/bash

set -e

echo $0: Start

(( $# == 2 ))

NODE_NAME=$1; shift
TEST_SPEC_NAME=$1; shift

# Get the cert generation tools
echo $0: Get fake cert tools and generate certs in $(pwd)/tools/apns_tools/CA
./get_apns_tools.sh

# Generate the test spec
echo $0: Generate test spec ${TEST_SPEC_NAME} for node ${NODE_NAME}
./template_nodename.sh ${NODE_NAME} ${TEST_SPEC_NAME}.src ${TEST_SPEC_NAME}
