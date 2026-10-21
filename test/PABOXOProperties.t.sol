// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PABOXO} from "src/PABOXO.sol";

/// @notice Boundary, rollback, and round-trip properties supplementing the basic ERC-20 tests.
/// @dev All balances are established by real transfers, never by editing token storage.
/// forge-config: default.fuzz.runs = 1024
contract PABOXOPropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PABOXO internal token;
    address internal alice = makeAddr("property holder");
    address internal bob = makeAddr("property recipient");
    address internal spender = makeAddr("property spender");
    address internal otherSpender = makeAddr("other property spender");

    function setUp() public {
        token = new PABOXO();
    }

    function test_MaximumFiniteAllowanceIsNotUnlimited() public {
        uint256 allowed = type(uint256).max - 1;
        assertTrue(token.approve(spender, allowed));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), allowed - 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), allowed - SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_UnlimitedApprovalCanBeReducedThenRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.approve(spender, 2));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 3);
        assertEq(token.allowance(address(this), spender), 2);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 0);

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferStillRejectsMoreThanTheBalance() public {
        uint256[2] memory amounts = [SUPPLY + 1, type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amounts[i]
                )
            );
            token.transfer(address(this), amounts[i]);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_MaximumDelegatedSelfTransferRevertsWithoutConsumingApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(this), type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
    }

    function test_ZeroDelegatedTransferToZeroAddressIsRejected() public {
        uint256[3] memory approvals = [uint256(0), uint256(1), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            assertTrue(token.approve(spender, approvals[i]));
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), spender), approvals[i]);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_ZeroOwnerCannotBeUsedForADelegatedMint() public {
        // Even a zero amount must reject an invalid owner. OpenZeppelin checks
        // that owner while spending the allowance, before reaching _transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), bob, 0);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(0), bob, 1);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferPreservesNonzeroApprovals() public {
        uint256[3] memory approvals = [uint256(1), type(uint256).max - 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(alice);
            assertTrue(token.approve(spender, approvals[i]));
            vm.prank(spender);
            assertTrue(token.transferFrom(alice, bob, 0));
            assertEq(token.allowance(alice, spender), approvals[i]);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(bob), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_DirectTransferDoesNotConsumeApprovalForLaterReceipts() public {
        assertTrue(token.approve(spender, SUPPLY));
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), SUPPLY);

        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedBalanceCheckLeavesApprovalUsableAfterTopUp(
        uint256 balanceSeed,
        uint256 amountSeed,
        uint256 allowanceSeed,
        bool unlimited
    ) public {
        uint256 held = bound(balanceSeed, 0, SUPPLY - 1);
        uint256 amount = bound(amountSeed, held + 1, SUPPLY);
        uint256 allowed = unlimited ? type(uint256).max : bound(allowanceSeed, amount, type(uint256).max - 1);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(spender, allowed));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), allowed);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.totalSupply(), SUPPLY);

        assertTrue(token.transfer(alice, amount - held));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), unlimited ? allowed : allowed - amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidReceiverLeavesApprovalUsableForRetry(
        uint256 amountSeed,
        uint256 allowanceSeed,
        bool unlimited
    ) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 allowed = unlimited ? type(uint256).max : bound(allowanceSeed, amount, type(uint256).max - 1);
        assertTrue(token.approve(spender, allowed));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), allowed);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), unlimited ? allowed : allowed - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SpendersCompeteForBalanceWithoutConsumingEachOthersAllowances(uint256 amountSeed)
        public
    {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        vm.startPrank(alice);
        assertTrue(token.approve(spender, amount));
        assertTrue(token.approve(otherSpender, amount));
        vm.stopPrank();

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, otherSpender), amount);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, amount)
        );
        vm.prank(otherSpender);
        token.transferFrom(alice, otherSpender, amount);
        assertEq(token.allowance(alice, otherSpender), amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(otherSpender), 0);

        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(alice, otherSpender, amount));
        assertEq(token.allowance(alice, otherSpender), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(otherSpender), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedRoundTripRestoresBalancesButNotAllowance(
        uint256 heldSeed,
        uint256 amountSeed,
        uint256 allowanceSeed
    ) public {
        uint256 held = bound(heldSeed, 1, SUPPLY);
        uint256 amount = bound(amountSeed, 0, held);
        uint256 allowed = bound(allowanceSeed, amount, type(uint256).max - 1);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(spender, allowed));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.balanceOf(alice), held - amount);
        assertEq(token.balanceOf(bob), amount);

        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.allowance(alice, spender), allowed - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedTransfersEqualOneTransfer(uint256 totalSeed, uint256 partSeed) public {
        uint256 total = bound(totalSeed, 0, SUPPLY);
        uint256 first = bound(partSeed, 0, total);
        PABOXO split = new PABOXO();
        assertTrue(token.approve(spender, total));
        assertTrue(split.approve(spender, total));

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, total));
        assertTrue(split.transferFrom(address(this), alice, first));
        assertTrue(split.transferFrom(address(this), alice, total - first));
        vm.stopPrank();

        // Both paths must also match the specification; equality alone could
        // conceal an identical mistake in both executions.
        assertEq(token.balanceOf(alice), total);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(split.balanceOf(alice), token.balanceOf(alice));
        assertEq(split.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(split.allowance(address(this), spender), 0);
        assertEq(split.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
