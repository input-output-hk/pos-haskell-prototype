# If any customization is required, copy this file to
# ./custom-wallet-config.nix and make edits there.

{
  ## Wallet API server.
  #walletListen = "127.0.0.1:8090";

  ## Runtime metrics server.
  #ekgListen = "127.0.0.0.1:8000";

  ## Directory for the wallet's local state.
  #stateDir = "./state-wallet-mainnet";

  ## Used to connect to a custom set of nodes on the network. When
  ## unspecified an appropriate default topology is generated.
  #topologyFile = ./topology.yaml;

  ## See https://downloads.haskell.org/~ghc/8.0.2/docs/html/users_guide/runtime_control.html#running-a-compiled-program
  #ghcRuntimeArgs = "-N2 -qg -A1m -I0 -T";

  ## Primarily used for troubleshooting.
  #additionalArgs = "";
}
