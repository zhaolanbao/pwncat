#!/usr/bin/env bash

set -e
set -u
set -o pipefail

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
SOURCEPATH="${SCRIPTPATH}/../../.lib/conf.sh"
BINARY="${SCRIPTPATH}/../../../bin/pwncat"
# shellcheck disable=SC1090
source "${SOURCEPATH}"


# -------------------------------------------------------------------------------------------------
# GLOBALS
# -------------------------------------------------------------------------------------------------

PYTHON="python${1:-}"
PYVER="$( "${PYTHON}" -V 2>&1 | head -1 || true )"

RHOST="localhost"
RPORT="${2:-4444}"
RUNS=1
STARTUP_WAIT=2
TRANS_WAIT=10


# -------------------------------------------------------------------------------------------------
# TEST FUNCTIONS
# -------------------------------------------------------------------------------------------------
print_test_case "${PYVER}"

run_test() {
	local srv_opts="${1// / }"
	local cli_opts="${2// / }"
	local curr_mutation="${3}"
	local total_mutation="${4}"
	local curr_round="${5}"
	local total_round="${6}"
	local data=

	print_h1 "[ROUND: ${curr_round}/${total_round}] (mutation: ${curr_mutation}/${total_mutation}) Starting Test Round (srv '${srv_opts}' vs cli '${cli_opts}')"
	run "sleep 1"

	###
	### Create data and files
	###
	data='abcdefghijklmnopqrstuvwxyz1234567890'
	srv_stdout="$(tmp_file)"
	srv_stderr="$(tmp_file)"
	cli_stdout="$(tmp_file)"
	cli_stderr="$(tmp_file)"


	# --------------------------------------------------------------------------------
	# START: SERVER
	# --------------------------------------------------------------------------------
	print_h2 "(1/5) Start: Server"

	# Start Server
	print_info "Start Server"
	# shellcheck disable=SC2086
	if ! srv_pid="$( run_bg "" "${PYTHON}" "${BINARY}" ${srv_opts} "${srv_stdout}" "${srv_stderr}" )"; then
		printf ""
	fi

	# Wait until Server is up
	run "sleep ${STARTUP_WAIT}"

	# [SERVER] Ensure Server is running
	test_case_instance_is_running "Server" "${srv_pid}" "${srv_stdout}" "${srv_stderr}"

	# [SERVER] Ensure Server has no errors
	test_case_instance_has_no_errors "Server" "${srv_pid}" "${srv_stdout}" "${srv_stderr}"


	# --------------------------------------------------------------------------------
	# START: CLIENT
	# --------------------------------------------------------------------------------
	print_h2 "(2/5) Start: Client"

	# Start Client
	print_info "Start Client"
	# shellcheck disable=SC2086
	if ! cli_pid="$( run_bg "echo ${data}" "${PYTHON}" "${BINARY}" ${cli_opts} "${cli_stdout}" "${cli_stderr}" )"; then
		printf ""
	fi

	# Wait until Client is up
	run "sleep ${STARTUP_WAIT}"

	# [CLIENT] Ensure Client is running
	test_case_instance_is_running "Client" "${cli_pid}" "${cli_stdout}" "${cli_stderr}" "Server" "${srv_pid}" "${srv_stdout}" "${srv_stderr}"

	# [CLIENT] Ensure Client has no errors
	test_case_instance_has_no_errors "Client" "${cli_pid}" "${cli_stdout}" "${cli_stderr}" "Server" "${srv_pid}" "${srv_stdout}" "${srv_stderr}"

	# [SERVER] Ensure Server is still is running
	test_case_instance_is_running "Server" "${srv_pid}" "${srv_stdout}" "${srv_stderr}" "Client" "${cli_pid}" "${cli_stdout}" "${cli_stderr}"

	# [SERVER] Ensure Server still has no errors
	test_case_instance_has_no_errors "Server" "${srv_pid}" "${srv_stdout}" "${srv_stderr}" "Client" "${cli_pid}" "${cli_stdout}" "${cli_stderr}"


	# --------------------------------------------------------------------------------
	# DATA TRANSFER
	# --------------------------------------------------------------------------------
	print_h2 "(3/5) Transfer: Client -> Server"

	# [SERVER] Wait for data
	print_info "Wait for data transfer"
	cnt=0
	while ! diff <(echo "${data}") "${srv_stdout}" >/dev/null 2>&1; do
		printf "."
		cnt=$(( cnt + 1 ))
		if [ "${cnt}" -gt "${TRANS_WAIT}" ]; then
			echo
			print_file "CLIENT STDERR" "${cli_stderr}"
			print_file "CLIENT STDOUT" "${cli_stdout}"
			print_file "SERVER STDERR" "${srv_stderr}"
			print_file "SERVER STDOUT" "${srv_stdout}"
			print_data "EXPECT DATA" "${data}"
			diff <(echo "${data}") "${srv_stdout}" 2>&1 || true
			kill_pid "${cli_pid}" || true
			kill_pid "${srv_pid}" || true
			print_data "RECEIVED RAW" "$( od -c "${srv_stdout}" )"
			print_data "EXPECTED RAW" "$( echo "${data}" | od -c )"
			print_error "[Receive Error] Received data on Server does not match send data from Client"
			exit 1
		fi
		sleep 1
	done
	echo
	print_file "Server received data" "${srv_stdout}"


	# --------------------------------------------------------------------------------
	# STOP: SERVER
	# --------------------------------------------------------------------------------
	print_h2 "(4/5) Stop: Server"

	# [SERVER] Manually stop the Server
	action_stop_instance "Server" "${srv_pid}" "${srv_stdout}" "${srv_stderr}" "Client" "${cli_pid}" "${cli_stdout}" "${cli_stderr}"

	# [SERVER] Ensure Server still has no errors
	test_case_instance_has_no_errors "Server" "${srv_pid}" "${srv_stdout}" "${srv_stderr}" "Client" "${cli_pid}" "${cli_stdout}" "${cli_stderr}"


	# --------------------------------------------------------------------------------
	# TEST: Client  shut down automatically
	# --------------------------------------------------------------------------------
	print_h2 "(5/5) Test: Client shut down automatically"

	# [CLIENT] Ensure Client has quit automatically
	test_case_instance_is_stopped "Client" "${cli_pid}" "${cli_stdout}" "${cli_stderr}" "Server" "${srv_pid}" "${srv_stdout}" "${srv_stderr}"

	# [CLIENT] Ensure Client has no errors
	test_case_instance_has_no_errors "Client" "${cli_pid}" "${cli_stdout}" "${cli_stderr}" "Server" "${srv_pid}" "${srv_stdout}" "${srv_stderr}"
}


