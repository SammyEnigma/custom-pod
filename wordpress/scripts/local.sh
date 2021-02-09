#!/bin/bash
# shellcheck disable=SC2154
set -eou pipefail

pod_script_env_file="$var_pod_script"

pod_env_shared_file="$var_run__general__script_dir/shared.sh"

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

case "$command" in
	"c")
		"$pod_env_shared_file" exec composer composer update --verbose
		;;
	"composer")
		"$pod_env_shared_file" exec composer composer clear-cache
		"$pod_env_shared_file" exec composer composer update --verbose
		;;
	"prepare")
		if [ "${var_custom__app_dev:-}" = "true" ] && [ "${var_custom__use_composer:-}" = "true" ]; then
			if [ -z "${var_dev__repo_dir_wordpress:-}" ]; then
				error "[error] wordpress directory not defined (var_dev__repo_dir_wordpress)"
			fi

			app_dir="$pod_layer_dir/$var_dev__repo_dir_wordpress"

			sudo chmod +x "$app_dir/"
			cp "$pod_layer_dir/env/wordpress/.env" "$app_dir/.env"
			chmod +r "$app_dir/.env"
			chmod 777 "$app_dir/web/app/uploads/"
		fi

		"$pod_env_shared_file" "$command" "$@"
		;;
	"setup")
		if [ "${var_custom__use_composer:-}" = "true" ]; then
			"$pod_env_shared_file" up mysql composer
			"$pod_env_shared_file" exec composer composer install --verbose
		fi

		"$pod_env_shared_file" "$command" "$@"
		;;
	"clear-remote")
		"$pod_script_env_file" "s3:subtask:s3_uploads" --s3_cmd=rb
		"$pod_script_env_file" "s3:subtask:s3_backup" --s3_cmd=rb
		;;
	"clear")
		"$pod_script_env_file" "local:clear"
		sudo docker volume rm -f "${var_run__general__ctx_full_name}_mysql"
		sudo docker volume rm -f "${var_run__general__ctx_full_name}_uploads"
		;;
	"clear-all")
		"$pod_script_env_file" "local:clear-all"
		;;
	*)
		"$pod_env_shared_file" "$command" "$@"
		;;
esac
