#!/usr/bin/env bash

set -e +o history

ARTIFACTS_BATCH_FILE=${1:-artifacts.yaml}
VENDOR_METADATA_FILE=$2
ARTIFACTORY_USER=$3
ARTIFACTORY_PASSWORD=$4
ARTIFACTORY_BASE_URL=$5
ARTIFACTORY_REPO=$6

SCRIPT_FILE="$0"

function error() {
    echo "::error file=${SCRIPT_FILE}::$1"
}

function warning() {
    echo "::warning file=${SCRIPT_FILE}::$1"
}

function info() {
    echo "::notice file=${SCRIPT_FILE}::$1"
}

function debug() {
    echo "::debug file=${SCRIPT_FILE}::$1"
}

function die() {
    error "$1"
    exit 1
}

function check_inputs() {
    if [ -z $ARTIFACTS_BATCH_FILE ]; then
        die "Missing artifacts batch file ($ARTIFACTS_BATCH_FILE_NAME)"
    fi

    if [ -z $VENDOR_METADATA_FILE ]; then
        die "Missing vendor metadata file"
    fi

    if [ -z $ARTIFACTORY_USER ]; then
        die "Missing Artifactory user"
    fi

    if [ -z $ARTIFACTORY_PASSWORD ]; then
        die "Missing Artifactory password/token"
    fi

    if [ -z $ARTIFACTORY_BASE_URL ]; then
        die "Missing Artifactory base URL"
    fi

    if [ -z $ARTIFACTORY_REPO ]; then
        die "Missing Artifactory repository name"
    fi

    if [[ ! -f "$ARTIFACTS_BATCH_FILE" ]]; then
        die "File $ARTIFACTS_BATCH_FILE_NAME not found"
    fi

    if [[ ! -f "$VENDOR_METADATA_FILE" ]]; then
        die "File $VENDOR_METADATA_FILE not found"
    fi
}

check_inputs

echo "ARTIFACTS_BATCH_FILE: $ARTIFACTS_BATCH_FILE"
echo "VENDOR_METADATA_FILE: $VENDOR_METADATA_FILE"
echo "ARTIFACTORY_USER: $ARTIFACTORY_USER"
echo "ARTIFACTORY_BASE_URL: $ARTIFACTORY_BASE_URL"
echo "ARTIFACTORY_REPO: $ARTIFACTORY_REPO"

declare -A URI_TEMPLATES

for ARTIFACT_NAME in $(yq e ".spec.artifacts | keys" $VENDOR_METADATA_FILE | awk '{print $2}'); do
    URI_TEMPLATE=$(yq e ".spec.artifacts.${ARTIFACT_NAME}.uriTemplate" $VENDOR_METADATA_FILE)
    URI_TEMPLATES[$ARTIFACT_NAME]=$URI_TEMPLATE
    debug "URI template: $ARTIFACT_NAME -> $URI_TEMPLATE"
done

# Retrieve Git tags
DIR=$(pwd)
cd $(dirname $VENDOR_METADATA_FILE})
GIT_TAGS=$(git tag --list)
cd $DIR

declare -A ARTIFACT_VERSIONS

