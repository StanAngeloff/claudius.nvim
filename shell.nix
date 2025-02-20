{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  shellHook = ''
    if [ -z "$ANTHROPIC_API_KEY" ]; then
      echo -e "\033[0;33mWarning: \$ANTHROPIC_API_KEY was not set before entering the dev shell.\033[0m"
    fi
  '';

  nativeBuildInputs = with pkgs; [
    libsecret # For secret-tool CLI
    (writeShellApplication {
      name = "claudius-dev";
      runtimeInputs = [ aider-chat ];
      text = ''
        aider --sonnet README.md lua/**/*.lua shell.nix
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
