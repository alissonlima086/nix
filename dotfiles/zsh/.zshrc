export EDITOR=nvim

HISTSIZE=10000
SAVEHIST=10000
HISTFILE="$HOME/.zsh_history"

setopt AUTO_CD
setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY

autoload -Uz compinit
compinit

# Key bindings — sem isso Home/End mandam a sequência de escape crua pro
# zle, que trata o ESC solto como início de comando (trava a digitação).
bindkey "${terminfo[khome]}" beginning-of-line
bindkey "${terminfo[kend]}" end-of-line
bindkey "${terminfo[kdch1]}" delete-char
# Fallback pra terminais/multiplexers que mandam sequências fora do terminfo
bindkey "^[[H" beginning-of-line
bindkey "^[[F" end-of-line
bindkey "^[[1~" beginning-of-line
bindkey "^[[4~" end-of-line

# Aliases
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# PATH
path=(
    "$HOME/.config/hypr/scripts"
    "$HOME/.local/bin"
    $path
)

# Prompt
eval "$(starship init zsh)"
