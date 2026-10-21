// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PABOXO} from "../src/PABOXO.sol";

/// @dev Keeps an independent ledger across successful and rejected actions by four token holders.
contract PABOXOHandler is Test {
    PABOXO public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new PABOXO();
        actors = [makeAddr("holder 0"), makeAddr("holder 1"), makeAddr("holder 2"), makeAddr("holder 3")];
        uint256 supply = token.totalSupply();
        expectedBalance[actors[0]] = supply;
        assertTrue(token.transfer(actors[0], supply));
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, 0, allowed < balance ? allowed : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectExcessAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed == type(uint256).max) return;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, to, allowed + 1);
    }
}

contract PABOXOInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    PABOXOHandler internal handler;
    PABOXO internal token;

    function setUp() public {
        handler = new PABOXOHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = PABOXOHandler.transfer.selector;
        selectors[1] = PABOXOHandler.approve.selector;
        selectors[2] = PABOXOHandler.spend.selector;
        selectors[3] = PABOXOHandler.rejectOverspend.selector;
        selectors[4] = PABOXOHandler.rejectExcessAllowance.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_BalancesMatchLedgerAndSupplyStaysFixed() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address holder = handler.actors(i);
            uint256 balance = token.balanceOf(holder);
            assertEq(balance, handler.expectedBalance(holder));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_AllowancesMatchLedger() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
