#!/usr/bin/env bash
set -eu

repo_owner=$(echo "${GITHUB_REPOSITORY}" | cut -d'/' -f1)
repo_name=$(echo "${GITHUB_REPOSITORY}" | cut -d'/' -f2)

graphql_query='
query ($repoOwner: String!, $repoName: String!) {
  repository(owner: $repoOwner, name: $repoName) {
    deployments(
      first: 100
      orderBy: {field: CREATED_AT, direction: DESC}
    ) {
      nodes {
        createdAt
        databaseId
        payload
      }
    }
  }
}
'

jq_query='
.data.repository.deployments.nodes
| map(select((.payload // "") | contains($deploymentPayloadMarker) | not))
| [ .[] | .databaseId ] | @tsv
'

deployment_ids=$(gh api graphql \
  -F repoOwner="$repo_owner" \
  -F repoName="$repo_name" \
  -f query="$graphql_query" \
  | jq -r --arg deploymentPayloadMarker "$DEPLOYMENT_PAYLOAD_MARKER" "$jq_query")

for deployment_id in $deployment_ids; do
  gh api --silent -X POST "/repos/{owner}/{repo}/deployments/${deployment_id}/statuses" \
    -f state="inactive"
  gh api --silent -X DELETE "/repos/{owner}/{repo}/deployments/${deployment_id}"
  echo "::notice::Redundant GitHub deployment object '${deployment_id}' was deleted."
done