for ARTIFACT_NAME in $(yq e ".spec.artifacts | keys" $ARTIFACTS_BATCH_FILE | awk '{print $2}'); do

    if [[ "x${URI_TEMPLATES[$ARTIFACT_NAME]}" == "x" ]]; then
        die "Missing URI pattern for artifact $ARTIFACT_NAME"
    fi

    VERSIONS_COUNT=$(yq e ".spec.artifacts.${ARTIFACT_NAME} | length" $ARTIFACTS_BATCH_FILE)
    i=0

    while [ $i -ne $VERSIONS_COUNT ]; do
        VERSION=$(yq e ".spec.artifacts.${ARTIFACT_NAME}[$i].version" $ARTIFACTS_BATCH_FILE)
        DECLARED_SHA256=$(yq e ".spec.artifacts.${ARTIFACT_NAME}[$i].sha256" $ARTIFACTS_BATCH_FILE)
        DECLARED_SHA1=$(yq e ".spec.artifacts.${ARTIFACT_NAME}[$i].sha1" $ARTIFACTS_BATCH_FILE)
        DECLARED_MD5=$(yq e ".spec.artifacts.${ARTIFACT_NAME}[$i].md5" $ARTIFACTS_BATCH_FILE)
        FINAL_URI=$(eval echo "${URI_TEMPLATES[$ARTIFACT_NAME]}")

        debug "VERSION: $VERSION"
        debug "DECLARED_SHA256: $DECLARED_SHA256"
        debug "DECLARED_SHA1: $DECLARED_SHA1"
        debug "DECLARED_MD5: $DECLARED_MD5"
        debug "FINAL_URI: $FINAL_URI"

        if [[ $GIT_TAGS == *"${ARTIFACT_NAME}_${VERSION}"* ]]; then
            info "Artifact $ARTIFACT_NAME $VERSION already processed; skipping"
            i=$(($i+1))
            continue
        fi

        info "===> Downloading $ARTIFACT_NAME $VERSION from $FINAL_URI ..."

        info "Creating tag ${ARTIFACT_NAME}_${VERSION}"
        # git tag ${ARTIFACT_NAME}_${VERSION}

        i=$(($i+1))
    done

    info "Pushing tags"
    # git push --tags
done

# i=0
# while [[ $i < $productVersionsCount ]]; do
#     productName=$(yq e ".spec.artifacts[$i].name" $ARTIFACTS_BATCH_FILE)
#     version=$(yq e ".spec.artifacts[$i].version" $ARTIFACTS_BATCH_FILE)
#     declaredSha256=$(yq e ".spec.artifacts[$i].sha256" $ARTIFACTS_BATCH_FILE)
#     declaredSha1=$(yq e ".spec.artifacts[$i].sha1" $ARTIFACTS_BATCH_FILE)
#     declaredMd5=$(yq e ".spec.artifacts[$i].md5" $ARTIFACTS_BATCH_FILE)
#     finalUri=$(eval echo "${URI_TEMPLATES[$productName]}")

#     info "===> Downloading '$productName' from '$finalUri' ..."

#     checksumHeaders=""

#     fileName=$(curl --silent --show-error --fail --head --insecure --location $finalUri | sed -r '/filename=/!d;s/.*filename=(.*)$/\1/' | tr -d '\r')
#     curl --silent --show-error --fail --remote-name --insecure --location $finalUri > /dev/null

#     if [ ! $? -eq 0 ]; then
#         warning "### Error downloading '$productName' ($fileName)"
#         continue
#     fi

#     if [[ $declaredSha != "null" ]]; then
#         echo -n "Verifying checksum ... "
#         sha256Sum=$(sha256sum "$fileName" | cut -d " " -f 1)
#         sha1Sum=$(sha1sum "$fileName" | cut -d " " -f 1)
#         md5Sum=$(md5sum "$fileName" | cut -d " " -f 1)

#         if [[ "$declaredSha" != "$sha256Sum" ]]; then
#             warning "### Invalid checksum - $productName:$version ($fileName): declared: [$declaredSha] real: [$sha]"
#             continue
#         else
#             echo "OK"
#             checksumHeaders="--header X-Checksum-Sha256:${sha256Sum} --header X-Checksum-Sha1:${sha1Sum} --header X-Checksum:${md5Sum}"
#             # checksumHeaders="--header X-Checksum-Sha256:${declaredSha}"
#         fi
#     else
#         info "No checksum provided to verify"
#     fi

#     base=$(basename -- "$fileName")
#     ext="${base#*.}"
#     name="${base%%.*}"

#     if [[ "$name" == "$ext" ]]; then
#         targetFileName=$name-$version
#     else
#         targetFileName=$name-$version.$ext
#     fi

#     targetUrl="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_REPO}/${targetFileName}"
#     info "Uploading to $targetUrl ... "
#     curl --silent --show-error --fail --insecure --user ${ARTIFACTORY_USER}:${ARTIFACTORY_PASSWORD} ${checksumHeaders} --request PUT "$targetUrl" --upload-file ${fileName} > /dev/null

#     i=$(($i+1))
# done

