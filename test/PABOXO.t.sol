// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PABOXO} from "../src/PABOXO.sol";

contract PABOXOTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    PABOXO internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new PABOXO();
    }

    function test_MetadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "PABOXO");
        assertEq(token.symbol(), "PABOXO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        PABOXO fresh = new PABOXO();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_TransferEntireBalanceEmitsEventAndDeliversExactly() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, SUPPLY);
        assertTrue(token.transfer(alice, SUPPLY));

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferOneSmallestUnit() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalanceAndSupply() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferInsufficientBalanceRevertsWithoutMutation() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventWithoutMovingTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 200 ether);
        assertTrue(token.approve(spender, 200 ether));
        assertEq(token.allowance(address(this), spender), 200 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ApproveCanExceedBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_ApprovalRevocationPreventsFurtherSpending() public {
        token.approve(spender, 200 ether);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 100 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_TransferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        token.approve(spender, 200 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 100 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 100 ether));
        assertEq(token.allowance(address(this), spender), 100 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100 ether);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromCannotSpendAllowanceTwice() public {
        token.approve(spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_TransferFromUnlimitedAllowanceDoesNotDecreaseIt() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
    }

    function test_TransferFromInsufficientAllowanceReverts() public {
        token.approve(spender, 100);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 100, 101)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 101);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_AllowanceIsSpecificToOwnerAndSpender() public {
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);

        token.transfer(alice, 100);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(address(this), spender), 100);
    }

    function test_DeployerCannotSpendHolderBalanceWithoutApproval() public {
        token.transfer(alice, 100);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1)
        );
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 100);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_TransferFromOwnBalanceStillRequiresAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1)
        );
        token.transferFrom(address(this), alice, 1);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_TransferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        token.approve(spender, 10);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 10));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_TransferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 100));
        vm.prank(spender);
        token.transferFrom(alice, bob, 100);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToZeroRollsBackAllowance() public {
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoApproval() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_NoMintBurnUpgradeOrAdministrativeEndpoints() public {
        bytes[12] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", bob, 1),
            abi.encodeWithSignature("mint(uint256)", 1),
            abi.encodeWithSignature("burn(uint256)", 1),
            abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1),
            abi.encodeWithSignature("initialize(address)", bob),
            abi.encodeWithSignature("transferOwnership(address)", bob),
            abi.encodeWithSignature("upgradeTo(address)", bob),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", alice),
            abi.encodeWithSignature("freeze(address)", alice),
            abi.encodeWithSignature("setMinter(address)", bob),
            abi.encodeWithSignature("seize(address)", alice)
        ];
        token.transfer(alice, 100);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100);
            assertEq(token.balanceOf(bob), 0);
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
    }

    function test_RejectsNativeEther() public {
        vm.deal(address(this), 1 ether);
        (bool received,) = address(token).call{value: 1}("");
        assertFalse(received);
        (bool paidTransfer,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (alice, 1)));
        assertFalse(paidTransfer);
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferAboveBalanceReverts(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount
            )
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_ApproveReplacesPreviousValue(uint256 first, uint256 second) public {
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(spender, second));
        assertEq(token.allowance(address(this), spender), second);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_TransferFromConservesSupplyAndTracksAllowance(uint256 rawAllowance, uint256 rawAmount)
        public
    {
        uint256 allowed = bound(rawAllowance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, allowed);
        token.approve(spender, allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), allowed - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromAboveAllowanceReverts(uint256 rawAllowance, uint256 rawExcess) public {
        uint256 allowed = bound(rawAllowance, 0, SUPPLY - 1);
        uint256 amount = bound(rawExcess, allowed + 1, SUPPLY);
        token.approve(spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), allowed);
    }
}
