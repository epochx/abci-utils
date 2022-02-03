qstat | awk 'NR>2 {split($0, a, " "); printf ("%s\t%s", a[1], a[3]);}' | while read -l -a rline
    complete -f -c delete-job -s j -o j -l job -a "$rline[1]" -d "$rline[2]"
end