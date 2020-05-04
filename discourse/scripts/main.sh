#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC2153
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"

. "${pod_vars_dir}/vars.sh"

RED='\033[0;31m'
NC='\033[0m' # No Color

function error {
	msg="$(date '+%F %T') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${1:-}"
	>&2 echo -e "${RED}${msg}${NC}"
	exit 2
}

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (env)."
fi

shift;

pod_env_shared_file="$pod_layer_dir/main/scripts/main.sh"

case "$command" in
  "bootstrap:remote:"*)
		ctx="${command#backup:local:db:}"
		prefix="var_bootstrap_remote_${ctx}"
		remote_tag="${prefix}_remote_tag"
		toolbox_service="${prefix}_toolbox_service"
		container_type="${prefix}_container_type"
		registry_api_base_url="${prefix}_registry_api_base_url"
		registry_host="${prefix}_registry_host"
		registry_port="${prefix}_registry_port"
		repository="${prefix}_repository"
		version="${prefix}_version"
		username="${prefix}_username"
		pass="${prefix}_pass"
		
		opts=()

		opts+=( "--remote_tag=${!remote_tag}" )
		opts+=( "--toolbox_service=${!toolbox_service}" )
		opts+=( "--container_type=${!container_type}" )
		opts+=( "--registry_api_base_url=${!registry_api_base_url}" )
		opts+=( "--registry_host=${!registry_host}" )
		opts+=( "--registry_port=${!registry_port}" )
		opts+=( "--repository=${!repository}" )
		opts+=( "--version=${!version}" )
		opts+=( "--username=${!username}" )
		opts+=( "--pass=${!pass}" )

		exists="$("$pod_script_env_file" "image:verify" "${opts[@]}")"

		if [ "$exists" != "true" ]; then
			"$pod_script_env_file" "image:push" "${opts[@]}"
		fi
    ;;
  "restore")
		docker exec -i -w /var/www/discourse "$var_restore_container_name" sh -x <<-SHELL
			discourse enable_restore
			discourse restore $var_restore_filename
			discourse disable_restore
		SHELL
    ;;
  *)
    "$pod_env_shared_file" "$command" "$@"
    ;;
esac