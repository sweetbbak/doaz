alias b := default

default:
    just --justfile {{justfile()}} build
    just --justfile {{justfile()}} chmod

chmod:
    #!/usr/bin/env bash
    sudo chown root ./zig-out/bin/doaz
    sudo chmod u+s ./zig-out/bin/doaz    

build:
    #!/usr/bin/env bash
    printf "\e[3;33;3m%s\e[0m\n" "Building suwudo"
    zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl
    just --justfile {{justfile()}} chmod

# install-usr-bin:
#     #!/usr/bin/env bash
#     printf "\e[3;33;3m%s\e[0m\n" "Installing suwudo"
#     suwu_path=$(which suwu)
#     [ -e "$suwu_path" ] && rm "${suwu_path}"
#
#     printf "\e[3;33;3m%s\e[0m\n" "Building suwudo"
#     go build -ldflags "-s -w" -o suwu cmd/*.go
#
#     sudo /usr/bin/cp ./suwu /usr/bin
#     sudo chown root /usr/bin/suwu
#     sudo chmod u+s /usr/bin/suwu
#
# install:
#     #!/usr/bin/env bash
#     printf "\e[3;33;3m%s\e[0m\n" "Installing suwudo"
#     suwu_path=$(which suwu)
#     [ -e "$suwu_path" ] && rm "${suwu_path}"
#
#     printf "\e[3;33;3m%s\e[0m\n" "Building suwudo"
#     go build -ldflags "-s -w" -o suwu cmd/*.go
#     /usr/bin/cp ./suwu ~/bin
#     sudo chown root ~/bin/suwu
#     sudo chmod u+s ~/bin/suwu
#
#
# uninstall:
#     #!/usr/bin/env bash
#     printf "\e[3;33;3m%s\e[0m\n" "Uninstalling suwudo"
#     [ -f "/usr/bin/suwu" ] && sudo rm /usr/bin/suwu
#     [ -f "$HOME/bin/suwu" ] && rm "$HOME/bin/suwu"
#     [ -f "$HOME/.local/bin/suwu" ] && rm "$HOME/.local/bin/suwu"

# test-all:
#     just --justfile {{justfile()}} build
#     just --justfile {{justfile()}} test

test:
    zig build test

