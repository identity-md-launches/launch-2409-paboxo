// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PABOXO} from "../src/PABOXO.sol";

/// @dev Keeps an independent ledger across successful and rejected actions by four token holders.
contract PABOXOHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PABOXO public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new PABOXO();
        actors = [makeAddr("holder 0"), makeAddr("holder 1"), makeAddr("holder 2"), makeAddr("holder 3")];
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        // Start every actor funded so randomly selected senders can move value.
        // The ghost ledger starts from the required supply, not the token's getter.
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = SUPPLY / actors.length;
            assertTrue(token.transfer(actors[i], SUPPLY / actors.length));
        }
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

    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 boundarySeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[5] memory amounts =
            [uint256(0), uint256(1), expectedBalance[owner], type(uint256).max - 1, type(uint256).max];
        uint256 amount = amounts[boundarySeed % amounts.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function revokeAndReject(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function rejectInvalidReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 held = expectedBalance[owner];
        uint256 amount = bound(amountSeed, 0, allowed < held ? allowed : held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
        // No ghost update: the attempted allowance deduction must roll back.
    }

    function rejectApprovedOverspend(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 held = expectedBalance[owner];
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max - 1);
        uint256 allowed = unlimited ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, allowed));
        expectedAllowance[owner][spender] = allowed;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, amount);
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        // A funded sender always exists because these actors retain the full supply.
        // Search the ghost ledger to keep this action useful even after full-balance transfers.
        uint256 index = fromSeed % actors.length;
        for (uint256 i; i < actors.length && expectedBalance[actors[index]] == 0; ++i) {
            index = (index + 1) % actors.length;
        }
        address from = actors[index];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 1, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), expectedBalance[from] - (from == to ? 0 : amount));
        assertEq(token.balanceOf(to), expectedBalance[to] + (from == to ? 0 : amount));
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // The round trip must leave both the balance and allowance ledgers unchanged.
        assertEq(token.balanceOf(from), expectedBalance[from]);
        assertEq(token.balanceOf(to), expectedBalance[to]);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PABOXOInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    PABOXOHandler internal handler;
    PABOXO internal token;

    function setUp() public {
        handler = new PABOXOHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = PABOXOHandler.transfer.selector;
        selectors[1] = PABOXOHandler.approve.selector;
        selectors[2] = PABOXOHandler.spend.selector;
        selectors[3] = PABOXOHandler.rejectOverspend.selector;
        selectors[4] = PABOXOHandler.rejectExcessAllowance.selector;
        selectors[5] = PABOXOHandler.approveBoundary.selector;
        selectors[6] = PABOXOHandler.revokeAndReject.selector;
        selectors[7] = PABOXOHandler.rejectInvalidReceiver.selector;
        selectors[8] = PABOXOHandler.rejectApprovedOverspend.selector;
        selectors[9] = PABOXOHandler.roundTrip.selector;
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

    function invariant_MetadataStaysFixed() public view {
        assertEq(token.name(), "PABOXO");
        assertEq(token.symbol(), "PABOXO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    function afterInvariant() public {
        // At the end of every random sequence every holder must still be able to
        // transfer its entire balance. Check exact arrival, including one-wei dust.
        invariant_BalancesMatchLedgerAndSupplyStaysFixed();
        uint256 collected;
        for (uint256 i; i < 4; ++i) {
            address holder = handler.actors(i);
            uint256 amount = handler.expectedBalance(holder);
            vm.prank(holder);
            assertTrue(token.transfer(address(this), amount));
            collected += amount;
            assertEq(token.balanceOf(holder), 0);
            assertEq(token.balanceOf(address(this)), collected);
        }
        assertEq(collected, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        invariant_AllowancesMatchLedger();
        invariant_MetadataStaysFixed();
    }

    function test_HandlerExercisesNonzeroSpendsAndRollbackBoundaries() public {
        uint256 initial = SUPPLY / 4;
        address owner = handler.actors(0);
        address spender = handler.actors(1);
        address recipient = handler.actors(2);

        handler.approveBoundary(0, 1, 4); // Unlimited approval.
        handler.spend(0, 1, 2, 1);
        assertEq(token.balanceOf(recipient), initial + 1);
        assertEq(token.allowance(owner, spender), type(uint256).max);
        handler.rejectInvalidReceiver(0, 1, 1);
        handler.revokeAndReject(0, 1, 2);
        assertEq(token.allowance(owner, spender), 0);

        handler.approveBoundary(0, 1, 3); // Largest finite approval.
        handler.rejectInvalidReceiver(0, 1, 1);
        handler.spend(0, 1, 2, 1);
        assertEq(token.allowance(owner, spender), type(uint256).max - 2);
        handler.rejectApprovedOverspend(0, 1, SUPPLY, false);
        assertEq(token.allowance(owner, spender), SUPPLY);
        handler.spend(0, 1, 2, initial - 2); // Empty the original holder.
        assertEq(token.balanceOf(owner), 0);
        handler.roundTrip(0, 3, 1); // Must find another funded sender.
        handler.rejectApprovedOverspend(0, 1, 1, true);

        invariant_BalancesMatchLedgerAndSupplyStaysFixed();
        invariant_AllowancesMatchLedger();
        invariant_MetadataStaysFixed();
        afterInvariant();
    }
}
