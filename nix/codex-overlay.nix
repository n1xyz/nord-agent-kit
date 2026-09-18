{ nord-mcp }:
final: prev: {
  # CLI overrides apply only to this wrapper; the user's Codex config and
  # authentication remain in their usual locations.
  codex = prev.writeShellScriptBin "codex" ''
    exec ${prev.codex}/bin/codex \
      -c ${prev.lib.escapeShellArg "mcp_servers.nord.command=\"${nord-mcp}/bin/nord-mcp\""} \
      -c 'mcp_servers.nord.args=["serve","--public","--network","mainnet"]' \
      -c 'mcp_servers.nord.enabled=true' \
      "$@"
  '';
}
