#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC2153
set -eou pipefail

# shellcheck disable=SC2154
pod_layer_dir="$var_pod_layer_dir"
# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit $LINENO;' ERR

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (env)."
fi

shift;

args=("$@")

pod_env_shared_file="$pod_layer_dir/main/scripts/main.sh"

case "$command" in
  "discourse:launcher")
		"$var_custom__discourse_dir"/launcher ${args[@]+"${args[@]}"}
		;;
  "discourse:bootstrap:"*)
		ctx="${command#discourse:bootstrap:}"
		prefix="var_discourse_bootstrap_${ctx}"
		toolbox_service="${prefix}_toolbox_service"
		container_type="${prefix}_container_type"
		registry_api_base_url="${prefix}_registry_api_base_url"
		registry_host="${prefix}_registry_host"
		registry_port="${prefix}_registry_port"
		repository="${prefix}_repository"
		version="${prefix}_version"
		username="${prefix}_username"
		userpass="${prefix}_userpass"
		container_name="${prefix}_container_name"

		local_image="local_discourse/${!container_name}"

		opts=()

		opts+=( "--toolbox_service=${!toolbox_service}" )
		opts+=( "--container_type=${!container_type}" )
		opts+=( "--registry_api_base_url=${!registry_api_base_url}" )
		opts+=( "--registry_host=${!registry_host}" )
		opts+=( "--registry_port=${!registry_port}" )
		opts+=( "--repository=${!repository}" )
		opts+=( "--version=${!version}" )
		opts+=( "--username=${!username}" )
		opts+=( "--userpass=${!userpass}" )

		opts+=( "--local_image=$local_image" )

		exists="$("$pod_script_env_file" "container:image:tag:exists" "${opts[@]}")"

		if [ "$exists" != "true" ]; then
			"$pod_script_env_file" "discourse:launcher" bootstrap "${!container_name}"
			"$pod_script_env_file" "container:image:push" "${opts[@]}"
		fi
    ;;
  "restore")
		docker exec -i -w /var/www/discourse "$var_restore_container_name" discourse enable_restore
		docker exec -i -w /var/www/discourse "$var_restore_container_name" discourse restore $var_restore_filename
		docker exec -i -w /var/www/discourse "$var_restore_container_name" discourse disable_restore
    ;;
  *)
    "$pod_env_shared_file" "$command" "$@"
    ;;
esac