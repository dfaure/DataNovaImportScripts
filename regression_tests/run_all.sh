#!/bin/sh

cd `dirname $0`

for name in *.csv; do
    base=${name%%.*}
    ../parse.pl $base.csv > $base.out || exit 1
    diff -u $base.expected $base.out
    rm -f $base.out
done
