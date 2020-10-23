#!/bin/bash
# shellcheck disable=SC2154
set -eou pipefail

# shellcheck disable=SC2153
pod_vars_dir="$POD_VARS_DIR"
# shellcheck disable=SC2153
pod_layer_dir="$POD_LAYER_DIR"
# shellcheck disable=SC2153
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

# shellcheck disable=SC1090
. "${pod_vars_dir}/vars.sh"

pod_layer_base_dir="$(dirname "$pod_layer_dir")"
base_dir="$(dirname "$pod_layer_base_dir")"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${*}"
}

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (env)."
fi

shift;

pod_env_shared_file="$pod_layer_dir/$var_run__general__script_dir/shared.sh"

case "$command" in
	"clear")
		"$pod_script_env_file" rm
		sudo docker volume rm -f "${var_main__env}-${var_main__ctx}-${var_main__pod_name}_grafana"
		sudo docker volume rm -f "${var_main__env}-${var_main__ctx}-${var_main__pod_name}_prometheus"
		sudo rm -rf "${base_dir}/data/${var_main__env}/${var_main__ctx}/${var_main__pod_name}/"
		;;
	"clear-all")
		"$pod_script_env_file" rm
		sudo docker container prune -f
		sudo docker network prune -f
		sudo docker volume prune -f
		sudo rm -rf "${base_dir}/data/"*
		;;
	"clear-remote")
		"$pod_script_env_file" "s3:subtask:s3_backup" --s3_cmd=rb
		;;
	*)
		"$pod_env_shared_file" "$command" "$@"
		;;
esac