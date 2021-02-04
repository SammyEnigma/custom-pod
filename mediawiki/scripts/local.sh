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

pod_env_shared_file="$pod_layer_dir/$var_run__general__script_dir/shared.sh"

function info {
	"$pod_env_shared_file" "util:info" --info="${*}"
}

function error {
	"$pod_env_shared_file" "util:error" --error="${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${*}"
}

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (env)."
fi

shift;

case "$command" in
	"clear")
		"$pod_script_env_file" "local:clear"
		sudo docker volume rm -f "${var_run__general__ctx_full_name}_mysql"
		sudo docker volume rm -f "${var_run__general__ctx_full_name}_uploads"
		;;
	"clear-all")
		"$pod_script_env_file" "local:clear-all"
		;;
	"clear-remote")
		"$pod_script_env_file" "s3:subtask:s3_uploads" --s3_cmd=rb
		"$pod_script_env_file" "s3:subtask:s3_backup" --s3_cmd=rb
		;;
	*)
		"$pod_env_shared_file" "$command" "$@"
		;;
esac