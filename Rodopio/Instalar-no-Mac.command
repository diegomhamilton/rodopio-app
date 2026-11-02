#!/bin/bash
set -eu
source_dir="$(cd "$(dirname "$0")" && pwd)"
target="$HOME/Documents/Personal/Ciranda"
mkdir -p "$target"
if [ "$source_dir" != "$target" ]; then
    if [ -e "$target/Ciranda.xcodeproj" ]; then
        target="$HOME/Documents/Personal/Ciranda-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$target"
    fi
    ditto "$source_dir" "$target"
fi
open "$target/Ciranda.xcodeproj"
printf 'Projeto disponível em: %s\n' "$target"
