#!/bin/bash

# 1. input excel-generated csv 
# 2. converts to plain csv 
# 3. outputs plain csv
usage() {
    echo "Usage: ctg-parse-excel-csv.sh -i EXCEL_CSV -o PLAIN_CSV "  1>&2 
    echo ""
    echo ""
}

exit_abnormal() {
    usage
    exit 1
}


while getopts i:o: opt; do
    case $opt in
	i) insheet="$OPTARG"
	   ;;
	o) outsheet="$OPTARG"
	    ;;
	\?) echo "> Error: Invalid option -$OPTARG" >&2
	    exit_abnormal ;;
	:) echo "> Error: -${OPTARG} requires an argument!" 
	    exit_abnormal ;;
    esac
done

shift "$(( OPTIND -1 ))"

if [ -z $insheet ]; then
    echo "> Error: missing -i insheet!"
    exit_abnormal
fi
if [ -z $outsheet ]; then
    echo "> Error: missing -o outsheet!"
    exit_abnormal
fi 


sed "s/;/,/g" $insheet > $outsheet

echo "> converted $insheet to plain csv : $outsheet"

