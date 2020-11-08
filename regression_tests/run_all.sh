#!/bin/sh

cd `dirname $0`

base=Avignon
../parse.pl $base.csv > $base.out
diff $base.expected $base.out
rm -f $base.out
