all    :; dapp --use solc:0.8.6 build
clean  :; dapp clean
test   :; dapp --use solc:0.8.6 test -v --rpc
deploy :; dapp create GuniLev
