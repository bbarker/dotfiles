{ inputs, config, pkgs, lib ? pkgs.lib, ... }:

let
  # Check if nixgl overlay is available (added in flake.nix for Linux+impure)
  hasNixGL = pkgs ? nixgl;
in
{
  # Packages for all Linux systems
  packages = with pkgs; [
    appimage-run
  ] ++ (if hasNixGL then [ pkgs.nixgl.auto.nixGLDefault ] else []);

  # Wrap a package with nixGL (no-op if nixGL not available)
  wrapWithNixGL = pkg:
    if hasNixGL then
      pkgs.runCommand "${pkg.name}-nixgl-wrapped" { } ''
        mkdir -p $out/bin
        for f in ${pkg}/bin/*; do
          name=$(basename "$f")
          echo "#!${pkgs.bash}/bin/bash" > "$out/bin/$name"
          echo 'exec ${pkgs.nixgl.auto.nixGLDefault}/bin/nixGL '"$f"' "$@"' >> "$out/bin/$name"
          chmod +x "$out/bin/$name"
        done
        # Link other directories
        for d in ${pkg}/*; do
          name=$(basename "$d")
          if [ "$name" != "bin" ]; then
            ln -s "$d" "$out/$name" 2>/dev/null || true
          fi
        done
      ''
    else
      pkg;
}
