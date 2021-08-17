qstat | awk 'NR>2 {split($0, a, " "); print a[1]" "a[3];}' | while read -l -a rline
    complete -c qdel -f -a "$rline[1]" -d "$rline[2]"
end