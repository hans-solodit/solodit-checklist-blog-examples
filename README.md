# Solodit Checklist Blog Examples

This repository contains minimal, working Solidity examples and Foundry-based Proof-of-Concept (PoC) exploits for each item covered in the Solodit Checklist blog series : [Solodit Checklist Explained](https://hanssolodit.substack.com/).  It's designed to provide practical, hands-on experience to complement the theoretical knowledge presented in the blog.

## About the Solodit Checklist

The [Solodit Checklist](https://solodit.cyfrin.io/checklist) is a comprehensive guide to smart contract security best practices.  This repository aims to make those best practices more accessible and understandable by demonstrating common vulnerabilities and secure coding patterns with runnable code.

## Structure
Each checklist item's PoC is named after the checklist item's ID code.
For example, the PoC for the checklist item `SOL-AM-DOSA-1` is named `SOL-AM-DOSA-1.t.sol` and is located in the `test` directory.
## Using the Repository

1.  **Install Foundry:**  Follow the instructions on the [Foundry Installation Page](https://book.getfoundry.sh/getting-started/installation). Foundry provides the tooling to compile, deploy, and test smart contracts.

2.  **Clone the Repository:**
    ```bash
    git clone https://github.com/hans-solodit/solodit-checklist-blog-examples
    cd solodit-checklist-blog-examples
    ```

3.  **Install Dependencies:**
    ```bash
    forge install
    ```

4.  **Run the Tests:**
    Use Foundry to run the tests:

    ```bash
    forge test
    ```
    To test a specific checklist item, use `--match-path` option:

    ```bash
    forge test --match-path SOL-AM-DOSA-1.t.sol
    ```

## Contributing

Contributions are welcome! If you find errors, have suggestions for improvements, or would like to add new examples, please submit a pull request.

## Disclaimer
These examples are provided for educational purposes only.