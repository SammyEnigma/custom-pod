#!/bin/bash
# shellcheck disable=SC2154
set -eou pipefail

# shellcheck disable=SC2153
pod_vars_dir="$POD_VARS_DIR"
# shellcheck disable=SC2153
pod_layer_dir="$POD_LAYER_DIR"
# shellcheck disable=SC2153
pod_full_dir="$POD_FULL_DIR"
# shellcheck disable=SC2153
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

# shellcheck disable=SC1090
. "${pod_vars_dir}/vars.sh"

pod_env_shared_file="$pod_layer_dir/$var_run__general__script_dir/shared.sh"

pod_layer_base_dir="$(dirname "$pod_layer_dir")"
base_dir="$(dirname "$pod_layer_base_dir")"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${*}"
}

if [ -z "$base_dir" ] || [ "$base_dir" = "/" ]; then
	msg="This project must be in a directory structure of type"
	msg="$msg [base_dir]/[pod_layer_base_dir]/[this_repo] with"
	msg="$msg base_dir different than '' or '/' instead of $pod_layer_dir"
	error "$msg"
fi

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

			inner_dir="env"

			if [ "${var_custom__dynamic:-}" = "true" ]; then
				inner_dir="main"
			fi

			sudo chmod +x "$app_dir/"
			cp "$pod_full_dir/$inner_dir/wordpress/.env" "$app_dir/.env"
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
		"$pod_script_env_file" rm
		sudo docker volume rm -f "${var_main__env}-${var_main__ctx}-${var_main__pod_name}_mysql"
		sudo docker volume rm -f "${var_main__env}-${var_main__ctx}-${var_main__pod_name}_nextcloud"
		sudo rm -rf "${base_dir}/data/${var_main__env}/${var_main__ctx}/${var_main__pod_name}/"
		;;
	"clear-all")
		"$pod_script_env_file" rm
		sudo docker container prune -f
		sudo docker network prune -f
		sudo docker volume prune -f
		sudo rm -rf "${base_dir}/data/"*
		;;
	*)
		"$pod_env_shared_file" "$command" "$@"
		;;
esac
