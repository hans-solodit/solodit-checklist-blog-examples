/**
 * Overview:
 * Checklist Item ID: SOL-AM-DOSA-6
 *
 * This test demonstrates a Denial-of-Service (DOS) vulnerability in a price-dependent contract
 * where an unhandled revert from an external Chainlink price feed can block critical functions.
 * Without proper error handling using try/catch, any revert from the external feed will cascade upward
 * and halt the execution of contract functions that depend on the price data.
 */

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract MockAggregatorV3Interface is AggregatorV3Interface {
    int256 public price = 100;
    bool public shouldRevert = false;

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        if (shouldRevert) {
            revert("Chainlink reverting");
        }
        return (1, price, block.timestamp, block.timestamp, 1);
    }

    function setRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setPrice(int256 _price) external {
        price = _price;
    }
}

contract PriceDependentContract {
    AggregatorV3Interface public priceFeed;

    constructor(address _priceFeed) {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    // Vulnerable function that retrieves the price without handling potential Chainlink reverts
    function getPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData(); // Vulnerable line: No error handling
        require(price > 0, "Price must be positive");
        return uint256(price);
    }

    function calculateSomethingImportant() public view returns (uint256) {
        uint256 price = getPrice();
        // ... some important calculation using the price
        return price * 2;
    }

    function calculateSomethingImportantSafely() public view returns (uint256) {
        uint256 price;
        try priceFeed.latestRoundData() returns (
            uint80,
            int256 _price,
            uint256,
            uint256,
            uint80
        ) {
            // If the price is positive return it
            require(_price > 0, "Price must be positive");
              price = uint256(_price);
        } catch Error(string memory reason) {
            // If the price feed call fails, return a default value
            price = 100;
        } catch (bytes memory reason) {
            price = 100;
        }

        // ... some important calculation using the price
        return price * 2;
    }
}

contract PriceDependentContractTest is Test {
    PriceDependentContract public priceDependentContract;
    MockAggregatorV3Interface public mockAggregator;

    function setUp() public {
        mockAggregator = new MockAggregatorV3Interface();
        priceDependentContract = new PriceDependentContract(address(mockAggregator));
    }

    function testDoSVulnerable() public {
        // Initially, everything works fine
        assertEq(priceDependentContract.calculateSomethingImportant(), 200);

        // Simulate a Chainlink revert
        mockAggregator.setRevert(true);

        // The vulnerable function call will now revert, causing a DoS
        vm.expectRevert("Chainlink reverting");
        priceDependentContract.calculateSomethingImportant();
    }

    function testDoSFixed() public {
        // Initially, everything works fine
        assertEq(priceDependentContract.calculateSomethingImportantSafely(), 200);

        // Simulate a Chainlink revert
        mockAggregator.setRevert(true);

        // The safe function call returns a hardcoded value
        // Even though the call to price feed reverts. Avoids DOS
        assertEq(priceDependentContract.calculateSomethingImportantSafely(), 200);
    }
}