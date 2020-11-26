#!/bin/sh

red=$'\e[1;31m'
grn=$'\e[1;32m'
yel=$'\e[1;33m'
blu=$'\e[1;34m'
mag=$'\e[1;35m'
cyn=$'\e[1;36m'
end=$'\e[0m'

export AWS_DEFAULT_OUTPUT="text"

script_dir=$(dirname $0)
aws configure add-model --service-model "file://${script_dir}/codeguru-reviewer-beta.json" --service-name codeguru-beta
cp "${script_dir}/codeguru-reviewer-beta.waiters-2.json" ~/.aws/models/codeguru-beta/2020-11-26-beta/waiters-2.json

cmd="aws codeguru-beta"

clean_up () {
  if [ $should_clean_up ]
  then
    printf "\n${cyn}Cleaning up artifacts uploaded to S3...${end}\n";
    aws s3 rm --recursive s3://$bucketName/$path/
    [ ! $? -eq 0 ] && printf "\n${yel}Failed to delete artificats from S3.${end}\n";
    rm source.zip artifacts.zip
  fi
}

die () {
    echo >&2 "\n${red}Exiting with ERROR: $@${end}"
    clean_up
    exit 1
}

die_if_failed () {
    [ ! $? -eq 0 ] && die "Last operation failed."
}

sarif_jq () {
    jq '{version: "2.1.0", "$schema": "http://json.schemastore.org/sarif-2.1.0-rtm.4", runs:[{tool:{driver:{name: "CodeGuru Reviewer Security Scanner", informationUri:"https://docs.aws.amazon.com/codeguru/latest/reviewer-ug/how-codeguru-reviewer-works.html", rules:[.RecommendationSummaries[] | select (.FilePath != ".") | {id: .RecommendationId, help: {text: .Description, markdown: .Description}}]}}, results:[.RecommendationSummaries[] | select (.FilePath != ".") | {ruleId: .RecommendationId, level:"warning", locations:[{physicalLocation:{artifactLocation:{uri: .FilePath}, region:{startLine: .StartLine, endLine: .EndLine}}}], message: {text: .Description | split(".")[0]}}]}] }' $1 ;
}

sast_jq () {
    jq '{version: "3.0", scan:{type:"sast", status: "success", scanner:{id:"codeguru-reviewer", name: "CodeGuru Reviewer Security Scanner", url:"https://docs.aws.amazon.com/codeguru/latest/reviewer-ug/how-codeguru-reviewer-works.html"}, vendor:{name:"AWS CodeGuru Reviewer"}}, vulnerabilities:[.RecommendationSummaries[] | select (.FilePath != ".") | {id: .RecommendationId, category: "sast", severity:"Critical", confidence: "High", description: .Description, message: .Description | split(".")[0], identifiers:[{type: .RecommendationId | split("-")[0], value: .RecommendationId | split("-")[1], url: .Description | match(".*\\[(.*)\\]\\((https?.*)").captures[1].string, name: .RecommendationId }], location:{file:.FilePath, start_line: .StartLine, end_line: .EndLine},"scanner":{ "id":"codeguru-reviewer", "name":"CodeGuru Reviewer Security Scanner" }}] }' $1 ;
}

jenkins_issues_jq () {
    jq -c '.RecommendationSummaries[] | select (.FilePath != ".") | {fileName: .FilePath, lineStart: .StartLine, lineEnd: .EndLine, reference: .RecommendationId, message: .Description | split(".")[0], description: .Description, severity: "HIGH" }'
}

printf "\n${grn}AWS CodeGuru Reviewer Security Scanner${end}\n"

# Because they are critical to operation, be verbose about whether and where src_root and build_root were or were not found
if [ -n "$src_root" ]; then echo "Detected Java Source dir variable, src_root is set to $src_root"; fi
if [ -n "$build_root" ]; then echo "Detected Build dir variable, build_root is set to $build_root"; fi

if [ -z "$src_root" ] && [ -n "$1" ]; then src_root=$1; echo "Detected Java Source dir parameter (1st), src_root is now set to $src_root"; fi
if [ -z "$build_root" ] && [ -n "$2" ]; then build_root=$2; echo "Detected Build dir parameter (2nd), build_root is now set to $build_root"; fi

if [ -z "$src_root" ] && [ -d src/main/java ]; then src_root=src/main/java; echo "Detected Java Source dir is present, src_root is now set to $src_root"; fi
if [ -z "$build_root" ] && [ -d target ]; then build_root=target; echo "Detected Java Build dir is present, build_root is now set to $build_root"; fi

if [ -z "$build_root" ]; then die "Build artifact directory not found."; fi
if [ -z "$src_root" ]; then die "Source root not found or is not a directory."; fi

# Do the same for sha and name
if [ -n "$sha" ]; then echo "Detected sha variable, sha is set to $sha"; fi
if [ -n "$name" ]; then echo "Detected name variable, name is set to $name"; fi

