generate-nix-module-options:
    rm -rf nixos/modules/generated && \
    cp -r "$(nix build .#generated-options --no-link --print-out-paths)" nixos/modules/generated/
    chmod +w -R nixos/modules/generated/
