# Vikalpa

[![tests](https://github.com/dsam82/Vikalpa/actions/workflows/tests.yml/badge.svg)](https://github.com/dsam82/Vikalpa/actions/workflows/tests.yml) [![lints](https://github.com/dsam82/Vikalpa/actions/workflows/lints.yml/badge.svg)](https://github.com/dsam82/Vikalpa/actions/workflows/lints.yml)

Vikalpa is a vanilla **ERC1155** options protocol facilitating writing/buying covered calls and covered puts in European options. The contracts have been directly inspired and modified from [@0xAliciabedes's](https://twitter.com/0xAlcibiades) [Valorem Options Contracts](https://github.com/Alcibiades-Capital/valorem-options-contracts).

```bash
/*
 * Will, it be a Call or Put, Anon? You decide.
 *
 * @@@@@@@@@@@@@@@@@@@@@@@@@@@###=*#@@@@@@@
 * @@@@%.   .+%%%@@@@@@@@%%-         #@@@@@
 * @@@*           :@@@@@#     ...     -@@@@
 * @@=     ..       @@@@.   .::.:...   .@@@
 * @*  .......:.    =@@@   ..:-----:--: .@@
 * * :=++==----.    -@@#. . .:=====+++=:.-@
 * :..=**+=-==:.     @@-    .:--=-=+**+.  @
 * .  -#%*-==:...    =@:  . .==:---=#%#:  +
 *   :=@+---=--..    -@:    .%%%-:---#%+:
 * ..:+*--=+****.    :@:.   :%%%:.:::=@+-:.
 * -=++=-:.:##%-..:: .@-..:.:*%%-   ..*#*+=
 * **#%-   .+#+..:+  .@*  :-...::     -@%##
 * %%%%: .....::..=  .@@:  :. :. .::  -@@%@
 * @@@%:. .-. :+  :   @@-     -.  +.  .@@@@
 * @@@@=.  =   :  ..  @@*. :   .  -   .@@@@
 * @@@@#:. :.  :   : .@@@-...  .   .  .@@@@
 * @@@@%=:. :   .  *==@@@%**: ..   :  :@@@@
 * @@@@@#=. :.  :. +%@@@@@@@-..:. .. .-@@@@
 * @@@@@@*=:::. :..=@@@@@@@@###*:..:.:+#*@@
 * @@@@@@%###=::-#*#@@@@@@@@@@@@*+++===**#%
 * @@@@@@@@@@###*@@@@@@@@@@@@@@@@%%@%#%#=*@
 *
 */
```

## Blueprint

```other
lib
├── forge-std
└── solmate src
src
├── interfaces
│  ├── ERC1155.sol
│  └── IVikalpa.sol
├── test
│  └── Vikalpa.t.sol
└── Vikalpa.sol
```

## Structure

[Vikalpa](src/Vikalpa.sol) contains the main logic of contract. There are mainly two types of users: Writer and Buyer.

Writer can write two types of `Options`: `covered calls` or `covered puts` using collateral as ERC20 `underlying asset` depending on the position opened through option type. Options contracts are issued as ERC1155 NFTs to writer or buyer which facilitates buying and exercising of options. The design is modified from **Valorem Contracts** and thus, doesn't require use of Chainlink Price Oracles to determine `Strike Price`. The `underlyingAmount` and `exerciseAmount` is pre-defined when creating an Option.

Though, this structure is prone to volatile asset price changes but is easier to implement and doesn't depend on outside contracts.

### Functions

-   `newOption`: create new option type with `underlyingAsset` and `exerciseAsset`
-   `write`: write an option and create a position
-   `buy`: buyer buys and option from open market paying `premium` to option writer
-   `exercise`: buyer exercises options after `exerciseTimestamp`
-   `liquidate`: writer redeems unbought positions and premium for bought options

## Tests

Check [SETUP.md](SETUP.md) for seeting up repository and running tests.

## Acknowledgements

-   [Valorem Options Contracts](https://github.com/Alcibiades-Capital/valorem-options-contracts)
-   [femplate](https://github.com/abigger87/femplate)
-   [foundry](https://github.com/gakonst/foundry)
-   [solmate](https://github.com/Rari-Capital/solmate)
-   [forge-std](https://github.com/brockelmore/forge-std)

## Disclaimer

_These smart contracts are being provided as is. No guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the user interface or the smart contracts. They have not been audited and as such there can be no assurance they will work as intended, and users may experience delays, failures, errors, omissions, loss of transmitted information or loss of funds. The creators are not liable for any of the foregoing. Users should proceed with caution and use at their own risk._
