# Egress proxy configuration (stub)
#
# Future: Network egress filtering via mitmproxy or similar.
# This module provides the interface for domain whitelisting
# without implementing the actual proxy.
#
# Design considerations:
# - Proxy should run as sidecar container or host service
# - Container traffic routed via iptables/nftables REDIRECT
# - TLS interception requires CA injection (complex)
# - Alternative: DNS-based filtering (simpler, less secure)
#
# References:
# - https://docs.mitmproxy.org/stable/
# - https://github.com/elazarl/goproxy

{ pkgs
, lib ? pkgs.lib
}:

{
  # Domain whitelist configuration
  #
  # Arguments:
  #   allowedDomains - List of allowed domains (supports wildcards)
  #   blockByDefault - Block all traffic not in whitelist (default: true)
  #   logBlocked     - Log blocked requests (default: true)
  #
  # Returns:
  #   Attribute set with proxy configuration (currently stub values)
  #
  # Example:
  #   mkEgressConfig {
  #     allowedDomains = [
  #       "api.anthropic.com"
  #       "*.github.com"
  #       "registry.npmjs.org"
  #     ];
  #   }
  #
  mkEgressConfig =
    { allowedDomains ? []
    , blockByDefault ? true
    , logBlocked ? true
    }:

    let
      # Normalize domains (lowercase, trim whitespace)
      normalizedDomains = map (d: lib.toLower (lib.trim d)) allowedDomains;

      # Default domains required for basic Claude operation
      requiredDomains = [
        "api.anthropic.com"        # Claude API
        "statsigapi.net"           # Analytics
        "sentry.io"                # Error reporting
      ];

      # Merge with user-specified domains
      allDomains = lib.unique (requiredDomains ++ normalizedDomains);

    in {
      # Current status: stub implementation
      enabled = false;

      # Configuration for future proxy
      config = {
        inherit blockByDefault logBlocked;
        domains = allDomains;
      };

      # Warning message for users
      warning = ''
        Egress filtering is not yet implemented.

        Currently, containers have unrestricted network access via pasta/slirp4netns.
        This is a planned feature for security-sensitive deployments.

        Workaround: Use host firewall rules to restrict outbound traffic
        from the container network namespace.
      '';

      # TODO:SECURITY - Implement egress filtering
      # Options to evaluate:
      # 1. mitmproxy sidecar with CA injection
      # 2. DNS-based filtering (CoreDNS + RPZ)
      # 3. iptables REDIRECT to transparent proxy
      # 4. eBPF-based socket filtering
    };

  # Placeholder for proxy container definition
  # Future: Returns a container spec for the proxy sidecar
  mkProxyContainer =
    { config
    , listenPort ? 8080
    }:

    {
      enabled = false;
      message = "Proxy container not yet implemented";

      # Stub container spec
      container = {
        image = "mitmproxy/mitmproxy:latest";  # Example
        ports = [ "${toString listenPort}:8080" ];
        volumes = [];
        environment = {
          PROXY_MODE = "transparent";
        };
      };
    };
}
