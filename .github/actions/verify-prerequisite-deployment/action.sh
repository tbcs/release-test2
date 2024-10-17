#!/usr/bin/env bash
set -eu

if [ -z "$PREREQUISITE_ENVIRONMENT" ]; then
  echo "::notice::Check passed: No prerequisite deployment is required for deployment to " \
    "'$DEPLOYMENT_ENVIRONMENT'."
  exit 0
fi

repo_owner=$(echo "${GITHUB_REPOSITORY}" | cut -d'/' -f1)
repo_name=$(echo "${GITHUB_REPOSITORY}" | cut -d'/' -f2)

graphql_query='
query ($repoOwner: String!, $repoName: String!, $environment: String!) {
  repository(owner: $repoOwner, name: $repoName) {
    deployments(
      first: 100
      environments: [$environment]
      orderBy: {field: CREATED_AT, direction: DESC}
    ) {
      nodes {
        databaseId
        createdAt
        latestStatus {
          state
        }
        commitOid
        payload
      }
    }
  }
}
'

jq_query='
.data.repository.deployments.nodes
| map(select(.latestStatus.state == "INACTIVE" or .latestStatus.state == "SUCCESS"))
| map(select(.commitOid | startswith($version)))
| map(select((.payload // "") | contains($deploymentPayloadMarker)))
| first | .createdAt // ""
'

latest_deployment=$(gh api graphql \
  -F repoOwner="$repo_owner" \
  -F repoName="$repo_name" \
  -F environment="$PREREQUISITE_ENVIRONMENT" \
  -f query="$graphql_query" \
  | jq -r \
    --arg version "$VERSION" \
    --arg deploymentPayloadMarker "$DEPLOYMENT_PAYLOAD_MARKER" "$jq_query")

if [ -n "$latest_deployment" ]; then
  echo "::notice::Version '$VERSION' has been previously deployed to" \
    "environment '$PREREQUISITE_ENVIRONMENT' at $latest_deployment."
  exit 0
else
  echo "::error::Deployment aborted:" \
    "deployment to '$DEPLOYMENT_ENVIRONMENT' requires a successful prior deployment" \
    "to '$PREREQUISITE_ENVIRONMENT', but none was found."
  exit 1
fi
