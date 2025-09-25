# Foundry DeFi Stablecoin

A decentralized stablecoin protocol built with Solidity and Foundry. This project is part of my learning journey in smart contract development, inspired by DeFi primitives like MakerDAO and Aave.

## About

This project is meant to be a stablecoin where users can deposit WETH and WBTC in exchange for a token that will be pegged to the USD.

## Features

- Collateralized Stablecoin — mint a stablecoin backed by crypto collateral.

- Secure Collateral Management — deposit and withdraw collateral safely.

- Overcollateralization — ensures stability and reduces liquidation risks.

- Comprehensive Testing — written with Foundry for speed and reliability.

- Gas-Efficient Design — optimized smart contract patterns.

## Tech Stack

- [Solidity](https://soliditylang.org/)
 — Smart contracts

- [Foundry](https://getfoundry.sh/)
 — Development, testing, and deployment

- [Chainlink](https://chain.link/)
 — Price feeds (for collateral valuations)

- [OpenZeppelin](https://www.openzeppelin.com/contracts)
 — Secure, audited contract libraries


 # Getting Started

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)`

## Quickstart

```
git clone https://github.com/Cyfrin/foundry-defi-stablecoin-cu
cd foundry-defi-stablecoin-cu
forge build
```

### Optional Gitpod

If you can't or don't want to run and install locally, you can work with this repo in Gitpod. If you do this, you can skip the `clone this repo` part.

[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#github.com/PatrickAlphaC/foundry-smart-contract-lottery-cu)

# Updates

- The latest version of openzeppelin-contracts has changes in the ERC20Mock file. To follow along with the course, you need to install version 4.8.3 which can be done by `forge install openzeppelin/openzeppelin-contracts@v4.8.3 --no-commit` instead of `forge install openzeppelin/openzeppelin-contracts --no-commit`

# Usage

## Start a local node

```
make anvil
```

## Deploy

This will default to your local node. You need to have it running in another terminal in order for it to deploy.

```
make deploy
```

# Contributing

Contributions are welcome! Feel free to open an issue or submit a PR.

# License

This project is licensed under the MIT License.

# Thank you!

If you appreciated this, feel free to follow me!



[![Akinjeji Oluwaferanmi Twitter](https://img.shields.io/badge/Twitter-1DA1F2?style=for-the-badge&logo=twitter&logoColor=white)](https://x.com/feranmiakinjeji)