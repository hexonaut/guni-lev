Easy leverage for G-UNI contract: https://etherscan.io/address/0x0388c96bbd7c7a9cb128386c90987af526db85d7#writeContract

Steps are:

```
1. vat.hope(0x0388c96BBD7C7A9Cb128386c90987af526db85d7)
2. dai.approve(0x0388c96BBD7C7A9Cb128386c90987af526db85d7, AMOUNT)
3. guniLev.wind(AMOUNT, MIN_AMOUNT_EXPECTED_IN_WALLET_AFTER_TX)
4. vat.nope(0x0388c96BBD7C7A9Cb128386c90987af526db85d7)		// For safety
```

MIN_AMOUNT_EXPECTED_IN_WALLET_AFTER_TX can be gathered by querying getWindEstimates(). Use the first value returned and set it slightly below that value to deal with Curve slippage. You will need at least AMOUNT of Dai in your wallet. Use this at your own risk.