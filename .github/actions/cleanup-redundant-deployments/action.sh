#!/usr/bin/env bash
set -eu

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
| map(select(.commitOid | startswith($version)))
| map(select((.payload // "") | contains($deploymentPayloadMarker) | not))
| [ .[] | .databaseId ] | @tsv
'

deployment_ids=$(gh api graphql \
  -F repoOwner="$repo_owner" \
  -F repoName="$repo_name" \
  -F environment="$DEPLOYMENT_ENVIRONMENT" \
  -f query="$graphql_query" \
  | jq -r \
    --arg version "$VERSION" \
    --arg deploymentPayloadMarker "$DEPLOYMENT_PAYLOAD_MARKER" "$jq_query")

for deployment_id in $deployment_ids; do
  gh api --silent -X DELETE "/repos/{owner}/{repo}/deployments/${deployment_id}"
  echo "::notice::Redundant GitHub deployment object '${deployment_id}' was deleted."
done
