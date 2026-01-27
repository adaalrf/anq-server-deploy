(if builtins.pathExists ./keys.local.nix
then import ./keys.local.nix
else import ./examples/keys.example.nix)
