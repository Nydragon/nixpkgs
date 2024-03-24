{ config, lib, options, pkgs, ... }:

with lib;

let

  cfg = config.networking.wireguard;
  opt = options.networking.wireguard;

  kernel = config.boot.kernelPackages;

  # interface options

  interfaceOpts = { ... }: {

    options = {

      ips = mkOption {
        example = [ "192.168.2.1/24" ];
        default = [];
        type = with types; listOf str;
        description = lib.mdDoc "The IP addresses of the interface.";
      };

      privateKey = mkOption {
        example = "yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=";
        type = with types; nullOr str;
        default = null;
        description = lib.mdDoc ''
          Base64 private key generated by {command}`wg genkey`.

          Warning: Consider using privateKeyFile instead if you do not
          want to store the key in the world-readable Nix store.
        '';
      };

      generatePrivateKeyFile = mkOption {
        default = false;
        type = types.bool;
        description = lib.mdDoc ''
          Automatically generate a private key with
          {command}`wg genkey`, at the privateKeyFile location.
        '';
      };

      privateKeyFile = mkOption {
        example = "/private/wireguard_key";
        type = with types; nullOr str;
        default = null;
        description = lib.mdDoc ''
          Private key file as generated by {command}`wg genkey`.
        '';
      };

      listenPort = mkOption {
        default = null;
        type = with types; nullOr int;
        example = 51820;
        description = lib.mdDoc ''
          16-bit port for listening. Optional; if not specified,
          automatically generated based on interface name.
        '';
      };

      preSetup = mkOption {
        example = literalExpression ''"''${pkgs.iproute2}/bin/ip netns add foo"'';
        default = "";
        type = with types; coercedTo (listOf str) (concatStringsSep "\n") lines;
        description = lib.mdDoc ''
          Commands called at the start of the interface setup.
        '';
      };

      postSetup = mkOption {
        example = literalExpression ''
          '''printf "nameserver 10.200.100.1" | ''${pkgs.openresolv}/bin/resolvconf -a wg0 -m 0'''
        '';
        default = "";
        type = with types; coercedTo (listOf str) (concatStringsSep "\n") lines;
        description = lib.mdDoc "Commands called at the end of the interface setup.";
      };

      postShutdown = mkOption {
        example = literalExpression ''"''${pkgs.openresolv}/bin/resolvconf -d wg0"'';
        default = "";
        type = with types; coercedTo (listOf str) (concatStringsSep "\n") lines;
        description = lib.mdDoc "Commands called after shutting down the interface.";
      };

      table = mkOption {
        default = "main";
        type = types.str;
        description = lib.mdDoc ''
          The kernel routing table to add this interface's
          associated routes to. Setting this is useful for e.g. policy routing
          ("ip rule") or virtual routing and forwarding ("ip vrf"). Both
          numeric table IDs and table names (/etc/rt_tables) can be used.
          Defaults to "main".
        '';
      };

      peers = mkOption {
        default = [];
        description = lib.mdDoc "Peers linked to the interface.";
        type = with types; listOf (submodule peerOpts);
      };

      allowedIPsAsRoutes = mkOption {
        example = false;
        default = true;
        type = types.bool;
        description = lib.mdDoc ''
          Determines whether to add allowed IPs as routes or not.
        '';
      };

      socketNamespace = mkOption {
        default = null;
        type = with types; nullOr str;
        example = "container";
        description = lib.mdDoc ''The pre-existing network namespace in which the
        WireGuard interface is created, and which retains the socket even if the
        interface is moved via {option}`interfaceNamespace`. When
        `null`, the interface is created in the init namespace.
        See [documentation](https://www.wireguard.com/netns/).
        '';
      };

      interfaceNamespace = mkOption {
        default = null;
        type = with types; nullOr str;
        example = "init";
        description = lib.mdDoc ''The pre-existing network namespace the WireGuard
        interface is moved to. The special value `init` means
        the init namespace. When `null`, the interface is not
        moved.
        See [documentation](https://www.wireguard.com/netns/).
        '';
      };

      fwMark = mkOption {
        default = null;
        type = with types; nullOr str;
        example = "0x6e6978";
        description = lib.mdDoc ''
          Mark all wireguard packets originating from
          this interface with the given firewall mark. The firewall mark can be
          used in firewalls or policy routing to filter the wireguard packets.
          This can be useful for setup where all traffic goes through the
          wireguard tunnel, because the wireguard packets need to be routed
          differently.
        '';
      };

      mtu = mkOption {
        default = null;
        type = with types; nullOr int;
        example = 1280;
        description = lib.mdDoc ''
          Set the maximum transmission unit in bytes for the wireguard
          interface. Beware that the wireguard packets have a header that may
          add up to 80 bytes to the mtu. By default, the MTU is (1500 - 80) =
          1420. However, if the MTU of the upstream network is lower, the MTU
          of the wireguard network has to be adjusted as well.
        '';
      };

      metric = mkOption {
        default = null;
        type = with types; nullOr int;
        example = 700;
        description = lib.mdDoc ''
          Set the metric of routes related to this Wireguard interface.
        '';
      };
    };

  };

  # peer options

  peerOpts = self: {

    options = {

      name = mkOption {
        default =
          replaceStrings
            [ "/" "-"     " "     "+"     "="     ]
            [ "-" "\\x2d" "\\x20" "\\x2b" "\\x3d" ]
            self.config.publicKey;
        defaultText = literalExpression "publicKey";
        example = "bernd";
        type = types.str;
        description = lib.mdDoc "Name used to derive peer unit name.";
      };

      publicKey = mkOption {
        example = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=";
        type = types.singleLineStr;
        description = lib.mdDoc "The base64 public key of the peer.";
      };

      presharedKey = mkOption {
        default = null;
        example = "rVXs/Ni9tu3oDBLS4hOyAUAa1qTWVA3loR8eL20os3I=";
        type = with types; nullOr str;
        description = lib.mdDoc ''
          Base64 preshared key generated by {command}`wg genpsk`.
          Optional, and may be omitted. This option adds an additional layer of
          symmetric-key cryptography to be mixed into the already existing
          public-key cryptography, for post-quantum resistance.

          Warning: Consider using presharedKeyFile instead if you do not
          want to store the key in the world-readable Nix store.
        '';
      };

      presharedKeyFile = mkOption {
        default = null;
        example = "/private/wireguard_psk";
        type = with types; nullOr str;
        description = lib.mdDoc ''
          File pointing to preshared key as generated by {command}`wg genpsk`.
          Optional, and may be omitted. This option adds an additional layer of
          symmetric-key cryptography to be mixed into the already existing
          public-key cryptography, for post-quantum resistance.
        '';
      };

      allowedIPs = mkOption {
        example = [ "10.192.122.3/32" "10.192.124.1/24" ];
        type = with types; listOf str;
        description = lib.mdDoc ''List of IP (v4 or v6) addresses with CIDR masks from
        which this peer is allowed to send incoming traffic and to which
        outgoing traffic for this peer is directed. The catch-all 0.0.0.0/0 may
        be specified for matching all IPv4 addresses, and ::/0 may be specified
        for matching all IPv6 addresses.'';
      };

      endpoint = mkOption {
        default = null;
        example = "demo.wireguard.io:12913";
        type = with types; nullOr str;
        description = lib.mdDoc ''
          Endpoint IP or hostname of the peer, followed by a colon,
          and then a port number of the peer.

          Warning for endpoints with changing IPs:
          The WireGuard kernel side cannot perform DNS resolution.
          Thus DNS resolution is done once by the `wg` userspace
          utility, when setting up WireGuard. Consequently, if the IP address
          behind the name changes, WireGuard will not notice.
          This is especially common for dynamic-DNS setups, but also applies to
          any other DNS-based setup.
          If you do not use IP endpoints, you likely want to set
          {option}`networking.wireguard.dynamicEndpointRefreshSeconds`
          to refresh the IPs periodically.
        '';
      };

      dynamicEndpointRefreshSeconds = mkOption {
        default = 0;
        example = 5;
        type = with types; int;
        description = lib.mdDoc ''
          Periodically re-execute the `wg` utility every
          this many seconds in order to let WireGuard notice DNS / hostname
          changes.

          Setting this to `0` disables periodic reexecution.
        '';
      };

      dynamicEndpointRefreshRestartSeconds = mkOption {
        default = null;
        example = 5;
        type = with types; nullOr ints.unsigned;
        description = lib.mdDoc ''
          When the dynamic endpoint refresh that is configured via
          dynamicEndpointRefreshSeconds exits (likely due to a failure),
          restart that service after this many seconds.

          If set to `null` the value of
          {option}`networking.wireguard.dynamicEndpointRefreshSeconds`
          will be used as the default.
        '';
      };

      persistentKeepalive = mkOption {
        default = null;
        type = with types; nullOr int;
        example = 25;
        description = lib.mdDoc ''This is optional and is by default off, because most
        users will not need it. It represents, in seconds, between 1 and 65535
        inclusive, how often to send an authenticated empty packet to the peer,
        for the purpose of keeping a stateful firewall or NAT mapping valid
        persistently. For example, if the interface very rarely sends traffic,
        but it might at anytime receive traffic from a peer, and it is behind
        NAT, the interface might benefit from having a persistent keepalive
        interval of 25 seconds; however, most users will not need this.'';
      };

    };

  };

  generateKeyServiceUnit = name: values:
    assert values.generatePrivateKeyFile;
    nameValuePair "wireguard-${name}-key"
      {
        description = "WireGuard Tunnel - ${name} - Key Generator";
        wantedBy = [ "wireguard-${name}.service" ];
        requiredBy = [ "wireguard-${name}.service" ];
        before = [ "wireguard-${name}.service" ];
        path = with pkgs; [ wireguard-tools ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          set -e

          # If the parent dir does not already exist, create it.
          # Otherwise, does nothing, keeping existing permissions intact.
          mkdir -p --mode 0755 "${dirOf values.privateKeyFile}"

          if [ ! -f "${values.privateKeyFile}" ]; then
            # Write private key file with atomically-correct permissions.
            (set -e; umask 077; wg genkey > "${values.privateKeyFile}")
          fi
        '';
      };

  peerUnitServiceName = interfaceName: peerName: dynamicRefreshEnabled:
    let
      refreshSuffix = optionalString dynamicRefreshEnabled "-refresh";
    in
      "wireguard-${interfaceName}-peer-${peerName}${refreshSuffix}";

  generatePeerUnit = { interfaceName, interfaceCfg, peer }:
    let
      psk =
        if peer.presharedKey != null
          then pkgs.writeText "wg-psk" peer.presharedKey
          else peer.presharedKeyFile;
      src = interfaceCfg.socketNamespace;
      dst = interfaceCfg.interfaceNamespace;
      ip = nsWrap "ip" src dst;
      wg = nsWrap "wg" src dst;
      dynamicRefreshEnabled = peer.dynamicEndpointRefreshSeconds != 0;
      # We generate a different name (a `-refresh` suffix) when `dynamicEndpointRefreshSeconds`
      # to avoid that the same service switches `Type` (`oneshot` vs `simple`),
      # with the intent to make scripting more obvious.
      serviceName = peerUnitServiceName interfaceName peer.name dynamicRefreshEnabled;
    in nameValuePair serviceName
      {
        description = "WireGuard Peer - ${interfaceName} - ${peer.name}"
          + optionalString (peer.name != peer.publicKey) " (${peer.publicKey})";
        requires = [ "wireguard-${interfaceName}.service" ];
        wants = [ "network-online.target" ];
        after = [ "wireguard-${interfaceName}.service" "network-online.target" ];
        wantedBy = [ "wireguard-${interfaceName}.service" ];
        environment.DEVICE = interfaceName;
        environment.WG_ENDPOINT_RESOLUTION_RETRIES = "infinity";
        path = with pkgs; [ iproute2 wireguard-tools ];

        serviceConfig =
          if !dynamicRefreshEnabled
            then
              {
                Type = "oneshot";
                RemainAfterExit = true;
              }
            else
              {
                Type = "simple"; # re-executes 'wg' indefinitely
                # Note that `Type = "oneshot"` services with `RemainAfterExit = true`
                # cannot be used with systemd timers (see `man systemd.timer`),
                # which is why `simple` with a loop is the best choice here.
                # It also makes starting and stopping easiest.
                #
                # Restart if the service exits (e.g. when wireguard gives up after "Name or service not known" dns failures):
                Restart = "always";
                RestartSec = if null != peer.dynamicEndpointRefreshRestartSeconds
                             then peer.dynamicEndpointRefreshRestartSeconds
                             else peer.dynamicEndpointRefreshSeconds;
              };
        unitConfig = lib.optionalAttrs dynamicRefreshEnabled {
          StartLimitIntervalSec = 0;
        };

        script = let
          wg_setup = concatStringsSep " " (
            [ ''${wg} set ${interfaceName} peer "${peer.publicKey}"'' ]
            ++ optional (psk != null) ''preshared-key "${psk}"''
            ++ optional (peer.endpoint != null) ''endpoint "${peer.endpoint}"''
            ++ optional (peer.persistentKeepalive != null) ''persistent-keepalive "${toString peer.persistentKeepalive}"''
            ++ optional (peer.allowedIPs != []) ''allowed-ips "${concatStringsSep "," peer.allowedIPs}"''
          );
          route_setup =
            optionalString interfaceCfg.allowedIPsAsRoutes
              (concatMapStringsSep "\n"
                (allowedIP:
                  ''${ip} route replace "${allowedIP}" dev "${interfaceName}" table "${interfaceCfg.table}" ${optionalString (interfaceCfg.metric != null) "metric ${toString interfaceCfg.metric}"}''
                ) peer.allowedIPs);
        in ''
          ${wg_setup}
          ${route_setup}

          ${optionalString (peer.dynamicEndpointRefreshSeconds != 0) ''
            # Re-execute 'wg' periodically to notice DNS / hostname changes.
            # Note this will not time out on transient DNS failures such as DNS names
            # because we have set 'WG_ENDPOINT_RESOLUTION_RETRIES=infinity'.
            # Also note that 'wg' limits its maximum retry delay to 20 seconds as of writing.
            while ${wg_setup}; do
              sleep "${toString peer.dynamicEndpointRefreshSeconds}";
            done
          ''}
        '';

        postStop = let
          route_destroy = optionalString interfaceCfg.allowedIPsAsRoutes
            (concatMapStringsSep "\n"
              (allowedIP:
                ''${ip} route delete "${allowedIP}" dev "${interfaceName}" table "${interfaceCfg.table}"''
              ) peer.allowedIPs);
        in ''
          ${wg} set "${interfaceName}" peer "${peer.publicKey}" remove
          ${route_destroy}
        '';
      };

  # the target is required to start new peer units when they are added
  generateInterfaceTarget = name: values:
    let
      mkPeerUnit = peer: (peerUnitServiceName name peer.name (peer.dynamicEndpointRefreshSeconds != 0)) + ".service";
    in
    nameValuePair "wireguard-${name}"
      rec {
        description = "WireGuard Tunnel - ${name}";
        wantedBy = [ "multi-user.target" ];
        wants = [ "wireguard-${name}.service" ] ++ map mkPeerUnit values.peers;
        after = wants;
      };

  generateInterfaceUnit = name: values:
    # exactly one way to specify the private key must be set
    #assert (values.privateKey != null) != (values.privateKeyFile != null);
    let privKey = if values.privateKeyFile != null then values.privateKeyFile else pkgs.writeText "wg-key" values.privateKey;
        src = values.socketNamespace;
        dst = values.interfaceNamespace;
        ipPreMove  = nsWrap "ip" src null;
        ipPostMove = nsWrap "ip" src dst;
        wg = nsWrap "wg" src dst;
        ns = if dst == "init" then "1" else dst;

    in
    nameValuePair "wireguard-${name}"
      {
        description = "WireGuard Tunnel - ${name}";
        after = [ "network-pre.target" ];
        wants = [ "network.target" ];
        before = [ "network.target" ];
        environment.DEVICE = name;
        path = with pkgs; [ kmod iproute2 wireguard-tools ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = concatStringsSep "\n" (
          optional (!config.boot.isContainer) "modprobe wireguard || true"
          ++ [
            values.preSetup
            ''${ipPreMove} link add dev "${name}" type wireguard''
          ]
          ++ optional (values.interfaceNamespace != null && values.interfaceNamespace != values.socketNamespace) ''${ipPreMove} link set "${name}" netns "${ns}"''
          ++ optional (values.mtu != null) ''${ipPostMove} link set "${name}" mtu ${toString values.mtu}''
          ++ (map (ip:
            ''${ipPostMove} address add "${ip}" dev "${name}"''
          ) values.ips)
          ++ [
            (concatStringsSep " " (
            [ ''${wg} set "${name}" private-key "${privKey}"'' ]
            ++ optional (values.listenPort != null) ''listen-port "${toString values.listenPort}"''
            ++ optional (values.fwMark != null) ''fwmark "${values.fwMark}"''
            ))
            ''${ipPostMove} link set up dev "${name}"''
            values.postSetup
          ]
          );

        postStop = ''
          ${ipPostMove} link del dev "${name}"
          ${values.postShutdown}
        '';
      };

  nsWrap = cmd: src: dst:
    let
      nsList = filter (ns: ns != null) [ src dst ];
      ns = last nsList;
    in
      if (length nsList > 0 && ns != "init") then ''ip netns exec "${ns}" "${cmd}"'' else cmd;
in

{

  ###### interface

  options = {

    networking.wireguard = {

      enable = mkOption {
        description = lib.mdDoc ''
          Whether to enable WireGuard.

          Please note that {option}`systemd.network.netdevs` has more features
          and is better maintained. When building new things, it is advised to
          use that instead.
        '';
        type = types.bool;
        # 2019-05-25: Backwards compatibility.
        default = cfg.interfaces != {};
        defaultText = literalExpression "config.${opt.interfaces} != { }";
        example = true;
      };

      interfaces = mkOption {
        description = lib.mdDoc ''
          WireGuard interfaces.

          Please note that {option}`systemd.network.netdevs` has more features
          and is better maintained. When building new things, it is advised to
          use that instead.
        '';
        default = {};
        example = {
          wg0 = {
            ips = [ "192.168.20.4/24" ];
            privateKey = "yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=";
            peers = [
              { allowedIPs = [ "192.168.20.1/32" ];
                publicKey  = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=";
                endpoint   = "demo.wireguard.io:12913"; }
            ];
          };
        };
        type = with types; attrsOf (submodule interfaceOpts);
      };

    };

  };


  ###### implementation

  config = mkIf cfg.enable (let
    all_peers = flatten
      (mapAttrsToList (interfaceName: interfaceCfg:
        map (peer: { inherit interfaceName interfaceCfg peer;}) interfaceCfg.peers
      ) cfg.interfaces);
  in {

    assertions = (attrValues (
        mapAttrs (name: value: {
          assertion = (value.privateKey != null) != (value.privateKeyFile != null);
          message = "Either networking.wireguard.interfaces.${name}.privateKey or networking.wireguard.interfaces.${name}.privateKeyFile must be set.";
        }) cfg.interfaces))
      ++ (attrValues (
        mapAttrs (name: value: {
          assertion = value.generatePrivateKeyFile -> (value.privateKey == null);
          message = "networking.wireguard.interfaces.${name}.generatePrivateKeyFile must not be set if networking.wireguard.interfaces.${name}.privateKey is set.";
        }) cfg.interfaces))
        ++ map ({ interfaceName, peer, ... }: {
          assertion = (peer.presharedKey == null) || (peer.presharedKeyFile == null);
          message = "networking.wireguard.interfaces.${interfaceName} peer «${peer.publicKey}» has both presharedKey and presharedKeyFile set, but only one can be used.";
        }) all_peers;

    boot.extraModulePackages = optional (versionOlder kernel.kernel.version "5.6") kernel.wireguard;
    boot.kernelModules = [ "wireguard" ];
    environment.systemPackages = [ pkgs.wireguard-tools ];

    systemd.services =
      (mapAttrs' generateInterfaceUnit cfg.interfaces)
      // (listToAttrs (map generatePeerUnit all_peers))
      // (mapAttrs' generateKeyServiceUnit
      (filterAttrs (name: value: value.generatePrivateKeyFile) cfg.interfaces));

      systemd.targets = mapAttrs' generateInterfaceTarget cfg.interfaces;
    }
  );

}
