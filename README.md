Easy leverage for G-UNI contract: https://etherscan.io/address/0xf30cE3B3564D0D12b1B240013299c7f12Fd5bd0f#writeContract

Steps are:

```
1. vat.hope(0xf30cE3B3564D0D12b1B240013299c7f12Fd5bd0f)
2. dai.approve(0xf30cE3B3564D0D12b1B240013299c7f12Fd5bd0f, AMOUNT)
3. guniLev.wind(AMOUNT, MIN_AMOUNT_EXPECTED_IN_WALLET_AFTER_TX)
4. vat.nope(0xf30cE3B3564D0D12b1B240013299c7f12Fd5bd0f)		// For safety
```

MIN_AMOUNT_EXPECTED_IN_WALLET_AFTER_TX can be gathered by querying getWindEstimates(). Use the first value returned and set it slightly below that value to deal with G-UNI slippage. You will need at least AMOUNT of Dai in your wallet. Use this at your own risk.
