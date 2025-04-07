/**
 * Overview:
 * Checklist Item ID: SOL-AM-FrA-1
 *
 * This test demonstrates a front-running attack vulnerability in a "get-or-create" pattern.
 * An attacker can front-run a victim's transaction to create a resource with manipulated parameters
 * before the victim's transaction is executed, thus controlling the resource's initial state.
 */

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VulnerablePool {
    address public poolCreator;
    uint256 public initialPrice;

    constructor(address _poolCreator, uint256 _initialPrice) {
        poolCreator = _poolCreator;
        initialPrice = _initialPrice;
    }
}

contract ExploitableContract {
    mapping(address => VulnerablePool) public pools;

    function getOrCreatePool(address _poolCreator, uint256 _initialPrice) public returns (VulnerablePool) {
        if (address(pools[_poolCreator]) == address(0)) {
            // Vulnerability: An attacker can front-run this transaction with different initialPrice
            pools[_poolCreator] = new VulnerablePool(_poolCreator, _initialPrice);
        }
        return pools[_poolCreator];
    }

    function viewPoolInitialPrice(address _poolCreator) public view returns (uint256) {
       if(address(pools[_poolCreator]) != address(0)) {
        return pools[_poolCreator].initialPrice();
       } else {
        return 0;
       }
    }
}

contract FrontRunningTest is Test {
    ExploitableContract public exploitableContract;
    address public victim;
    address public attacker;

    function setUp() public {
        exploitableContract = new ExploitableContract();
        victim = address(1);
        attacker = address(2);

        vm.deal(victim, 10 ether);
        vm.deal(attacker, 10 ether);
    }

    function testFrontRunning() public {
        uint256 intendedPrice = 100;
        uint256 attackPrice = 50;

        // 1. Victim intends to create a pool with initialPrice = intendedPrice
        vm.startPrank(victim);
        // exploitableContract.getOrCreatePool(victim, intendedPrice); //Simulate that the victim is about to call this.

        // 2. Attacker observes this transaction and front-runs it with attackPrice
        vm.stopPrank();
        vm.startPrank(attacker);
        exploitableContract.getOrCreatePool(victim, attackPrice);
        vm.stopPrank();

        // 3. Victim's transaction now executes
        vm.startPrank(victim);
        exploitableContract.getOrCreatePool(victim, intendedPrice); // This call should not change the price because the pool already exists

        // 4. Assert that the pool's initialPrice is now the attacker's price, NOT the victim's intended price
        assertEq(exploitableContract.viewPoolInitialPrice(victim), attackPrice, "The pool's initial price should be the attacker's price.");
        vm.stopPrank();
    }
}