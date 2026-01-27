(if builtins.pathExists ./options.local.nix
then import ./options.local.nix
else import ./examples/options.example.nix)
