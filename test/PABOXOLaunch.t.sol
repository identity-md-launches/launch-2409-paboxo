// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PABOXO} from "../src/PABOXO.sol";

/// @dev Test scaffold only: models a factory deploying and distributing a token.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (PABOXO) {
        return new PABOXO{salt: salt}();
    }

    function move(PABOXO token, address to, uint256 amount) external {
        require(token.transfer(to, amount), "transfer failed");
    }
}

contract PABOXOLaunchTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    TokenFactoryHarness internal factory;

    function setUp() public {
        factory = new TokenFactoryHarness();
    }

    function test_Create2MintsEverythingToImmediateDeployer() public {
        address caller = makeAddr("factory caller");
        address origin = makeAddr("transaction origin");
        bytes32 salt = keccak256("PABOXO deployment test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(PABOXO).creationCode)
                        )
                    )
                )
            )
        );

        vm.prank(caller, origin);
        PABOXO token = factory.deploy(salt);
        assertEq(address(token), predicted);
        assertGt(address(token).code.length, 0);
        assertLe(address(token).code.length, 24_576);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(caller), 0);
        assertEq(token.balanceOf(origin), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_DistributionClaimsAndBidirectionalPoolTransfersDeliverExactAmounts() public {
        PABOXO token = factory.deploy(keccak256("distribution test"));
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool token custodian");
        address recipient = makeAddr("remainder recipient");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");

        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY / 2;
        uint256 remainder = SUPPLY - swarmShare - poolShare;
        factory.move(token, distributor, swarmShare);
        factory.move(token, pool, poolShare);
        factory.move(token, recipient, remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarmShare);
        assertEq(token.balanceOf(pool), poolShare);
        assertEq(token.balanceOf(recipient), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarmShare));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarmShare);

        // Exercises only the token movement used by buys and sells, not AMM pricing or settlement.
        uint256 traded = 123 ether;
        vm.prank(pool);
        assertTrue(token.transfer(trader, traded));
        assertEq(token.balanceOf(trader), traded);
        assertEq(token.balanceOf(pool), poolShare - traded);
        vm.prank(trader);
        assertTrue(token.transfer(pool, traded));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), poolShare);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