if [ -z "$sha" ] && [ -n "$3" ]; then sha=$3; echo "Detected sha parameter (3rd), sha is now set to $sha"; fi
if [ -z "$name" ] && [ -n "$4" ]; then name=$4; echo "Detected name parameter (4th), name is now set to $name"; fi

if [ -z "$sha" ] && [ -n "$GITHUB_SHA" ]; then sha=$GITHUB_SHA; echo "Detected GitHub, sha is now set to $sha"; fi
if [ -z "$name" ] && [ -n "$GITHUB_REPOSITORY" ]; then name=${GITHUB_REPOSITORY//\//-}; echo "Detected GitHub, name is now set to $name"; fi

if [ -z "$sha" ] && [ -n "$CI_COMMIT_SHA" ]; then sha=$CI_COMMIT_SHA; echo "Detected GitLab, sha is now set to $sha"; fi
if [ -z "$name" ] && [ -n "$CI_PROJECT_PATH_SLUG" ]; then name=$CI_PROJECT_PATH_SLUG; echo "Detected GitLab, name is now set to $name"; fi

if [ -z "$sha" ]; then die "Commit hash not autodetected, please set sha to the commit hash before calling."; fi
if [ -z "$name" ]; then die "Repository name not autodetected, please set name variable to a unique repository name before calling. Association name could not be set."; fi

path="${name}_${sha: -7}_$(date +%s)"

printf "\nassociation name: ${yel}$name${end}   region: ${yel}$AWS_DEFAULT_REGION${end}   src-root: ${yel}$src_root${end}   build-artifact: ${yel}$build_root${end}\n"

printf "\n${cyn}Querying for the repository association '$name'...${end}\n";

associationArn=$($cmd list-repository-associations --query "RepositoryAssociationSummaries[?ProviderType=='S3Bucket' && Name=='$name'].AssociationArn | [0]")
die_if_failed

if [ $associationArn == None ]
then
    printf "${cyn}No repository association found, creating a new association...${end}\n";
    associationArn=$($cmd associate-repository --repository "{\"S3Bucket\": {\"Name\": \"$name\"}}" --query RepositoryAssociation.AssociationArn)
    die_if_failed
    printf "\nassociation-arn: ${yel}$associationArn${end}\n"
    printf "${cyn}Awaiting association complete...${end}\n";
    $cmd wait association-complete --association-arn "$associationArn"
    die_if_failed
else
  printf "\nassociation-arn: ${yel}$associationArn${end}\n"
fi

bucketName=$($cmd describe-repository-association --association-arn "$associationArn" --query RepositoryAssociation.S3RepositoryDetails.BucketName)
die_if_failed

printf "S3 bucket name: ${yel}$bucketName${end}\n"

printf "\n${cyn}Archiving source...${end}\n";
zip -r source $src_root
die_if_failed

printf "\n${cyn}Archiving build artifacts...${end}\n";
zip -j -r artifacts $build_root -i *.jar
die_if_failed

should_clean_up=true

printf "\n${cyn}Uploading source archive...${end}\n";
aws s3 cp source.zip s3://$bucketName/$path/
die_if_failed

printf "\n${cyn}Uploading the build artifact...${end}\n";
aws s3 cp artifacts.zip s3://$bucketName/$path/
die_if_failed

printf "\n${cyn}Submitting the review request...${end}\n";
CodeReviewArn=$($cmd create-code-review --name "${path}" --repository-association-arn "$associationArn" --type "{\"RepositoryAnalysis\": {\"S3BucketRepository\": {\"Name\": \"$name\",\"Details\": {\"BucketName\": \"$bucketName\",\"CodeArtifacts\": {\"BuildArtifactsObjectKey\": \"$path/artifacts.zip\", \"SourceCodeArtifactsObjectKey\": \"$path/source.zip\"}}}},\"AnalysisTypes\": [\"Security\"]}" --query CodeReview.CodeReviewArn)
die_if_failed

printf "\ncode-review-arn: ${yel}$CodeReviewArn${end}\n";
printf "\n${cyn}Awaiting results...${end}\n";
$cmd wait code-review-complete --code-review-arn $CodeReviewArn
if [ ! $? -eq 0 ]
then
  printf "\n${red}Timed out waiting for results or review failed.${end}\n";
else
  printf "\n${cyn}Fetching review results...${end}\n";
  $cmd --output json list-recommendations --code-review-arn $CodeReviewArn > codeguru-results.json
  sarif_jq < codeguru-results.json > codeguru-results.sarif.json
  sast_jq < codeguru-results.json > codeguru-results.sast.json
  jenkins_issues_jq < codeguru-results.json > codeguru-results.jenkins-json.log
fi

clean_up

printf "\n${grn}AWS CodeGuru Reviewer Security Scanner - end marker${end}\n"
