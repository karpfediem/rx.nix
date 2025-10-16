# Render a single file resource block.
{ esc }: f:
let
  srcLine =
    if f ? "__content" then
    # Content is inlined via payload artifact.
    # We always reference files from the generation payload dir.
      ''  content  => deploy.readfile("/files/${esc f.src}"),''
    else if f ? "__source" then
      ''  source  => "${esc f.__source}",''
    else
    # Should not happen because IR guarantees exactly one content source.
      ''  # ERROR: missing source/content'';
in
''
  file "${esc f.path}" {
    ${srcLine}
    owner   => "${esc (f.owner or "root")}",
    group   => "${esc (f.group or "root")}",
    mode    => "${esc (f.mode  or "0644")}",
    state   => $const.res.file.state.exists,
  }
''
