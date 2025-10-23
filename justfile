generate-nix-module-options:
    out_path="$(nix build .#rx-nixos-options --no-link --print-out-paths)" && \
    mkdir -p nixos/modules/generated && \
    rsync -a --delete --chmod=Du+w,Fu+w "$out_path"/ nixos/modules/generated/
