#!/bin/bash

set -o errtrace -o nounset -o pipefail -o errexit

: ${SKIP_CLEAN_CHECK=""}

# Enable build on Travis as well as on GH Actions
set +u
if test "${GITHUB_WORKFLOW}"; then
    BRANCH=${GITHUB_HEAD_REF}
    BUILD_DIR=${GITHUB_WORKSPACE}
    BUILD_NUMBER="${GITHUB_WORKFLOW}-${GITHUB_RUN_ID}-${GITHUB_RUN_NUMBER}"
    CI_SERVER="Github"
    PULL_REQUEST=$(test "${GITHUB_HEAD_REF}" && echo "true" || echo "false")
    # JDK_VERSION is set by GH Action
    # RUNNER_OS is set by GH Action
elif test "${TRAVIS_BRANCH}"; then
    BRANCH=${TRAVIS_BRANCH}
    BUILD_NUMBER=${TRAVIS_BUILD_NUMBER}
    BUILD_DIR=${TRAVIS_BUILD_DIR}
    CI_SERVER="Travis"
    PULL_REQUEST=${TRAVIS_PULL_REQUEST:-"false"}
    JDK_VERSION=${TRAVIS_JDK_VERSION}
    RUNNER_OS="ubuntu-latest"
elif test "${IS_DOCKER}"; then
    # All environment must be injected by `docker run`
    :
else
    echo "Cannot determine CI Server (Travis or Github)" >&2
    exit 1
fi
set -u

# Goto directory of this script
cd "$(dirname "${BASH_SOURCE[0]}")"

version_info () {
  echo "############################################"
  echo "#                                          #"
  echo "#        Version Check                     #"
  echo "#                                          #"
  echo "############################################"
  ./gradlew --no-daemon --version
}

cleaning () {
  echo "############################################"
  echo "#                                          #"
  echo "#        Cleaning                          #"
  echo "#                                          #"
  echo "############################################"
  ./gradlew --no-daemon clean
}

dependency_info() {
  echo "############################################"
  echo "#                                          #"
  echo "#        Check for dependency updates      #"
  echo "#                                          #"
  echo "############################################"
  ./gradlew --no-daemon -b init.gradle dependencyUpdates
  ./gradlew --no-daemon dependencyUpdates
}

unit_tests () {
  echo "############################################"
  echo "#                                          #"
  echo "#        Unit testing                      #"
  echo "#                                          #"
  echo "############################################"
  if [ "${BRANCH}" == "ng" ] || [ "${BRANCH}" == "main-2.x" ] ; then
    echo "skipping tests for now"
  else
    ./gradlew --no-daemon test --info
  fi
}

integration_tests () {
  echo "############################################"
  echo "#                                          #"
  echo "#        Integration testing               #"
  echo "#                                          #"
  echo "############################################"
  if [ "${BRANCH}" == "ng" ] || [ "${BRANCH}" == "main-2.x" ] ; then
    echo "skipping tests for now"
  else
      TEMPLATES='Arc42DE Arc42EN Arc42ES'
      for TEMPLATE in ${TEMPLATES}; do
        echo "### ${TEMPLATE}"
        TEST_DIR="build/${TEMPLATE}_test"

        ./gradlew --no-daemon -b init.gradle "init${TEMPLATE}" -PnewDocDir="${TEST_DIR}"
        ./bin/doctoolchain "${TEST_DIR}" generatePDF
        ./bin/doctoolchain "${TEST_DIR}" generateHTML
        # ./bin/doctoolchain "${TEST_DIR}" publishToConfluence

        echo "#### check for html result"
        # if [ ! -f "${TEST_DIR}"/build/html5/arc42-template.html ]; then exit 1; fi
        echo "#### check for pdf result"
        # if [ ! -f "${TEST_DIR}"/build/pdf/arc42-template.pdf ]; then exit 1; fi
      done
  fi
}

