#!/usr/bin/env bash

ARTIFACTS_BATCH_FILE_NAME=artifacts.yaml

set -e +o history

artifactBatchFile=$1
vendorMetadataFile=$2
artifactoryUser=$1
artifactoryPassword=$2
artifactoryBaseUrl=$3
artifactoryRepo=$4

function err() {
    echo "### $1"
    exit 1
}

function msg() {
    echo "===> $1"
}

function check_inputs() {
    if [ -z $artifactBatchFile ]; then
        err "Missing artifacts batch file ($ARTIFACTS_BATCH_FILE_NAME)"
    fi

    if [ -z $vendorMetadataFile ]; then
        err "Missing vendor metadata file"
    fi

    if [ -z $artifactoryUser ]; then
        err "Missing Artifactory user"
    fi

    if [ -z $artifactoryPassword ]; then
        err "Missing Artifactory password/token"
    fi

    if [ -z $artifactoryBaseUrl ]; then
        err "Missing Artifactory base URL"
    fi

    if [ -z $artifactoryRepo ]; then
        err "Missing Artifactory repository name"
    fi
}

check_inputs

declare -A uriTemplates
artifactCount=0

for artifactName in $(yq e '.spec.artifacts | keys' $vendorMetadataFile | awk '{print $2}'); do
    uriTemplate=$(yq e ".spec.artifacts.${artifactName}.uriTemplate" $vendorMetadataFile)

    existing=uriTemplates[$artifactName]

    # product name duplicity check
    if [[ ! -z $existing ]]; then
        err "Duplicate artifact name \'$artifactName\' in $vendorMetadataFile" 
    fi

    uriTemplates[$artifactName]=$uriTemplate

    artifactCount=$(($artifactCount+1))
done

declare -A artifactVersions

for artifactName in $(yq e '.spec.artifacts | keys' $artifactBatchFile | awk '{print $2}'); do

    for version in $(yq e '.spec.artifacts[].${artifactName}' $artifactBatchFile | awk '{print $2}'); do

    productName=$(yq e ".spec.artifacts[$i].name" $artifactBatchFile)
    version=$(yq e ".spec.artifacts[$i].version" $artifactBatchFile)
    declaredSha256=$(yq e ".spec.artifacts[$i].sha256" $artifactBatchFile)
    declaredSha1=$(yq e ".spec.artifacts[$i].sha1" $artifactBatchFile)
    declaredMd5=$(yq e ".spec.artifacts[$i].md5" $artifactBatchFile)
    finalUri=$(eval echo "${uriTemplates[$productName]}")

done


productVersionsCount=$(yq e '.spec.artifacts | length' $artifactBatchFile)



i=0
while [[ $i < $productVersionsCount ]]; do
    productName=$(yq e ".spec.artifacts[$i].name" $artifactBatchFile)
    version=$(yq e ".spec.artifacts[$i].version" $artifactBatchFile)
    declaredSha256=$(yq e ".spec.artifacts[$i].sha256" $artifactBatchFile)
    declaredSha1=$(yq e ".spec.artifacts[$i].sha1" $artifactBatchFile)
    declaredMd5=$(yq e ".spec.artifacts[$i].md5" $artifactBatchFile)
    finalUri=$(eval echo "${uriTemplates[$productName]}")

    echo "===> Downloading '$productName' from '$finalUri' ..."

    checksumHeaders=""

    fileName=$(curl --silent --show-error --fail --head --insecure --location $finalUri | sed -r '/filename=/!d;s/.*filename=(.*)$/\1/' | tr -d '\r')
    curl --silent --show-error --fail --remote-name --insecure --location $finalUri > /dev/null

    if [ ! $? -eq 0 ]; then
        echo "### Error downloading '$productName' ($fileName)"
        continue
    fi

    if [[ $declaredSha != "null" ]]; then
        echo -n "Verifying checksum ... "
        sha256Sum=$(sha256sum "$fileName" | cut -d " " -f 1)
        sha1Sum=$(sha1sum "$fileName" | cut -d " " -f 1)
        md5Sum=$(md5sum "$fileName" | cut -d " " -f 1)

        if [[ "$declaredSha" != "$sha256Sum" ]]; then
            echo "### Invalid checksum - $productName:$version ($fileName): declared: [$declaredSha] real: [$sha]"
            continue
        else
            echo "OK"
            checksumHeaders="--header X-Checksum-Sha256:${sha256Sum} --header X-Checksum-Sha1:${sha1Sum} --header X-Checksum:${md5Sum}"
            # checksumHeaders="--header X-Checksum-Sha256:${declaredSha}"
        fi
    else
        echo "No checksum provided to verify"
    fi

    base=$(basename -- "$fileName")
    ext="${base#*.}"
    name="${base%%.*}"

    if [[ "$name" == "$ext" ]]; then
        targetFileName=$name-$version
    else
        targetFileName=$name-$version.$ext
    fi

    targetUrl="${artifactoryBaseUrl}/${artifactoryRepo}/${targetFileName}"
    echo "Uploading to $targetUrl ... "
    curl --silent --show-error --fail --insecure --user ${artifactoryUser}:${artifactoryPassword} ${checksumHeaders} --request PUT "$targetUrl" --upload-file ${fileName} > /dev/null

    i=$(($i+1))
done

