# useful env variables
if test -e /usr/local/bin/show_point 
    set -x GROUPS (show_point | cut -d " " -f1 | tail -n +2 | tr '\n' ' ')
else
    set -x GROUPS
end

if test -e "$HOME/.groups"
    cat "$HOME/.groups" | while read -l -a gline
        set -x "$gline[2]" "$gline[1]"
    end
end
