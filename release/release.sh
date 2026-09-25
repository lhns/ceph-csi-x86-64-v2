#!/usr/bin/env bash
# Release steps for .github/workflows/release.yml. Needs gh (GH_TOKEN), curl, jq; `publish` also docker.
#   release.sh versions          upstream's stable releases from $floor on, oldest first
#   release.sh plan [VERSION]    GITHUB_OUTPUT lines build=[..] and adopt=[..]: versions with no release here,
#                                split by whether ghcr already has the tag
#   release.sh publish VERSION   push the tested quay.io/cephcsi/cephcsi:VERSION unless ghcr has the tag, then release
#   release.sh adopt VERSION     release a tag ghcr already has, for its existing digest
# DRY_RUN=true reports instead of pushing or releasing. A tag in ghcr is never overwritten.
set -euo pipefail
cd "$(dirname "$0")/.."
image=ghcr.io/lhns/ceph-csi-x86-64-v2
floor=v3.18.0 # upstream's first release on an x86-64-v3 (EL10) base
repo=${GITHUB_REPOSITORY:-lhns/ceph-csi-x86-64-v2}
dry=${DRY_RUN:-false}
run_url=${GITHUB_SERVER_URL:-https://github.com}/$repo/actions/runs/${GITHUB_RUN_ID:-}

versions() {
	gh api --paginate repos/ceph/ceph-csi/releases --jq '.[] | select((.draft or .prerelease) | not) | .tag_name' |
		grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V |
		while read -r v; do [ "$(printf '%s\n' "$floor" "$v" | sort -V | head -1)" != "$floor" ] || echo "$v"; done
}

# The tag's digest, or nothing if ghcr has no such tag. Any other answer is an error, never "absent".
digest() {
	local token head code
	token=$(curl -fsS "https://ghcr.io/token?scope=repository:${image#ghcr.io/}:pull" | jq -r .token)
	head=$(curl -sS -I -w '%{http_code}' -H "Authorization: Bearer $token" \
		-H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json' \
		"https://ghcr.io/v2/${image#ghcr.io/}/manifests/$1" | tr -d '\r')
	code=$(tail -n1 <<<"$head")
	case $code in
	200) awk 'tolower($1) == "docker-content-digest:" { print $2 }' <<<"$head" ;;
	404) ;;
	*) echo "ghcr answered $code for $image:$1" >&2; return 1 ;;
	esac
}

# 0 if a release exists, 1 if not; any other failure aborts.
has_release() {
	local out
	out=$(gh api "repos/$repo/releases/tags/$1" 2>&1 >/dev/null) && return 0
	grep -q 'HTTP 404' <<<"$out" && return 1
	echo "$out" >&2
	exit 1
}

release() { # VERSION DIGEST TARGET-COMMIT RUN-URL
	local v=$1 d=$2 target=$3 run=$4 pins
	pins=$(git show "$target:versions.Dockerfile" | awk '$1 == "FROM" { printf "- %s: `%s`\n", $4, $2 }')
	body="Upstream [ceph-csi $v](https://github.com/ceph/ceph-csi/releases/tag/$v), built on an x86-64-v2 (EL9) base.

Image: \`$image:$v@$d\`

Base images (\`versions.Dockerfile\` at this tag):
$pins

CI: $run"
	if has_release "$v"; then
		echo "release $v exists; nothing to do"
	elif [ "$dry" = true ]; then
		printf 'DRY RUN: would create release %s at %s:\n%s\n' "$v" "$target" "$body"
	else
		gh release create "$v" -R "$repo" --target "$target" --title "$v" --notes "$body"
	fi
}

adopt() {
	local v=$1 d config target run
	d=$(digest "$v")
	[ -n "$d" ] || { echo "$image:$v does not exist" >&2; exit 1; }
	config=$(docker buildx imagetools inspect "$image:$v" --format '{{json .Image}}' 2>/dev/null ||
		echo '{}')
	target=$(jq -r '.config.Labels["org.opencontainers.image.revision"] // empty' <<<"$config")
	run=$(jq -r '.config.Labels["io.github.lhns.ci-run"] // empty' <<<"$config")
	if [ -z "$target" ] || [ "$target" = unknown ] || ! git cat-file -e "$target^{commit}" 2>/dev/null; then
		echo "$image:$v carries no building commit; releasing it at $GITHUB_SHA" >&2
		target=$GITHUB_SHA
		run="not recorded: pushed before this workflow existed"
	fi
	echo "$image:$v exists as $d; not pushing"
	release "$v" "$d" "$target" "$run"
}

case ${1:-} in
versions)
	versions
	;;
plan)
	want=${2:-}
	all=$(versions)
	if [ -n "$want" ]; then
		grep -qx "$want" <<<"$all" || { echo "$want is not a stable upstream release >= $floor" >&2; exit 1; }
		all=$want
	fi
	build=() adopt=()
	for v in $all; do
		released=false
		has_release "$v" && released=true
		d=$(digest "$v")
		echo "$v: release $([ $released = true ] && echo exists || echo missing), ghcr ${d:-missing}" >&2
		# A named version in a dry run is built and tested whatever its state; nothing is published.
		if [ -n "$want" ] && [ "$dry" = true ]; then build+=("$v"); fi
		[ $released = false ] || continue
		if [ -n "$d" ]; then adopt+=("$v"); elif [ -z "$want" ] || [ "$dry" != true ]; then build+=("$v"); fi
	done
	echo "build=$(printf '%s\n' "${build[@]}" | jq -Rsc 'split("\n") | map(select(. != ""))')"
	echo "adopt=$(printf '%s\n' "${adopt[@]}" | jq -Rsc 'split("\n") | map(select(. != ""))')"
	;;
publish)
	v=$2
	d=$(digest "$v")
	if [ -n "$d" ]; then
		echo "$image:$v already exists; not overwriting it with this build"
		adopt "$v"
		exit
	fi
	if [ "$dry" = true ]; then
		echo "DRY RUN: would push $image:$v"
		release "$v" "sha256:(dry run)" "$GITHUB_SHA" "$run_url"
		exit
	fi
	docker tag "quay.io/cephcsi/cephcsi:$v" "$image:$v"
	docker push "$image:$v"
	d=$(digest "$v")
	echo "Published \`$image:$v@$d\`" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
	release "$v" "$d" "$GITHUB_SHA" "$run_url"
	;;
adopt)
	adopt "$2"
	;;
*)
	sed -n '2,9p' "$0" >&2
	exit 2
	;;
esac
