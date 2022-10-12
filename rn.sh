validator=""
generator=""
programs=()
iterations=-1

main() {
	help=0
	default_diff=0
	clean=0
	
	for (( i=0; i<=$#; i++ ))
	do
		ag="${!i}"
		if [ "$ag" = "--help" ] || [ "$ag" = "-h" ]; then
			help=1
		elif [ "$ag" = "--generator" ] || [ "$ag" = "--gen" ] || [ "$ag" = "-g" ]; then
			if [ $i -ge $# ]; then
				echo "missing argument after '$ag'"
				exit
			fi
			i=$(( i + 1 ))
			generator="${!i}"
		elif [ "$ag" = "--validator" ] || [ "$ag" = "--val" ] || [ "$ag" = "-v" ]; then
			if [ $i -ge $# ]; then
				echo "missing argument after '$ag'"
				exit
			fi
			i=$(( i + 1 ))
			validator="${!i}"
		elif [ "$ag" = "-d" ] || [ "$ag" = "--dif" ] || [ "$ag" = "--diff" ]; then
			default_diff=1
		elif [ "$ag" = "-t" ] || [ "$ag" = "--tests" ] || [ "$ag" = "--testcount" ]; then
			if [ $i -ge $# ]; then
				echo "missing argument after '$ag'"
				exit
			fi
			i=$(( i + 1 ))
			iterations="${!i}"
		elif [ "$ag" = "-c" ] || [ "$ag" = "--clean" ]; then
			clean=1
		elif [ $i -gt 0 ]; then
			programs+=( "$ag" )
		fi
	done
	
	if [ $help -eq 1 ]; then
		help
		exit
	fi
	
	if [ $clean -eq 1 ]; then
		rm -f in_ out_ out_prv_ val_out_
		exit
	fi
	
	if [ "$generator" = "" ]; then
		echo "missing generator"
		exit
	fi
	
	if [ ${#programs[@]} -eq 0 ]; then
		echo "missing targets"
		exit
	fi
	
	# abort if any programs have different output
	if [ $default_diff -eq 1 ] && [ "$validator" = "" ]; then
		echo "running diff mode"
		if [ ${#programs[@]} -eq 1 ]; then
			echo "only one target was specified"
			exit
		fi
		mode_diff
		exit
	fi
	
	# abort if any programs have different output OR if the output fails validator test
	if [ $default_diff -eq 1 ] && [ ! "$validator" = "" ]; then
		echo "running diff + validator mode"
		if [ ${#programs[@]} -eq 1 ]; then
			echo "only one target was specified"
			exit
		fi
		mode_diff_val
		exit
	fi
	
	# abort if program has output that fails validator test
	if [ ! "$validator" = "" ] && [ ${#programs[@]} -eq 1 ]; then
		echo "running single target validator mode"
		mode_val_single
		exit
	fi
	
	# abort if any programs have output that fails validator test
	if [ ! "$validator" = "" ] && [ ${#programs[@]} -gt 1 ]; then
		echo "running multiple target validator mode"
		mode_val_multi
		exit
	fi
	
	# abort if program has non-zero exit code
	if [ ${#programs[@]} -eq 1 ]; then
		echo "running single target mode"
		mode_single
		exit
	fi
	
	# abort if any programs have non-zero exit code
	if [ ${#programs[@]} -gt 1 ]; then
		echo "running multiple target mode"
		mode_multi
		exit
	fi
	
	echo "mode was undecided"
	exit
}

help() {
	echo " -- rn help --"
	echo "  "
	echo "  usage:"
	echo "  $ rn {flags}"
	echo "  "
	echo "  '-h' or '--help', prints this message"
	echo "  '-c' or '--clean', removes temporary potentially stray files such as 'in_'/'out_'/etc."
	echo "  '-g', '--gen' or '--generator', specify a generator, following this should be a path to the generator"
	echo "  '-v', '--val' or '--validator', specify a validator, following this should be a path to the validator"
	echo "  '-d', '--dif' or '--diff', use diff mode as well"
	echo "  '-t', '--tests' or '--testcount', specify a number of tests to run, following this should be a positive integer, default is infinity"
	echo "  any other argument will be interpreted as an executable to add to the list of targets"
	echo "  "
	echo "  generator: should print generated input to stdout"
	echo "  validator: executed as '$ ./{path} input_test_case executable_output' - non-zero exit code signals failed validation"
	echo "  diff mode: must specify more than one executable - testing is terminated if any two executables have different output"
	echo "  executables to be tested: should read input from stdin and print output to stdout"
	echo "  "
	echo "  any number of executables can be specified"
	echo "  exactly one generator may be specified"
	echo "  at most one validator may be specified"
	echo "  if no validator or diff mode is specified, default to running all input files and test for execution time and crashes"
	echo "  execution time and crashes are tested in any mode"
}

diff_script() {
	df=$(diff out_prv_ out_ | head -n 2)
	if [ ${#df} -eq 0 ]; then
		return 0
	fi
	ep="diff at ["
	for (( ii=0; ii<${#df}; ii++ ))
	do
		re='^[0-9]+$'
		if [ "${df:$ii:1}" = "c" ]; then
			ep="${ep}:"
		elif ! [[ "${df:$ii:1}" =~ $re ]]; then
			break
		else
			ep="${ep}${df:$ii:1}"
		fi
	done
	ep="${ep}]"
	echo "$ep"
	return 1
}

mode_diff() {
	echo ""
	trap "exit" INT
	test_count=0
	max_time=()
	for (( i=0; i<${#programs[@]}; i++ )); do max_time+=( $i ); done
	avg_time=()
	for (( i=0; i<${#programs[@]}; i++ )); do avg_time+=( $i ); done
	while [ $iterations -eq -1 ] || [ $iterations -gt $test_count ]
	do
		test_count=$(( test_count + 1 ))
		echo "running #$test_count"
		./"$generator" > in_
		exit_code=$?
		if [ $exit_code -ne 0 ]; then
			echo "  generator '$generator' had non-zero exit code ($exit_code)"
			exit
		fi
		for (( i=0; i<${#programs[@]}; i++ ))
		do
			if [ $i -ne 0 ]; then
				cat > out_prv_ < out_
			fi
			time_elapsed=$(date +%s%N)
			extension="${programs[$i]##*.}"
			if [ "$extension" == "py" ]; then
				python3 "${programs[$i]}" < in_ > "out_"
			else
				./"${programs[$i]}" < in_ > "out_"
			fi
			exit_code=$?
			time_elapsed=$(( ($(date +%s%N) - $time_elapsed) / 1000000 ))
			if [ $exit_code -ne 0 ]; then
				echo "  target '${programs[$i]}' had non-zero exit code ($exit_code)"
				if [ $i -ne 0 ]; then
					rm out_prv_
				fi
				exit
			fi
			echo "  target '${programs[$i]}' execution time: ${time_elapsed}ms"
			max_time[$i]=$(( max_time[$i] > $time_elapsed ? max_time[$i] : $time_elapsed ))
			avg_time[$i]=$(( avg_time[$i] + $time_elapsed ))
			if [ $i -ne 0 ]; then
				diff_script
				exit_code=$?
				if [ $exit_code -ne 0 ]; then
					echo "  output of target '${programs[$i]}' was different from previous target(s) output(s)"
					exit
				fi
				rm out_prv_
			fi
		done
	done
	echo -e "\ndone\n"
	for (( i=0; i<${#programs[@]}; i++ ))
	do
		echo "target '${programs[$i]}':"
		echo "  max execution time: ${max_time[$i]}ms"
		if [ $test_count -gt 0 ]; then
			avg_time[$i]=$(( avg_time[$i] / $test_count ))
		fi
		echo "  average execution time: ${avg_time[$i]}ms"
	done
	rm -f in_ out_ out_prv_ val_out_
}

mode_diff_val() {
	echo ""
	trap "exit" INT
	test_count=0
	max_time=()
	for (( i=0; i<${#programs[@]}; i++ )); do max_time+=( $i ); done
	avg_time=()
	for (( i=0; i<${#programs[@]}; i++ )); do avg_time+=( $i ); done
	while [ $iterations -eq -1 ] || [ $iterations -gt $test_count ]
	do
		test_count=$(( test_count + 1 ))
		echo "running #$test_count"
		./"$generator" > in_
		exit_code=$?
		if [ $exit_code -ne 0 ]; then
			echo "  generator '$generator' had non-zero exit code ($exit_code)"
			exit
		fi
		for (( i=0; i<${#programs[@]}; i++ ))
		do
			if [ $i -ne 0 ]; then
				cat > out_prv_ < out_
			fi
			time_elapsed=$(date +%s%N)
			extension="${programs[$i]##*.}"
			if [ "$extension" == "py" ]; then
				python3 "${programs[$i]}" < in_ > "out_"
			else
				./"${programs[$i]}" < in_ > "out_"
			fi
			exit_code=$?
			time_elapsed=$(( ($(date +%s%N) - $time_elapsed) / 1000000 ))
			if [ $exit_code -ne 0 ]; then
				echo "  target '${programs[$i]}' had non-zero exit code ($exit_code)"
				if [ i -ne 0 ]; then
					rm out_prv_
				fi
				exit
			fi
			echo "  target '${programs[$i]}' execution time: ${time_elapsed}ms"
			max_time[$i]=$(( max_time[$i] > $time_elapsed ? max_time[$i] : $time_elapsed ))
			avg_time[$i]=$(( avg_time[$i] + $time_elapsed ))
			if [ $i -ne 0 ]; then
				diff_script
				exit_code=$?
				if [ $exit_code -ne 0 ]; then
					echo "  output of target '${programs[$i]}' was different from previous targets outputs"
					exit
				fi
				rm out_prv_
			fi
			./"$validator" in_ out_ > val_out_
			exit_code=$?
			cat val_out_
			if [ $exit_code -ne 0 ]; then
				echo "  target '${programs[$i]}' failed validation - validator exit code was: $exit_code"
				exit
			fi
		done
	done
	echo -e "\ndone\n"
	for (( i=0; i<${#programs[@]}; i++ ))
	do
		echo "target '${programs[$i]}':"
		echo "  max execution time: ${max_time[$i]}ms"
		if [ $test_count -gt 0 ]; then
			avg_time[$i]=$(( avg_time[$i] / $test_count ))
		fi
		echo "  average execution time: ${avg_time[$i]}ms"
	done
	rm -f in_ out_ out_prv_ val_out_
}

mode_val_single() {
	echo ""
	trap "exit" INT
	test_count=0
	max_time=0
	avg_time=0
	while [ $iterations -eq -1 ] || [ $iterations -gt $test_count ]
	do
		test_count=$(( test_count + 1 ))
		echo "running #$test_count"
		./"$generator" > in_
		exit_code=$?
		if [ $exit_code -ne 0 ]; then
			echo "  generator '$generator' had non-zero exit code ($exit_code)"
			exit
		fi
		time_elapsed=$(date +%s%N)
		extension="${programs[0]##*.}"
		if [ "$extension" == "py" ]; then
			python3 "${programs[0]}" < in_ > "out_"
		else
			./"${programs[0]}" < in_ > "out_"
		fi
		exit_code=$?
		time_elapsed=$(( ($(date +%s%N) - $time_elapsed) / 1000000 ))
		if [ $exit_code -ne 0 ]; then
			echo "  target '${programs[0]}' had non-zero exit code ($exit_code)"
			exit
		fi
		echo "  execution time: ${time_elapsed}ms"
		max_time=$(( $max_time > $time_elapsed ? $max_time : $time_elapsed ))
		avg_time=$(( $avg_time + $time_elapsed ))
		./"$validator" in_ out_ > val_out_
		exit_code=$?
		cat val_out_
		if [ $exit_code -ne 0 ]; then
			echo "  target '${programs[0]}' failed validation - validator exit code was: $exit_code"
			exit
		fi
	done
	echo -e "\ndone\n"
	echo "max execution time: ${max_time}ms"
	if [ $test_count -gt 0 ]; then
		avg_time=$(( $avg_time / $test_count ))
	fi
	echo "average execution time: ${avg_time}ms"
	rm -f in_ out_ out_prv_ val_out_
}

mode_val_multi() {
	echo ""
	trap "exit" INT
	test_count=0
	max_time=()
	for (( i=0; i<${#programs[@]}; i++ )); do max_time+=( $i ); done
	avg_time=()
	for (( i=0; i<${#programs[@]}; i++ )); do avg_time+=( $i ); done
	while [ $iterations -eq -1 ] || [ $iterations -gt $test_count ]
	do
		test_count=$(( test_count + 1 ))
		echo "running #$test_count"
		./"$generator" > in_
		exit_code=$?
		if [ $exit_code -ne 0 ]; then
			echo "  generator '$generator' had non-zero exit code ($exit_code)"
			exit
		fi
		for (( i=0; i<${#programs[@]}; i++ ))
		do
			time_elapsed=$(date +%s%N)
			extension="${programs[$i]##*.}"
			if [ "$extension" == "py" ]; then
				python3 "${programs[$i]}" < in_ > "out_"
			else
				./"${programs[$i]}" < in_ > "out_"
			fi
			exit_code=$?
			time_elapsed=$(( ($(date +%s%N) - $time_elapsed) / 1000000 ))
			if [ $exit_code -ne 0 ]; then
				echo "  target '${programs[$i]}' had non-zero exit code ($exit_code)"
				exit
			fi
			echo "  target '${programs[$i]}' execution time: ${time_elapsed}ms"
			max_time[$i]=$(( max_time[$i] > $time_elapsed ? max_time[$i] : $time_elapsed ))
			avg_time[$i]=$(( avg_time[$i] + $time_elapsed ))
			./"$validator" in_ out_ > val_out_
			exit_code=$?
			cat val_out_
			if [ $exit_code -ne 0 ]; then
				echo "  target '${programs[$i]}' failed validation - validator exit code was: $exit_code"
				exit
			fi
		done
	done
	echo -e "\ndone\n"
	for (( i=0; i<${#programs[@]}; i++ ))
	do
		echo "target '${programs[$i]}':"
		echo "  max execution time: ${max_time[$i]}ms"
		if [ $test_count -gt 0 ]; then
			avg_time[$i]=$(( avg_time[$i] / $test_count ))
		fi
		echo "  average execution time: ${avg_time[$i]}ms"
	done
	rm -f in_ out_ out_prv_ val_out_
}

mode_single() {
	echo ""
	trap "exit" INT
	test_count=0
	max_time=0
	avg_time=0
	while [ $iterations -eq -1 ] || [ $iterations -gt $test_count ]
	do
		test_count=$(( test_count + 1 ))
		echo "running #$test_count"
		./"$generator" > in_
		exit_code=$?
		if [ $exit_code -ne 0 ]; then
			echo "  generator '$generator' had non-zero exit code ($exit_code)"
			exit
		fi
		time_elapsed=$(date +%s%N)
		extension="${programs[0]##*.}"
		if [ "$extension" == "py" ]; then
			python3 "${programs[0]}" < in_ > "out_"
		else
			./"${programs[0]}" < in_ > "out_"
		fi
		exit_code=$?
		time_elapsed=$(( ($(date +%s%N) - $time_elapsed) / 1000000 ))
		if [ $exit_code -ne 0 ]; then
			echo "  target '${programs[0]}' had non-zero exit code ($exit_code)"
			exit
		fi
		echo "  execution time: ${time_elapsed}ms"
		max_time=$(( $max_time > $time_elapsed ? $max_time : $time_elapsed ))
		avg_time=$(( $avg_time + $time_elapsed ))
	done
	echo -e "\ndone\n"
	echo "max execution time: ${max_time}ms"
	if [ $test_count -gt 0 ]; then
		avg_time=$(( $avg_time / $test_count ))
	fi
	echo "average execution time: ${avg_time}ms"
	rm -f in_ out_ out_prv_ val_out_
}

mode_multi() {
	echo ""
	trap "exit" INT
	test_count=0
	max_time=()
	for (( i=0; i<${#programs[@]}; i++ )); do max_time+=( $i ); done
	avg_time=()
	for (( i=0; i<${#programs[@]}; i++ )); do avg_time+=( $i ); done
	while [ $iterations -eq -1 ] || [ $iterations -gt $test_count ]
	do
		test_count=$(( test_count + 1 ))
		echo "running #$test_count"
		./"$generator" > in_
		exit_code=$?
		if [ $exit_code -ne 0 ]; then
			echo "  generator '$generator' had non-zero exit code ($exit_code)"
			exit
		fi
		for (( i=0; i<${#programs[@]}; i++ ))
		do
			time_elapsed=$(date +%s%N)
			extension="${programs[$i]##*.}"
			if [ "$extension" == "py" ]; then
				python3 "${programs[$i]}" < in_ > "out_"
			else
				./"${programs[$i]}" < in_ > "out_"
			fi
			exit_code=$?
			time_elapsed=$(( ($(date +%s%N) - $time_elapsed) / 1000000 ))
			if [ $exit_code -ne 0 ]; then
				echo "  target '${programs[$i]}' had non-zero exit code ($exit_code)"
				exit
			fi
			echo "  target '${programs[$i]}' execution time: ${time_elapsed}ms"
			max_time[$i]=$(( max_time[$i] > $time_elapsed ? max_time[$i] : $time_elapsed ))
			avg_time[$i]=$(( avg_time[$i] + $time_elapsed ))
		done
	done
	echo -e "\ndone\n"
	for (( i=0; i<${#programs[@]}; i++ ))
	do
		echo "target '${programs[$i]}':"
		echo "  max execution time: ${max_time[$i]}ms"
		if [ $test_count -gt 0 ]; then
			avg_time[$i]=$(( avg_time[$i] / $test_count ))
		fi
		echo "  average execution time: ${avg_time[$i]}ms"
	done
	rm -f in_ out_ out_prv_ val_out_
}

main "$@"
