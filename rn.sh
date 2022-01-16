validator=""
generator=""
programs=()
iterations=-1

main() {
	help=0
	default_diff=0
	
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
		elif [ $i -gt 0 ]; then # TODO: check if this is needed
			programs+=( "$ag" )
		fi
	done
	
	if [ $help -eq 1 ]; then
		help
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
	echo " -- help --"
	echo "  "
	echo "  usage:"
	echo "  $ rn {flags}"
	echo "  "
	echo "  '-h' or '--help', prints this message"
	echo "  '-g', '--gen' or '--generator', specify a generator, following this should be a path to the generator"
	echo "  '-v', '--val' or '--validator', specify a validator, following this should be a path to the validator"
	echo "  '-d', '--dif' or '--diff', use diff mode as well"
	echo "  '-t', '--tests' or '--testcount', specify a number of tests to run, following this should be a positive integer, default is infinity"
	echo "  any other argument will be interpreted as an executable to add to the list of targets"
	echo "  "
	echo "  any number of executables can be specified"
	echo "  exactly one generator and at most one validator may be used"
	echo "  if no validator or 'diff' mode is specified, the mode will be defaulted to testing whether the target(s) crash, as well as their execution time"
	echo "  validator will be executed with '$ ./{path} infile outfile', specifying the input file used for a target as well as the targets output"
	echo "  exit code 0 from the validator will signal that the output was valid and the script will continue"
	echo "  the generator should print resulting input file to stdout"
	echo "  all targets should print output to stdout and read from stdin"
}

diff_script() {
	readarray -t s_prv < out_prv_
	readarray -t s_now < out_
	for (( ii=0; ii<${#s_now[@]}; ii++ ))
	do
		if [ $ii -ge ${#s_prv[@]} ]; then
			ii=$(( ii + 1 ))
			echo "diff at [$ii:-1]"
			return 1
		fi
		s_cur_prv=${s_prv[$ii]}
		s_cur_now=${s_now[$ii]}
		if [ ${#s_cur_now} -ne ${#s_cur_prv} ]; then
			len=$(( ${#s_cur_now} < ${#s_cur_prv} ? ${#s_cur_now} : ${#s_cur_prv} ))
			ii=$(( ii + 1 ))
			len=$(( len - 1 ))
			echo "diff at [$ii:$len]"
			return 1
		fi
		for (( jj=0; jj<${#s_cur_now}; jj++ ))
		do
			if [ ${s_cur_now:$jj:1} != ${s_cur_prv:$jj:1} ]; then
				ii=$(( ii + 1 ))
				echo "diff at [$ii:$jj]"
				return 1
			fi
		done
	done
	if [ ${#s_now[@]} -lt ${#s_prv[@]} ]; then
		i=$(( ${#s_now[@]} + 1 ))
		echo "diff at [$ii:-1]"
		return 1
	fi
	return 0
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
			./"${programs[$i]}" < in_ > "out_"
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
					rm out_prv_
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
	touch in_ out_ val_out_
	rm in_ out_ val_out_
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
			if [ i -ne 0 ]; then
				cat > out_prv_ < out_
			fi
			time_elapsed=$(date +%s%N)
			./"${programs[$i]}" < in_ > "out_"
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
			if [ i -ne 0 ]; then
				diff_script
				exit_code=$?
				if [ $exit_code -ne 0 ]; then
					echo "  output of target '${programs[$i]}' was different from previous targets outputs"
					rm out_prv_
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
	touch in_ out_ val_out_
	rm in_ out_ val_out_
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
		./"${programs[0]}" < in_ > out_
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
	touch in_ out_ val_out_
	rm in_ out_ val_out_
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
			./"${programs[$i]}" < in_ > "out_"
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
	touch in_ out_ val_out_
	rm in_ out_ val_out_
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
		./"${programs[0]}" < in_ > out_
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
	touch in_ out_
	rm in_ out_
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
			./"${programs[$i]}" < in_ > "out_"
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
	touch in_ out_
	rm in_ out_
}

main "$@"