check_for_clean_worktree() {
  echo "############################################"
  echo "#                                          #"
  echo "#        Check for clean worktree          #"
  echo "#                                          #"
  echo "############################################"
  if test "${SKIP_CLEAN_CHECK}"; then
      echo "Skipping check!!!"
  else
    # To be executed as latest possible step, to ensures that there is no
    # uncommitted code and there are no untracked files, which means .gitignore is
    # complete and all code is part of a reviewable commit.
    GIT_STATUS="$(git status --porcelain)"
    if [[ ${GIT_STATUS} ]]; then
      echo "Your worktree is not clean, there is either uncommitted code or there are untracked files:"
      echo "${GIT_STATUS}"
      exit 1
    fi
  fi
}

create_doc () {
  echo "############################################"
  echo "#                                          #"
  echo "#        Create documentation              #"
  echo "#                                          #"
  echo "############################################"
  echo "BRANCH=${BRANCH}"
  if [ "${BRANCH}" == "ng" ] || [ "${BRANCH}" == "main-2.x" ] ; then
    echo ">>> exportMarkdown"
    ./dtcw local exportMarkdown
    echo ">>> exportChangelog"
    ./dtcw local exportChangeLog
    echo ">>> exportContributors"
    ./dtcw local exportContributors
    echo ">>> generateSite"
    ./dtcw local generateSite --stacktrace
    [ -d docs ] || mkdir docs
    cp -r build/microsite/output/. docs/.
#    [ -d  docs/htmlchecks ] || mkdir docs/htmlchecks
#    cp -r build/docs/report/htmlchecks/. docs/htmlchecks/.

  else
    ./gradlew --no-daemon exportMarkdown exportChangeLog exportContributors generateHTML htmlSanityCheck --stacktrace && ./copyDocs.sh
  fi
}

publish_doc () {
  echo "publish_doc"
  # Take from and modified http://sleepycoders.blogspot.de/2013/03/sharing-travis-ci-generated-files.html
  # ensure publishing doesn't run on pull requests, only when token is available and only on JDK11 matrix build and on master or a travisci test branch
  if [ "${PULL_REQUEST}" == "false" ] && [ -n "${GH_TOKEN}" ] && { [ "${JDK_VERSION}" == "openjdk11" ] || { [ "${JDK_VERSION}" == "11-adopt" ] && [ "${RUNNER_OS}" == "ubuntu-latest" ]; }; } && { [ "${BRANCH}" == "travisci" ] || [ "${BRANCH}" == "master" ] || [ "${BRANCH}" == "ng" ] || [ "${BRANCH}" == "main-1.x" ] || [ "${BRANCH}" == "main-2.x" ]; } ; then
    echo "############################################"
    echo "#                                          #"
    echo "#        Publish documentation             #"
    echo "#                                          #"
    echo "############################################"
    echo -e "Starting to update gh-pages\n"

    #go to home and setup git
    cd "${HOME}"
    git config --global user.email "travis@travis-ci.org"
    git config --global user.name "Travis"

    #using token clone gh-pages branch
    git clone --quiet --branch=gh-pages "https://${GH_TOKEN}@github.com/${TRAVIS_REPO_SLUG}.git" gh-pages > /dev/null

    if [ "${BRANCH}" == "master" ] || [ "${BRANCH}" == "main-1.x" ] ; then
      #go into directory and copy data we're interested in to that directory
      cd gh-pages
      rm -rf v1.3.x/*
      cp -Rf "${BUILD_DIR}"/docs/* v1.3.x/.
    fi
    if [ "${BRANCH}" == "ng" ] || [ "${BRANCH}" == "main-2.x" ] ; then
      #go into directory and copy data we're interested in to that directory
      cd gh-pages
      rm -rf v2.0.x/*
      cp -Rf "${BUILD_DIR}"/build/microsite/output/* v2.0.x/.
    fi

    #add, commit and push files
    git add -f .
    git commit -m "${CI_SERVER} build '${BUILD_NUMBER}' pushed to gh-pages"
    git push -fq origin gh-pages > /dev/null

    echo -e "Done publishing to gh-pages.\n"
  fi
}

version_info
cleaning
dependency_info
#unit_tests
#integration_tests
check_for_clean_worktree
create_doc
publish_doc