# -------------------------------------------------------------------------------------------------
# MAIN ENTRYPOINT
# -------------------------------------------------------------------------------------------------

for curr_round in $(seq "${RUNS}"); do
	echo
	#         server opts         client opts
	run_test "-l ${RPORT} -vvvv" "${RHOST} ${RPORT} -vvvv"  "1" "13" "${curr_round}" "${RUNS}"
	run_test "-l ${RPORT} -vvv " "${RHOST} ${RPORT} -vvvv"  "2" "13" "${curr_round}" "${RUNS}"
	run_test "-l ${RPORT} -vv  " "${RHOST} ${RPORT} -vvvv"  "3" "13" "${curr_round}" "${RUNS}"
	run_test "-l ${RPORT} -v   " "${RHOST} ${RPORT} -vvvv"  "4" "13" "${curr_round}" "${RUNS}"
	run_test "-l ${RPORT}      " "${RHOST} ${RPORT} -vvvv"  "5" "13" "${curr_round}" "${RUNS}"

	run_test "-l ${RPORT} -vvvv" "${RHOST} ${RPORT} -vvv "  "6" "13" "${curr_round}" "${RUNS}"
	run_test "-l ${RPORT} -vvvv" "${RHOST} ${RPORT} -vv  "  "7" "13" "${curr_round}" "${RUNS}"
	run_test "-l ${RPORT} -vvvv" "${RHOST} ${RPORT} -v   "  "8" "13" "${curr_round}" "${RUNS}"
	run_test "-l ${RPORT} -vvvv" "${RHOST} ${RPORT}      "  "9" "13" "${curr_round}" "${RUNS}"

	run_test "-l ${RPORT} -vvv " "${RHOST} ${RPORT} -vvv " "10" "13" "${curr_round}" "${RUNS}"
	run_test "-l ${RPORT} -vv  " "${RHOST} ${RPORT} -vv  " "11" "13" "${curr_round}" "${RUNS}"
	run_test "-l ${RPORT} -v   " "${RHOST} ${RPORT} -v   " "12" "13" "${curr_round}" "${RUNS}"
	run_test "-l ${RPORT}      " "${RHOST} ${RPORT}      " "13" "13" "${curr_round}" "${RUNS}"
done
