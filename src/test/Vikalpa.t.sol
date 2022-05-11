// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "@std/Test.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {IVikalpa} from "../interfaces/IVikalpa.sol";
import {ERC1155TokenReceiver} from "../interfaces/ERC1155.sol";
import {Vikalpa} from "../Vikalpa.sol";

contract ERC1155Recipient is ERC1155TokenReceiver {}

contract TestVikalpa is Test, ERC1155TokenReceiver {
    uint256 public constant tokenBalance = 10000000e18;
    address public mockUser = address(new ERC1155Recipient());

    Vikalpa public vikalpa;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    IVikalpa.Option public mockOption =
        IVikalpa.Option({
            underlyingAsset: address(tokenA),
            underlyingAmount: 100e18,
            exerciseAsset: address(tokenB),
            exerciseAmount: 1000e18,
            premium: 5e17,
            expiryTimestamp: uint32(block.timestamp + 2 days),
            exerciseTimestamp: uint32(block.timestamp + 1 days),
            randomSeed: 123456789,
            optionType: true
        });

    function setUp() public {
        // deploy option engine
        vikalpa = new Vikalpa();

        // create tokens
        tokenA = new MockERC20("TKNA", "Token A", 18);
        tokenB = new MockERC20("TKNB", "Token B", 18);

        // mint tokens
        tokenA.mint(address(this), tokenBalance);
        tokenB.mint(address(this), tokenBalance);
        tokenA.mint(mockUser, tokenBalance);
        tokenB.mint(mockUser, tokenBalance);

        // set approvals
        tokenA.approve(address(vikalpa), tokenBalance);
        tokenB.approve(address(vikalpa), tokenBalance);

        vm.startPrank(mockUser);
        tokenA.approve(address(vikalpa), tokenBalance);
        tokenB.approve(address(vikalpa), tokenBalance);
        vm.stopPrank();
    }

    function setUpCallOption() public returns (uint256) {
        IVikalpa.Option memory option = IVikalpa.Option({
            underlyingAsset: address(tokenA),
            underlyingAmount: 100e18,
            exerciseAsset: address(tokenB),
            exerciseAmount: 1000e18,
            premium: 5e17,
            expiryTimestamp: uint32(block.timestamp + 2 days),
            exerciseTimestamp: uint32(block.timestamp + 1 days),
            randomSeed: 123456789,
            optionType: true
        });

        return vikalpa.newOption(option);
    }

    function setUpPutOption() public returns (uint256) {
        IVikalpa.Option memory option = IVikalpa.Option({
            underlyingAsset: address(tokenA),
            underlyingAmount: 100e18,
            exerciseAsset: address(tokenB),
            exerciseAmount: 1000e18,
            premium: 5e17,
            expiryTimestamp: uint32(block.timestamp + 2 days),
            exerciseTimestamp: uint32(block.timestamp + 1 days),
            randomSeed: 123456789,
            optionType: false
        });

        return vikalpa.newOption(option);
    }

    function setUpBuyCallOption(uint256 amount)
        public
        returns (uint256 optionId, uint256 positionId)
    {
        optionId = setUpCallOption();
        positionId = vikalpa.write(optionId, uint80(100));

        vikalpa.setApprovalForAll(address(mockUser), true);

        vm.prank(mockUser);
        vikalpa.buy(optionId, uint80(amount));
    }

    function setUpBuyPutOption(uint256 amount)
        public
        returns (uint256 optionId, uint256 positionId)
    {
        optionId = setUpPutOption();
        positionId = vikalpa.write(optionId, uint80(100));

        vikalpa.setApprovalForAll(address(mockUser), true);

        vm.prank(mockUser);
        vikalpa.buy(optionId, uint80(amount));
    }

    function assertOption(uint256 optionId, IVikalpa.Option memory expected)
        public
    {
        IVikalpa.Option memory actual = vikalpa.getOption(optionId);

        assertEq(actual.underlyingAsset, expected.underlyingAsset);
        assertEq(actual.underlyingAmount, expected.underlyingAmount);
        assertEq(actual.exerciseAsset, expected.exerciseAsset);
        assertEq(actual.exerciseAmount, expected.exerciseAmount);
        assertEq(actual.premium, expected.premium);
        assertEq(actual.expiryTimestamp, expected.expiryTimestamp);
        assertEq(actual.exerciseTimestamp, expected.exerciseTimestamp);
    }

    function assertPosition(
        uint256 positionId,
        IVikalpa.Position memory expected
    ) public {
        IVikalpa.Position memory actual = vikalpa.getPosition(positionId);

        assertEq(actual.optionId, expected.optionId);
        assertEq(actual.amountWritten, expected.amountWritten);
        assertEq(actual.amountBought, expected.amountBought);
        assertEq(actual.amountExercised, expected.amountExercised);
        assertEq(actual.writer, expected.writer);
        assertEq(actual.liquidated, expected.liquidated);
    }

    function testNewOption() public {
        IVikalpa.Option memory option = IVikalpa.Option({
            underlyingAsset: address(tokenA),
            underlyingAmount: 100e18,
            exerciseAsset: address(tokenB),
            exerciseAmount: 1000e18,
            premium: 5e17,
            expiryTimestamp: uint32(block.timestamp + 2 days),
            exerciseTimestamp: uint32(block.timestamp + 1 days),
            randomSeed: 123456789,
            optionType: true
        });

        uint256 optionId = vikalpa.newOption(option);

        assertEq(optionId, 1);
    }

    function testNewOptionMultiple() public {
        uint256 optionId = setUpCallOption();
        optionId = setUpPutOption();

        assertEq(optionId, 2);

        IVikalpa.Option memory option = vikalpa.getOption(1);
        assertEq(option.optionType, true);

        option = vikalpa.getOption(2);
        assertEq(option.optionType, false);
    }

    function testWriteCallOption() public {
        uint256 optionId = setUpCallOption();

        uint256 positionId = vikalpa.write(optionId, uint80(100));

        IVikalpa.Option memory option = vikalpa.getOption(optionId);

        assertGt(positionId, 0);
        assertPosition(
            positionId,
            IVikalpa.Position({
                optionId: optionId,
                amountWritten: uint80(100),
                amountBought: uint80(0),
                amountExercised: uint80(0),
                writer: address(this),
                liquidated: false
            })
        );

        // Call option, underlying asset is tokenA, exercise asset is tokenB
        assertEq(
            tokenA.balanceOf(address(this)),
            tokenBalance - (uint80(100) * option.underlyingAmount)
        );
        assertEq(
            tokenA.balanceOf(address(vikalpa)),
            uint80(100) * option.underlyingAmount
        );
        assertEq(tokenB.balanceOf(address(this)), tokenBalance);
        assertEq(tokenB.balanceOf(address(vikalpa)), 0);

        // check ERC1155 balance

        address[] memory owners = new address[](2);
        owners[0] = address(this);
        owners[1] = address(this);

        uint256[] memory tokens = new uint256[](2);
        tokens[0] = optionId;
        tokens[1] = positionId;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = uint80(100);
        amounts[1] = uint80(1);

        uint256[] memory balances = vikalpa.balanceOfBatch(owners, tokens);

        for (uint256 i; i < 2; i++) {
            assertEq(balances[i], amounts[i]);
        }

        assertEq(vikalpa.unboughtPositionByOptions(optionId, 0), positionId);
    }

    function testWritePutOption() public {
        uint256 optionId = setUpPutOption();

        uint256 positionId = vikalpa.write(optionId, uint80(100));

        IVikalpa.Option memory option = vikalpa.getOption(optionId);

        assertGt(positionId, 0);
        assertPosition(
            positionId,
            IVikalpa.Position({
                optionId: optionId,
                amountWritten: uint80(100),
                amountBought: uint80(0),
                amountExercised: uint80(0),
                writer: address(this),
                liquidated: false
            })
        );

        // Put option, underlying asset is tokenA, exercise asset is tokenB
        assertEq(tokenA.balanceOf(address(this)), tokenBalance);
        assertEq(tokenA.balanceOf(address(vikalpa)), 0);

        assertOption(optionId, option);

        assertEq(
            tokenB.balanceOf(address(this)),
            tokenBalance - (uint80(100) * option.exerciseAmount)
        );
        assertEq(
            tokenB.balanceOf(address(vikalpa)),
            uint80(100) * option.exerciseAmount
        );

        assertEq(vikalpa.unboughtPositionByOptions(optionId, 0), positionId);
    }

    function testWriteMultiple() public {
        uint256 optionId1 = setUpCallOption();
        uint256 positionId1 = vikalpa.write(optionId1, uint80(100));
        IVikalpa.Option memory option1 = vikalpa.getOption(optionId1);

        uint256 optionId2 = setUpPutOption();
        uint256 positionId2 = vikalpa.write(optionId2, uint80(100));
        IVikalpa.Option memory option2 = vikalpa.getOption(optionId2);

        // 2 options + 2 position
        assertEq(positionId2, 4);

        assertEq(
            tokenA.balanceOf(address(this)),
            tokenBalance - (uint80(100) * option1.underlyingAmount)
        );
        assertEq(
            tokenA.balanceOf(address(vikalpa)),
            uint80(100) * option1.underlyingAmount
        );

        assertEq(
            tokenB.balanceOf(address(this)),
            tokenBalance - (uint80(100) * option2.exerciseAmount)
        );
        assertEq(
            tokenB.balanceOf(address(vikalpa)),
            uint80(100) * option2.exerciseAmount
        );

        assertOption(optionId1, option1);
        assertOption(optionId2, option2);

        assertEq(vikalpa.unboughtPositionByOptions(optionId1, 0), positionId1);
        assertEq(vikalpa.unboughtPositionByOptions(optionId2, 0), positionId2);
    }

    function testWriteMultipleSameOption() public {
        uint256 optionId = setUpCallOption();
        uint256 positionId = vikalpa.write(optionId, uint80(100));
        positionId = vikalpa.write(optionId, uint80(10));

        IVikalpa.Option memory option = vikalpa.getOption(optionId);

        // 1 option + 2 position
        assertEq(positionId, 3);

        assertEq(
            tokenA.balanceOf(address(this)),
            tokenBalance - (uint80(110) * option.underlyingAmount)
        );
        assertEq(
            tokenA.balanceOf(address(vikalpa)),
            uint80(110) * option.underlyingAmount
        );

        assertOption(optionId, option);

        assertEq(vikalpa.balanceOf(address(this), optionId), 110);
        assertEq(vikalpa.balanceOf(address(this), positionId), 1);
        assertEq(tokenB.balanceOf(address(this)), tokenBalance);
        assertEq(tokenB.balanceOf(address(vikalpa)), 0);

        assertEq(vikalpa.unboughtPositionByOptions(optionId, 1), positionId);
    }

    function testBuyCall() public {
        uint256 optionId = setUpCallOption();
        uint256 positionId = vikalpa.write(optionId, uint80(100));

        vikalpa.setApprovalForAll(address(mockUser), true);

        IVikalpa.Position memory position = vikalpa.getPosition(positionId);

        vm.prank(mockUser);
        vikalpa.buy(optionId, position.amountWritten);

        IVikalpa.Option memory option = vikalpa.getOption(optionId);
        position = vikalpa.getPosition(positionId);

        assertPosition(positionId, position);
        assertOption(optionId, option);
        assertEq(vikalpa.balanceOf(address(mockUser), optionId), 100);
        assertEq(vikalpa.balanceOf(address(this), optionId), 0);
        assertEq(
            tokenB.balanceOf(address(vikalpa)),
            option.premium * uint80(100)
        );
        assertEq(
            vikalpa.unexercisedPositionsByAccount(address(mockUser), 0),
            2
        );
    }

    function testBuyPut() public {
        uint256 optionId = setUpPutOption();
        uint256 positionId = vikalpa.write(optionId, uint80(100));

        vikalpa.setApprovalForAll(address(mockUser), true);

        IVikalpa.Position memory position = vikalpa.getPosition(positionId);

        vm.prank(mockUser);
        vikalpa.buy(optionId, position.amountWritten);

        IVikalpa.Option memory option = vikalpa.getOption(optionId);
        position = vikalpa.getPosition(positionId);

        assertPosition(positionId, position);
        assertOption(optionId, option);
        assertEq(vikalpa.balanceOf(address(mockUser), optionId), 100);
        assertEq(vikalpa.balanceOf(address(this), optionId), 0);
        assertEq(
            tokenB.balanceOf(address(vikalpa)),
            (option.premium * uint80(100)) +
                (option.exerciseAmount * uint80(100))
        );
        assertEq(
            vikalpa.unexercisedPositionsByAccount(address(mockUser), 0),
            2
        );
    }

    function testBuyPartial() public {
        uint256 optionId = setUpCallOption();
        uint256 positionId = vikalpa.write(optionId, uint80(100));

        vikalpa.setApprovalForAll(address(mockUser), true);

        vm.prank(mockUser);
        vikalpa.buy(optionId, uint80(50));

        IVikalpa.Option memory option = vikalpa.getOption(optionId);
        IVikalpa.Position memory position = vikalpa.getPosition(positionId);

        assertPosition(positionId, position);
        assertOption(optionId, option);

        assertEq(vikalpa.balanceOf(address(mockUser), optionId), 50);
        assertEq(vikalpa.balanceOf(address(this), optionId), 50);
        assertEq(vikalpa.unboughtPositionByOptions(optionId, 0), positionId);

        assertEq(
            tokenB.balanceOf(address(vikalpa)),
            (option.premium * uint80(50))
        );
        assertEq(
            vikalpa.unexercisedPositionsByAccount(address(mockUser), 0),
            2
        );
    }

    function testBuyMultipleSameOption() public {
        uint256 optionId = setUpCallOption();
        uint256 positionId = vikalpa.write(optionId, uint80(100));

        vikalpa.setApprovalForAll(address(mockUser), true);

        vm.startPrank(mockUser);
        vikalpa.buy(optionId, uint80(30));
        vikalpa.buy(optionId, uint80(30));
        vm.stopPrank();

        IVikalpa.Option memory option = vikalpa.getOption(optionId);
        IVikalpa.Position memory position = vikalpa.getPosition(positionId);

        assertPosition(positionId, position);
        assertOption(optionId, option);

        assertEq(
            tokenB.balanceOf(address(vikalpa)),
            (option.premium * uint80(30)) * uint80(2)
        );
        assertEq(
            vikalpa.unexercisedPositionsByAccount(address(mockUser), 0),
            2
        );
        assertEq(
            vikalpa.unexercisedPositionsByAccount(address(mockUser), 1),
            2
        );
    }

    function testBuyMultiplePositions() public {
        uint256 optionId = setUpCallOption();
        uint256 positionId = vikalpa.write(optionId, uint80(10));
        uint256 positionId2 = vikalpa.write(optionId, uint80(10));
        uint256 positionId3 = vikalpa.write(optionId, uint80(100));

        assertEq(vikalpa.unboughtPositionByOptions(optionId, 0), positionId);
        assertEq(vikalpa.unboughtPositionByOptions(optionId, 1), positionId2);
        assertEq(vikalpa.unboughtPositionByOptions(optionId, 2), positionId3);

        vikalpa.setApprovalForAll(address(mockUser), true);

        vm.prank(mockUser);
        vikalpa.buy(optionId, uint80(40));

        IVikalpa.Option memory option = vikalpa.getOption(optionId);

        // check ERC1155 NFT balances
        assertEq(vikalpa.balanceOf(address(mockUser), optionId), 40);
        assertEq(vikalpa.balanceOf(address(this), optionId), 80);

        // check token balances
        assertEq(
            tokenB.balanceOf(address(vikalpa)),
            option.premium * uint80(40)
        );
    }

    function testExercise() public {
        (uint256 optionId, uint256 positionId) = setUpBuyCallOption(100);

        IVikalpa.Option memory option = vikalpa.getOption(optionId);

        vm.warp(option.exerciseTimestamp + 1);
        vm.prank(mockUser);
        vikalpa.exercise(optionId, uint80(100));

        IVikalpa.Position memory position = vikalpa.getPosition(positionId);

        // check NFT balances
        assertEq(vikalpa.balanceOf(address(mockUser), optionId), 0);
        assertEq(vikalpa.balanceOf(address(this), optionId), 0);

        // check position exercise amount
        assertEq(position.amountExercised, 100);

        // check token Balances
        assertEq(tokenA.balanceOf(address(vikalpa)), 0);
        assertEq(
            tokenA.balanceOf(address(mockUser)),
            tokenBalance + option.underlyingAmount * 100
        );
        assertEq(
            tokenB.balanceOf(address(vikalpa)),
            (option.premium + option.exerciseAmount) * 100
        );
        assertEq(
            tokenB.balanceOf(address(mockUser)),
            tokenBalance - ((option.premium + option.exerciseAmount) * 100)
        );
    }

    function testExercisePut() public {
        (uint256 optionId, uint256 positionId) = setUpBuyPutOption(100);

        IVikalpa.Option memory option = vikalpa.getOption(optionId);

        vm.warp(option.exerciseTimestamp + 1);
        vm.prank(mockUser);
        vikalpa.exercise(optionId, uint80(100));

        IVikalpa.Position memory position = vikalpa.getPosition(positionId);

        // check NFT balances
        assertEq(vikalpa.balanceOf(address(mockUser), optionId), 0);
        assertEq(vikalpa.balanceOf(address(this), optionId), 0);

        // check position exercise amount
        assertEq(position.amountExercised, 100);

        // check token Balances
        assertEq(
            tokenA.balanceOf(address(vikalpa)),
            option.underlyingAmount * 100
        );
        assertEq(
            tokenA.balanceOf(address(mockUser)),
            tokenBalance - option.underlyingAmount * 100
        );
        assertEq(tokenB.balanceOf(address(vikalpa)), option.premium * 100);
        assertEq(
            tokenB.balanceOf(address(mockUser)),
            tokenBalance + option.exerciseAmount * 100 - option.premium * 100
        );
    }

    function testExercisePartial() public {
        (uint256 optionId, uint256 positionId) = setUpBuyCallOption(100);

        IVikalpa.Option memory option = vikalpa.getOption(optionId);

        vm.warp(option.exerciseTimestamp + 1);
        vm.prank(mockUser);
        vikalpa.exercise(optionId, uint80(50));

        IVikalpa.Position memory position = vikalpa.getPosition(positionId);

        // check NFT balances
        assertEq(vikalpa.balanceOf(address(mockUser), optionId), 50);
        assertEq(vikalpa.balanceOf(address(this), optionId), 0);

        // check position exercise amount
        assertEq(position.amountExercised, 50);

        // check token Balances
        assertEq(
            tokenA.balanceOf(address(vikalpa)),
            option.underlyingAmount * 50
        );
        assertEq(
            tokenA.balanceOf(address(mockUser)),
            tokenBalance + option.underlyingAmount * 50
        );
        assertEq(
            tokenB.balanceOf(address(vikalpa)),
            option.premium * 100 + option.exerciseAmount * 50
        );
        assertEq(
            tokenB.balanceOf(address(mockUser)),
            tokenBalance - option.exerciseAmount * 50 - option.premium * 100
        );
    }

    function testExercisePartialPut() public {
        (uint256 optionId, uint256 positionId) = setUpBuyPutOption(100);

        IVikalpa.Option memory option = vikalpa.getOption(optionId);

        vm.warp(option.exerciseTimestamp + 1);
        vm.prank(mockUser);
        vikalpa.exercise(optionId, uint80(50));

        IVikalpa.Position memory position = vikalpa.getPosition(positionId);

        // check NFT balances
        assertEq(vikalpa.balanceOf(address(mockUser), optionId), 50);
        assertEq(vikalpa.balanceOf(address(this), optionId), 0);

        // check position exercise amount
        assertEq(position.amountExercised, 50);

        // check token Balances
        assertEq(
            tokenA.balanceOf(address(vikalpa)),
            option.underlyingAmount * 50
        );
        assertEq(
            tokenA.balanceOf(address(mockUser)),
            tokenBalance - option.underlyingAmount * 50
        );
        assertEq(
            tokenB.balanceOf(address(vikalpa)),
            option.premium * 100 + option.exerciseAmount * 50
        );
        assertEq(
            tokenB.balanceOf(address(mockUser)),
            tokenBalance + option.exerciseAmount * 50 - option.premium * 100
        );
    }

    function testExerciseMultiple() public {
        (uint256 optionId, uint256 positionId) = setUpBuyCallOption(100);
        (uint256 optionId2, uint256 positionId2) = setUpBuyCallOption(100);

        IVikalpa.Option memory option = vikalpa.getOption(optionId);

        vm.warp(option.exerciseTimestamp + 1);
        vm.prank(mockUser);
        vikalpa.exercise(optionId, uint80(120));

        IVikalpa.Position memory position = vikalpa.getPosition(positionId);
        IVikalpa.Position memory position2 = vikalpa.getPosition(positionId2);

        // check NFT balances
        assertEq(vikalpa.balanceOf(address(mockUser), optionId), 80);

        // check position exercise amount
        assertEq(position.amountExercised, 100);
        assertEq(position2.amountExercised, 20);

        // check token Balances
        assertEq(
            tokenA.balanceOf(address(vikalpa)),
            option.underlyingAmount * (200 - 100 - 20)
        );
        assertEq(
            tokenA.balanceOf(address(mockUser)),
            tokenBalance + option.underlyingAmount * (100 + 20)
        );
        assertEq(
            tokenB.balanceOf(address(vikalpa)),
            option.premium * 200 + option.exerciseAmount * (100 + 20)
        );
        assertEq(
            tokenB.balanceOf(address(mockUser)),
            tokenBalance -
                option.exerciseAmount *
                (100 + 20) -
                option.premium *
                200
        );
    }

    function testLiquidate() public {
        (uint256 optionId, uint256 positionId) = setUpBuyCallOption(100);

        IVikalpa.Option memory option = vikalpa.getOption(optionId);

        vm.warp(option.expiryTimestamp + 1);
        vikalpa.liquidate(positionId);

        IVikalpa.Position memory position = vikalpa.getPosition(positionId);
    }
}
