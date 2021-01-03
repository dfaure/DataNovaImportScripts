#!/bin/sh

cd `dirname $0`

for name in *.csv; do
    base=${name%%.*}
    echo $base.csv
    export KEEPOLD=1
    ../parse.pl $base.csv > $base.out || exit 1
    # Update baseline:
    #cp $base.out $base.expected
    diff -u $base.expected $base.out
    rm -f $base.out
done
