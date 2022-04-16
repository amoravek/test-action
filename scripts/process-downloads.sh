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

function verify_checksum() {
    FILE=$1
    CHECKSUM=$2

    if [[ -z $FILE ]]; then
        warning "No file given to verify checksum"
        return
    fi

    if [[ -z $CHECKSUM ]]; then
        warning "No checksum given"
        return
    fi

    CHECKSUM_LENGTH=${#CHECKSUM}
    
    if [[ $CHECKSUM_LENGTH == "32" ]]; then # md5
        CALCULATED_CHECKSUM=$(md5sum "$TARGET_FILE_NAME" | cut -d " " -f 1)
    elif [[ $CHECKSUM_LENGTH == "40" ]]; then # sha-1
        CALCULATED_CHECKSUM=$(sha1sum "$TARGET_FILE_NAME" | cut -d " " -f 1)
    elif [[ $CHECKSUM_LENGTH == "64" ]]; then # sha-256
        CALCULATED_CHECKSUM=$(sha256sum "$TARGET_FILE_NAME" | cut -d " " -f 1)
    else
        error "Wrong checksum size!"
        exit 1
    fi

    if [[ "$CHECKSUM" != "$CALCULATED_CHECKSUM" ]]; then
        error "Checksum validation failed for file $TARGET_FILE_NAME! declared: [$CHECKSUM] vs. calculated: [$CALCULATED_CHECKSUM]"
        exit 1
    else
        info "Checksum validation successfull"
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

        while : ; do

            if [[ $GIT_TAGS == *"${ARTIFACT_NAME}_${VERSION}"* ]]; then
                info "Artifact $ARTIFACT_NAME $VERSION already processed; skipping"
                break
            fi

            info "Downloading $ARTIFACT_NAME $VERSION from $FINAL_URI ..."

            CHECKSUM_HEADERS=""

            URI_LOWERCASE=${a,,}

            debug "URI_LOWERCASE: $URI_LOWERCASE"

            if [[ "$URI_LOWERCASE" == "http"* ]]; then # http download

            elif [[ "$URI_LOWERCASE" == "scp"* ]]; then # scp download

            else
                warning "Error downloading $ARTIFACT_NAME ($TARGET_FILE_NAME)"
                break
            fi

            TARGET_FILE_NAME=$(curl --silent --show-error --fail --head --insecure --location $FINAL_URI | sed -r '/filename=/!d;s/.*filename=(.*)$/\1/' | tr -d '\r')

            debug "TARGET_FILE_NAME: $TARGET_FILE_NAME"

            curl --silent --show-error --fail --remote-name --insecure --location $FINAL_URI > /dev/null

            if [ ! $? -eq 0 ]; then
                warning "Error downloading $ARTIFACT_NAME ($TARGET_FILE_NAME)"
                break
            else
                info "File $TARGET_FILE_NAME successfully downloaded"
            fi

            CHECKSUM_HEADERS=""

            if [[ $DECLARED_MD5 != "null" ]]; then
                verify_checksum $TARGET_FILE_NAME $DECLARED_MD5
                CHECKSUM_HEADERS="$CHECKSUM_HEADERS --header X-Checksum:$DECLARED_MD5"
            fi

            if [[ $DECLARED_SHA1 != "null" ]]; then
                verify_checksum $TARGET_FILE_NAME $DECLARED_SHA1
                CHECKSUM_HEADERS="$CHECKSUM_HEADERS --header X-Checksum-Sha1:${DECLARED_SHA1}"
            fi

            if [[ $DECLARED_SHA256 != "null" ]]; then
                verify_checksum $TARGET_FILE_NAME $DECLARED_SHA256
                CHECKSUM_HEADERS="$CHECKSUM_HEADERS --header X-Checksum-Sha256:${DECLARED_SHA256}"
            fi

            # base=$(basename -- "$TARGET_FILE_NAME")
            # ext="${base#*.}"
            # name="${base%%.*}"

            # if [[ "$name" == "$ext" ]]; then
            #     targetTARGET_FILE_NAME=$name-$version
            # else
            #     targetTARGET_FILE_NAME=$name-$version.$ext
            # fi

            # targetUrl="${ARTIFACTORY_BASE_URL}/${ARTIFACTORY_REPO}/${targetTARGET_FILE_NAME}"
            # info "Uploading to $targetUrl ... "
            # curl --silent --show-error --fail --insecure --user ${ARTIFACTORY_USER}:${ARTIFACTORY_PASSWORD} ${CHECKSUM_HEADERS} --request PUT "$targetUrl" --upload-file ${TARGET_FILE_NAME} > /dev/null

            info "Creating tag ${ARTIFACT_NAME}_${VERSION}"
            # git tag ${ARTIFACT_NAME}_${VERSION}

            break
        done

        i=$(($i+1))
    done

    info "Pushing tags"
    # git push --tags

    info "Success"
done
