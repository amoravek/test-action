#!/usr/bin/env bash

set -x -e +o history

# artifactBatchFile=$1
# vendorMetadataFile=$2
artifactoryUser=$1
artifactoryPassword=$2
artifactoryBaseUrl=$3
artifactoryRepo=$4

productCount=$(yq e '.spec.artifacts | length' vendor-metadata.yaml)

echo "$productCount products detected"

declare -A uriTemplates

function checkVersions {
    echo "=== checking versions ============"
    yq -V
    echo
    curl -V
    echo "=================================="
}

checkVersions

i=0
while [[ $i < $productCount ]]; do
    productName=$(yq e ".spec.artifacts[$i].name" vendor-metadata.yaml)
    uriTemplate=$(yq e ".spec.artifacts[$i].uriTemplate" vendor-metadata.yaml)

    echo "productName[$i]: $productName"
    echo "uriTemplate[$i]: $uriTemplate"

    uriTemplates[$productName]=$uriTemplate

    i=$(($i+1))
done

productVersionsCount=$(yq e '.spec.artifacts | length' ./artifacts.yaml)

declare -A productVersions

i=0
while [[ $i < $productVersionsCount ]]; do
    productName=$(yq e ".spec.artifacts[$i].name" ./artifacts.yaml)
    version=$(yq e ".spec.artifacts[$i].version" ./artifacts.yaml)
    declaredSha=$(yq e ".spec.artifacts[$i].sha256" ./artifacts.yaml)
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

