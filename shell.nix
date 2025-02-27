{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  shellHook = ''
    if [ -z "$ANTHROPIC_API_KEY" ]; then
      # Try to get API key from libsecret if available
      if command -v secret-tool >/dev/null 2>&1; then
        API_KEY=$(secret-tool lookup service anthropic key api 2>/dev/null)
        if [ ! -z "$API_KEY" ]; then
          export ANTHROPIC_API_KEY="$API_KEY"
          echo -e "\033[0;32m[claudius-shell] Retrieved API key from system keyring.\033[0m"
        else
          echo -e "\033[0;33m[claudius-shell] Warning: \$ANTHROPIC_API_KEY was not set and not found in system keyring.\033[0m"
        fi
      else
        echo -e "\033[0;33m[claudius-shell] Warning: \$ANTHROPIC_API_KEY was not set and libsecret tools not available.\033[0m"
      fi
    fi
  '';

  nativeBuildInputs = with pkgs; [
    libsecret

    (writeShellApplication {
      name = "claudius-dev";
      runtimeInputs = [ aider-chat.withPlaywright ];
      text = ''
        aider \
          --model anthropic/claude-3-5-sonnet-20241022 \
            README.md lua/**/*.lua syntax/*.vim
      '';
    })

    (writeShellApplication {
      name = "claudius-fmt";
      runtimeInputs = [
        nixfmt-rfc-style
        nodejs_22.pkgs.prettier
        stylua
      ];
      text = ''
        find . -type f -name '*.nix' -exec nixfmt {} \;
        stylua --indent-type spaces --indent-width 2 lua/**/*
        prettier --write --parser markdown README.md
      '';
    })
  ];
}
