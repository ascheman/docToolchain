#!/bin/bash

set -eu

docker run \
  -v $PWD:/wrk \
  -v $HOME/.gradle:/root/.gradle \
  -w /wrk \
  -ti --rm \
  -e IS_DOCKER=true \
  -e BRANCH=$(git rev-parse --abbrev-ref HEAD) \
  -e BUILD_NUMBER=0 \
  -e BUILD_DIR="/wrk" \
  -e CI_SERVER="Docker" \
  -e PULL_REQUEST="false" \
  -e JDK_VERSION=openjdk-17 \
  -e RUNNER_OS="debian-latest" \
  -e SKIP_CLEAN_CHECK=true \
  ascheman/doctoolchain-base "${@}"
