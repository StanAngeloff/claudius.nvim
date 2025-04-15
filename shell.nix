{
  pkgs ? import <nixpkgs> { },
}:
let
  packageOverrides = pkgs.callPackage ./python-packages.nix { };
  python = pkgs.python312.override { inherit packageOverrides; };
  pythonWithPackages = python.withPackages (p: [
    p.google-cloud-aiplatform
    p.google-generativeai
    p.aider-chat
  ]);
in
pkgs.mkShell {
  shellHook = ''
    if [ -z "$VERTEXAI_PROJECT" ]; then
      if [ -f .env ]; then
        export VERTEXAI_PROJECT=$(grep -oP '(?<=^VERTEXAI_PROJECT=).*' .env)
        if [ -z "$VERTEXAI_PROJECT" ]; then
          echo -e "\033[0;33m[claudius-shell] Warning: \$VERTEXAI_PROJECT was not set in .env file.\033[0m"
          exit 1
        else
          echo -e "\033[0;32m[claudius-shell] Loaded project name from .env file: $VERTEXAI_PROJECT\033[0m"
        fi
      else
        echo -e "\033[0;33m[claudius-shell] Warning: \$VERTEXAI_PROJECT was not set and no .env file found.\033[0m"
        exit 1
      fi
    fi

    if [ -z "$GOOGLE_APPLICATION_CREDENTIALS"]; then
      # Try to get credentials from libsecret if available.
      if command -v secret-tool >/dev/null 2>&1; then
        CREDENTIALS=$(secret-tool lookup service vertex key api project_id "$VERTEXAI_PROJECT" 2>/dev/null)
        if [ ! -z "$CREDENTIALS" ]; then
          echo "$CREDENTIALS" >.claudius-credentials.json
          export GOOGLE_APPLICATION_CREDENTIALS=".claudius-credentials.json"
          echo -e "\033[0;32m[claudius-shell] Retrieved credentials from system keyring.\033[0m"
        else
          echo -e "\033[0;33m[claudius-shell] Warning: \$GOOGLE_APPLICATION_CREDENTIALS was not set and not found in system keyring.\033[0m"
          exit 1
        fi
      else
        echo -e "\033[0;33m[claudius-shell] Warning: \$GOOGLE_APPLICATION_CREDENTIALS was not set and libsecret tools not available.\033[0m"
        exit 1
      fi
    fi
  '';

  nativeBuildInputs = with pkgs; [
    libsecret
    pythonWithPackages

    (writeShellApplication {
      name = "claudius-dev";
      text = ''
        aider \
          lua/*/*.lua \
          lua/*/*/*.lua \
          syntax/*.vim \
          README.md

        rm -f .claudius-credentials.json || true
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

        stylua --indent-type spaces --indent-width 2 \
          lua/*/*.lua \
          lua/*/*/*.lua

        prettier --write \
          README.md
      '';
    })
  ];
}
