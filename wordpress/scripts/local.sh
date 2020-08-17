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

CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function error {
	msg="$(date '+%F %T') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${1:-}"
	>&2 echo -e "${RED}${msg}${NC}"
	exit 2
}

if [ -z "$base_dir" ] || [ "$base_dir" = "/" ]; then
	msg="This project must be in a directory structure of type"
	msg="$msg [base_dir]/[pod_layer_base_dir]/[this_repo] with"
	msg="$msg base_dir different than '' or '/' instead of $pod_layer_dir"
	error "$msg"
fi

ctl_layer_dir="$base_dir/ctl"
app_layer_dir="$base_dir/apps/$var_dev__repo_dir_wordpress"

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (env)."
fi

shift;

start="$(date '+%F %T')"

case "$command" in
	"prepare"|"setup"|"migrate"|"stop"|"rm"|"clear")
		echo -e "${CYAN}$(date '+%F %T') - env (local) - $command - start${NC}"
		;;
esac

case "$command" in
	"w3tc")
		"$pod_script_env_file" exec-nontty wordpress /bin/bash <<-SHELL
			set -eou pipefail

			wp --allow-root plugin install w3-total-cache

			cp /var/www/html/web/app/plugins/w3-total-cache/wp-content/advanced-cache.php /var/www/html/web/app/advanced-cache.php
			mkdir /var/www/html/web/app/cache
			chmod 777 /var/www/html/web/app/cache
			mkdir /var/www/html/web/app/w3tc-config
			chmod 777 /var/www/html/web/app/w3tc-config

			wp --allow-root plugin activate w3-total-cache
		SHELL
		;;
	"w3tc-remove")
		"$pod_script_env_file" exec-nontty wordpress /bin/bash <<-SHELL
			set -eou pipefail

			wp --allow-root plugin deactivate w3-total-cache
			wp --allow-root plugin uninstall w3-total-cache
		SHELL
		;;
	"c")
		"$pod_env_shared_file" exec composer composer update --verbose
		;;
	"composer")
		"$pod_env_shared_file" exec composer composer clear-cache
		"$pod_env_shared_file" exec composer composer update --verbose
		;;
	"prepare")
		if [ "${var_custom__use_composer:-}" = "true" ]; then
			inner_dir="env"

			if [ "${var_custom__dynamic:-}" = "true" ]; then
				inner_dir="main"
			fi

			sudo chmod +x "$app_layer_dir/"
			cp "$pod_full_dir/$inner_dir/wordpress/.env" "$app_layer_dir/.env"
			chmod +r "$app_layer_dir/.env"
			chmod 777 "$app_layer_dir/web/app/uploads/"
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
	"stop"|"rm")
		"$pod_env_shared_file" "$command" "$@"
		"$ctl_layer_dir/run" "$command"
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

end="$(date '+%F %T')"

case "$command" in
	"prepare"|"setup"|"migrate"|"stop"|"rm"|"clear")
		echo -e "${CYAN}$(date '+%F %T') - env (local) - $command - end${NC}"
		echo -e "${CYAN}env (local) - $command - $start - $end${NC}"
		;;
esac