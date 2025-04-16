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
    PROJECT_ROOT=$(pwd)
    export PROJECT_ROOT
  '';

  nativeBuildInputs = with pkgs; [
    libsecret
    pythonWithPackages

    (writeShellApplication {
      name = "claudius-dev";
      text = ''
        set +e

        if [ -z "''${VERTEXAI_PROJECT-}" ]; then
          if [ -f "$PROJECT_ROOT/.env" ]; then
            VERTEXAI_PROJECT=$(grep -oP '(?<=^VERTEXAI_PROJECT=).*' "$PROJECT_ROOT/.env")
            if [ -n "''${VERTEXAI_PROJECT-}" ]; then
              export VERTEXAI_PROJECT
              echo -e "\033[0;32m[claudius-dev] Loaded Vertex project name from .env file: $VERTEXAI_PROJECT\033[0m"
            else
              echo -e "\033[0;33m[claudius-dev] Warning: \$VERTEXAI_PROJECT was not set in .env file.\033[0m"
            fi
          else
            echo -e "\033[0;33m[claudius-dev] Warning: \$VERTEXAI_PROJECT was not set and no .env file found.\033[0m"
          fi
        fi

        if [ -z "''${GOOGLE_APPLICATION_CREDENTIALS-}" ]; then
          if command -v secret-tool >/dev/null 2>&1; then
            CREDENTIALS=$(secret-tool lookup service vertex key api project_id "''${VERTEXAI_PROJECT-}" 2>/dev/null)
            if [ -n "''${CREDENTIALS-}" ]; then
              existing=$(trap -p EXIT | awk -F"'" '{print $2}')
              # shellcheck disable=SC2064
              trap "( rm -f '$PROJECT_ROOT/.aider-credentials.json'; $existing )" EXIT
              echo "$CREDENTIALS" >"$PROJECT_ROOT/.aider-credentials.json"
              GOOGLE_APPLICATION_CREDENTIALS="$PROJECT_ROOT/.aider-credentials.json"
              export GOOGLE_APPLICATION_CREDENTIALS
              echo -e "\033[0;32m[claudius-dev] Retrieved Google credentials from system keyring.\033[0m"
            else
              echo -e "\033[0;33m[claudius-dev] Warning: \$GOOGLE_APPLICATION_CREDENTIALS was not set and not found in system keyring.\033[0m"
            fi
          else
            echo -e "\033[0;33m[claudius-dev] Warning: \$GOOGLE_APPLICATION_CREDENTIALS was not set and libsecret tools not available.\033[0m"
          fi
        fi

        aider \
          lua/*/*.lua \
          lua/*/*/*.lua \
          syntax/*.vim \
          README.md

        rm -f .aider-credentials.json || true
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
