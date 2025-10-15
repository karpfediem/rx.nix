{ lib }:
filesAttr:
let
  inherit (lib) mapAttrsToList removePrefix;

  mkItem = path: f:
    let
      hasText = f ? text && f.text != null;
      hasSrc  = f ? source && f.source != null;
      hasGen  = f ? generator && f ? value && f.generator != null && f.value != null;
      count   = (if hasText then 1 else 0) + (if hasSrc then 1 else 0) + (if hasGen then 1 else 0);

      # Flat rootfs: strip one leading slash if present, otherwise keep as-is.
      # This tolerates both "/etc/hosts" and "etc/hosts".
      relPath = removePrefix "/" (toString path);
    in
    if count != 1 then
      throw "rx.files ${toString path}: set exactly one of text | source | (generator+value)"
    else
      {
        path      = toString path;
        src       = relPath;
        owner     = f.owner or "root";
        group     = f.group or "root";
        mode      = f.mode  or "0644";
        ensureDir = f.ensureDir or true;
      }
      //
      (if hasText then { "__content" = f.text; }
       else if hasSrc then { "__source" = toString f.source; }
       else { "__content" = (f.generator f.value); });

in
{
  files = mapAttrsToList mkItem filesAttr;
}
