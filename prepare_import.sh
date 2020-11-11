./parse.pl ../laposte_ouvertur.csv > ../out 2> ../warnings
ready=`grep -v ERROR ../out | wc -l`
errors=`grep ERROR ../out | wc -l`
echo "$ready post offices ready for import. $errors post offices with unresolved rules"
echo "(see ../warnings)"
