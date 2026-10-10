{
  description = "Development shell";

  inputs.nix-devenv.url = "github:dryvist/nix-devenv?dir=shells/tofu&ref=v0";

  outputs =
    { nix-devenv, ... }:
    {
      inherit (nix-devenv) devShells;
    };
}
