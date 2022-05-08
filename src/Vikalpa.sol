// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC1155} from "@solmate/tokens/ERC1155.sol";
import {SafeTransferLib} from "@solmate/utis/SafeTransferLib.sol";

import {IVikalpa} from "./interfaces/IVikalpa.sol";

contract Vikalpa is ERC1155, IVikalpa {
    uint256 internal _nextId = 1;

    mapping(uint256 => Type) internal _tokenType;
    mapping(bytes32 => uint256) internal _hashToOptionType;

    mapping(uint256 => Option) public options;
    mapping(uint256 => Position) public positions;

    mapping(uint256 => uint256[]) public unboughtPositionByOptions;
    mapping(address => uint256[]) public unexercisedPositionsByAccount;

    function newOption(Option memory _option) external returns (uint256) {
        bytes32 optionKey = uint256(keccak256(abi.encode(_option)));
        if (_hashToOptionType[optionKey] != 0) revert OptionExists(optionKey);

        if (_option.expiryTimestamp < block.timestamp + 1 days)
            revert ExpiredOption();

        if (underlyingAsset == exerciseAsset) revert InvalidAssets();

        if (expiryTimestamp < exerciseTimestamp + 1 days)
            revert ExerciseWindowTooShort();

        if (
            ERC20(_option.underlyingAsset).totalSupply() <
            _option.underlyingAmount ||
            ERC20(_option.exerciseAsset).totalSupply() < _option.exerciseAmount
        ) revert InvalidAmount();

        _option.randomSeed = uint160(uint256(optionKey));

        _tokenType[_nextId] = Type.Option;
        _hashToOptionType[optionKey] = _nextId;
        options[_nextId] = _option;

        emit NewOptionCreated(
            _nextId,
            _option.optionType,
            _option.underlyingAsset,
            _option.exerciseAsset,
            _option.underlyingAmount,
            _option.exerciseAmount,
            _option.expiryTimestamp,
            _option.excerciseTimestamp
        );

        return _nextId++;
    }

    function write(uint256 _optionId, uint80 _amount)
        external
        returns (uint256 positionId)
    {
        if (_tokenType[_optionId] != Type.Option)
            revert InvalidToken(_optionId);

        Option storage option = options[_optionId];

        if (option.expiryTimestamp < block.timestamp)
            revert ExpiredOption(_optionId, option.expiryTimestamp);

        if (option.optionType) {
            // Call Position
            uint256 optionAmount = option.underlyingAmount * _amount;

            SafeTransferLib.safeTransferFrom(
                ERC20(option.underlyingAsset),
                msg.sender,
                address(this),
                optionAmount
            );
        } else {
            // Put Position
            uint256 optionAmount = option.exerciseAmount * _amount;

            SafeTransferLib.safeTransferFrom(
                ERC20(option.exerciseAsset),
                msg.sender,
                address(this),
                optionAmount
            );
        }

        positionId = _nextId;

        uint256[] memory tokens = new uint256[](2);
        tokens[0] = _optionId;
        tokens[1] = positionId;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _amount;
        amounts[1] = 1;

        _tokenType[_nextId] = Type.Position;
        positions[_nextId] = Position({
            optionId: _optionId,
            amountWritten: _amount,
            amountBought: 0,
            amountExercised: 0,
            writer: msg.sender,
            liquidated: false
        });

        unboughtPositionByOptions[_optionId].push(positionId);

        ++_nextId;

        _batchMint(msg.sender, tokens, amounts, hex"");

        emit OptionWritten(msg.sender, positionId, _optionId, _amount);

        return positionId;
    }

    function _buyFrom(
        uint256 _optionId,
        uint80 _amount,
        uint160 _randomSeed
    ) private {
        uint256 positionLen = unboughtPositionByOptions[_optionId].length;
        if (positionLen == 0) revert NoOptions();

        Position storage position;
        uint256 curIndex;
        uint256 amountCurrentlyBought;
        uint256 i;

        while (_amount > 0) {
            if (positionLen == 1) {
                curIndex = 0;
            } else {
                curIndex = _randomSeed % positionLen;
            }

            position = positions[
                unboughtPositionByOptions[_optionId][curIndex]
            ];

            uint256 amountAvailable = position.amountWritten -
                position.amountBought;

            if (_amount > amountAvailable) {
                _amount -= amountAvailable;
                amountCurrentlyBought = amountAvailable;
            } else {
                amountCurrentlyBought = _amount;
                _amount = 0;
            }

            uint256 newLen = positionLen - 1;
            if (newLen != 0) {
                unboughtPositionByOptions[_optionId][
                    curIndex
                ] = unboughtPositionByOptions[_optionId][newLen];
                unboughtPositionByOptions[_optionId].pop();
                positionLen = newLen;
            } else {
                unboughtPositionByOptions[_optionId].pop();
            }

            // update bought amount in position
            position.amountBought += amountCurrentlyBought;

            unexercisedPositionsByAccount[msg.sender].push(positionId);

            emit OptionBoughtFromWriter(
                msg.sender,
                position.writer,
                position.optionId,
                amountCurrentlyBought
            );

            // transfer option NFT to buyer
            safeTransferFrom(
                position.writer,
                msg.sender,
                _optionId,
                amountCurrentlyBought
            );

            position.randomSeed = uint256(keccak256(abi.encode(randomSeed, i)));
            ++i;
        }

        options[_optionId].randomSeed = randomSeed;

        return amountCurrentlyBought;
    }

    function buy(uint256 _optionId, uint80 _amount) external {
        if (_tokenType[_optionId] != Type.Option)
            revert InvalidToken(_optionId);

        Option storage option = options[_optionId];

        if (option.expiryTimestamp < block.timestamp)
            revert ExpiredOption(_optionId, option.expiryTimestamp);

        uint256 _optionAmount = _buyFrom(_optionId, _amount, option.randomSeed);

        // transfer option premium from buyer
        SafeTransferLib.safeTransferFrom(
            ERC20(option.exerciseAmount),
            msg.sender,
            address(this),
            _optionAmount * option.premium
        );

        emit OptionsBought(msg.sender, _optionId, _amount);
    }

    function exercise(uint256 _optionId, uint80 _amount) external {
        if (_tokenType[_optionId] != Type.Option)
            revert InvalidToken(_optionId);

        if (balanceOf(msg.sender, _optionId) < _amount)
            revert NotEnoughBalance(msg.sender, _optionId);

        Option storage option = options[_optionId];

        if (option.expiryTimestamp <= block.timestamp)
            revert ExpiredOption(_optionId, option.expiryTimestamp);

        if (option.excerciseTimestamp > block.timestamp)
            revert EarlyExercise(_optionId, option.excerciseTimestamp);

        uint256 optionAmount = option.underlyingAmount * _amount;
        uint256 exerciseAmount = option.exerciseAmount * _amount;

        // update exercise amount in positions
        Position storage position;

        uint256[] memory positionIds = unexercisedPositionsByAccount[
            msg.sender
        ];
        uint256 amountLeft = _amount;
        uint256 i;

        while (amountLeft > 0) {
            position = positions[positionIds[i]];

            if (amountLeft < position.amountBought - position.amountExercised) {
                position.amountExercised += amountLeft;
                amountLeft = 0;
            } else {
                amountLeft -= position.amountBought - position.amountExercised;
                position.amountExercised = position.amountBought;
            }

            ++i;
        }

        if (option.optionType) {
            // Call Position

            SafeTransferLib.safeTransferFrom(
                ERC20(option.exerciseAsset),
                msg.sender,
                address(this),
                exerciseAmount
            );

            SafeTransferLib.safeTransfer(
                ERC20(option.underlyingAsset),
                msg.sender,
                optionAmount
            );
        } else {
            // Put Position

            SafeTransferLib.safeTransferFrom(
                ERC20(option.underlyingAsset),
                msg.sender,
                address(this),
                optionAmount
            );

            SafeTransferLib.safeTransfer(
                ERC20(option.exerciseAsset),
                msg.sender,
                exerciseAmount
            );
        }

        _burn(msg.sender, _optionId, _amount);
        emit OptionExercised(msg.sender, _optionId, _amount);
    }

    function liquidate(uint256 _positionId) external {
        if (_tokenType[_positionId] != Type.Position)
            revert InvalidToken(_positionId);

        if (balanceOf(msg.sender, positionId) != 1)
            revert NotEnoughBalance(msg.sender, _positionId);

        Position storage position = positions[_positionId];

        if (position.liquidated) revert AlreadyLiquidated(_positionId);

        Option storage option = options[position.optionId];

        if (option.expiryTimestamp > block.timestamp)
            revert EarlyLiquidation(_positionId, option.expiryTimestamp);

        uint256 exerciseAmount = position.amountExercised *
            option.exerciseAmount;
        uint256 underlyingAmount = (position.amountWritten -
            position.amountExercised) * option.underlyingAmount;

        if (option.optionType) {
            // Call Position
            SafeTransferLib.safeTransfer(
                ERC20(option.underlyingAsset),
                msg.sender,
                underlyingAmount
            );
            SafeTransferLib.safeTransfer(
                ERC20(option.exerciseAsset),
                msg.sender,
                exerciseAmount
            );
        } else {
            // Put Position
            SafeTransferLib.safeTransfer(
                ERC20(option.underlyingAsset),
                msg.sender,
                exerciseAmount
            );
            SafeTransferLib.safeTransfer(
                ERC20(option.exerciseAsset),
                msg.sender,
                underlyingAmount
            );
        }

        position.liquidated = true;

        _burn(msg.sender, positionId, 1);

        emit OptionLiquidated(msg.sender, _positionId);
    }

    function getTokenInfo(uint256 _tokenId)
        external
        view
        returns (Info memory info)
    {
        if (_tokenType[_tokenId] == Type.Option) {
            Option storage option = options[_tokenId];
            bool expired = (option.expiryTimestamp > block.timestamp);
            info.optionType = option.optionType;
            info.underlyingAsset = option.underlyingAsset;
            info.exerciseAsset = option.exerciseAsset;
            info.underlyingAmount = expired
                ? uint256(0)
                : uint256(option.underlyingAmount);
            info.exerciseAmount = expired
                ? uint256(0)
                : uint256(option.exerciseAmount);
        } else if (_tokenType[_tokenId] == Type.Position) {
            Position storage position = positions[_tokenId];
            Option storage option = options[position.optionId];
            bool expired = (option.expiryTimestamp > block.timestamp);
            info.optionType = option.optionType;
            info.underlyingAsset = option.underlyingAsset;
            info.exerciseAsset = option.exerciseAsset;
            info.underlyingAmount = expired
                ? uint256(0)
                : uint256(
                    option.underlyingAmount *
                        (position.amountWritten - position.amountExercised)
                );
            info.exerciseAmount = expired
                ? uint256(0)
                : uint256(option.exerciseAmount * position.amountExercised);
        } else {
            revert InvalidToken(_tokenId);
        }
    }
}
