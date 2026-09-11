# bash completion for myhop
_myhop_complete() {
    local cur prev subcommands conf aliases
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    subcommands="add list edit rm connect help"
    conf="${MYHOP_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/myhop/instances.tsv}"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
        return 0
    fi

    case "$prev" in
        edit|rm|del|delete|connect)
            if [ -f "$conf" ]; then
                aliases=$(grep -v '^\s*#' "$conf" | grep -v '^\s*$' | cut -f1)
                COMPREPLY=( $(compgen -W "$aliases" -- "$cur") )
            fi
            return 0
            ;;
        list)
            COMPREPLY=( $(compgen -W "--test" -- "$cur") )
            return 0
            ;;
    esac
}
complete -F _myhop_complete myhop
