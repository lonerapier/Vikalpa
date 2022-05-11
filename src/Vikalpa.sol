// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC20} from "@solmate/tokens/ERC20.sol";
// import {ERC1155} from "@solmate/tokens/ERC1155.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {ERC1155} from "./interfaces/ERC1155.sol";
import {IVikalpa} from "./interfaces/IVikalpa.sol";

/*
 * Will, it be a Call or Put, Anon? You decide.
 *
 * @@@@@@@@@@@@@@@@@@@@@@@@@@@###=*#@@@@@@@
 * @@@@%.   .+%%%@@@@@@@@%%-         #@@@@@
 * @@@*           :@@@@@#     ...     -@@@@
 * @@=     ..       @@@@.   .::.:...   .@@@
 * @*  .......:.    =@@@   ..:-----:--: .@@
 * * :=++==----.    -@@#. . .:=====+++=:.-@
 * :..=**+=-==:.     @@-    .:--=-=+**+.  @
 * .  -#%*-==:...    =@:  . .==:---=#%#:  +
 *   :=@+---=--..    -@:    .%%%-:---#%+:
 * ..:+*--=+****.    :@:.   :%%%:.:::=@+-:.
 * -=++=-:.:##%-..:: .@-..:.:*%%-   ..*#*+=
 * **#%-   .+#+..:+  .@*  :-...::     -@%##
 * %%%%: .....::..=  .@@:  :. :. .::  -@@%@
 * @@@%:. .-. :+  :   @@-     -.  +.  .@@@@
 * @@@@=.  =   :  ..  @@*. :   .  -   .@@@@
 * @@@@#:. :.  :   : .@@@-...  .   .  .@@@@
 * @@@@%=:. :   .  *==@@@%**: ..   :  :@@@@
 * @@@@@#=. :.  :. +%@@@@@@@-..:. .. .-@@@@
 * @@@@@@*=:::. :..=@@@@@@@@###*:..:.:+#*@@
 * @@@@@@%###=::-#*#@@@@@@@@@@@@*+++===**#%
 * @@@@@@@@@@###*@@@@@@@@@@@@@@@@%%@%#%#=*@
 *
 */

/// @notice Vanilla ERC1155 Options AMM contract for covered calls or puts
/// @dev Two types of ERC1155 tokens issued:
///     1. Option Tokens
///     2. Position Tokens
contract Vikalpa is ERC1155, IVikalpa {
    // =============== STATE VARIABLES ===============

    /// @notice manages ids of tokens
    uint256 internal _nextId = 1;

    /// @notice mapping of token ids to token types
    mapping(uint256 => Type) internal _tokenType;

    /// @notice mapping of option hashes to option ids
    mapping(bytes32 => uint256) internal _hashToOptionType;

    /// @notice mapping of option ids to options
    mapping(uint256 => Option) internal options;

    /// @notice mapping of position ids to positions
    mapping(uint256 => Position) internal positions;

    /// @notice mapping of option ids to unbought positions
    mapping(uint256 => uint256[]) public unboughtPositionByOptions;

    /// @notice mapping of accounts to bought positions
    mapping(address => uint256[]) public unexercisedPositionsByAccount;

    // =============== HELPER FUNCTIONS ===============

    /// @inheritdoc ERC1155
    function uri(uint256) public pure override returns (string memory) {
        return "";
    }

    /// @inheritdoc IVikalpa
    function getOption(uint256 _optionId) public view returns (Option memory) {
        return options[_optionId];
    }

    /// @inheritdoc IVikalpa
    function getPosition(uint256 _positionId)
        public
        view
        returns (Position memory)
    {
        return positions[_positionId];
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

    // =============== PUBLIC FUNCTIONS ===============

    function newOption(Option memory _option) external returns (uint256) {
        // create option hash key
        bytes32 optionKey = keccak256(abi.encode(_option));

        // check if option already exists
        uint256 optionId = _hashToOptionType[optionKey];
        if (optionId != 0) return optionId;

        // check for expired option
        if (_option.expiryTimestamp < block.timestamp + 1 days)
            revert ExpiredOption();

        // check for invalid tokens
        if (_option.underlyingAsset == _option.exerciseAsset)
            revert InvalidAssets(
                _option.underlyingAsset,
                _option.exerciseAsset
            );

        // expiry timestamp should be greater than exercise timestamp by at least 1 day
        if (_option.expiryTimestamp < _option.exerciseTimestamp + 1 days)
            revert ExerciseWindowTooShort(
                _option.exerciseTimestamp,
                _option.expiryTimestamp
            );

        // check token supplies
        if (
            ERC20(_option.underlyingAsset).totalSupply() <
            _option.underlyingAmount ||
            ERC20(_option.exerciseAsset).totalSupply() < _option.exerciseAmount
        ) revert InvalidAmount();

        // create option seed
        _option.randomSeed = uint160(uint256(optionKey));

        // populate option type mapping
        _tokenType[_nextId] = Type.Option;
        _hashToOptionType[optionKey] = _nextId;
        options[_nextId] = _option;

        emit NewOptionCreated(
            _nextId,
            _option.underlyingAsset,
            _option.exerciseAsset,
            _option.optionType,
            _option.underlyingAmount,
            _option.exerciseAmount,
            _option.expiryTimestamp,
            _option.exerciseTimestamp
        );

        // increment next id and return
        return _nextId++;
    }

    /// @inheritdoc IVikalpa
    function write(uint256 _optionId, uint80 _amount)
        external
        returns (uint256 positionId)
    {
        if (_tokenType[_optionId] != Type.Option)
            revert InvalidToken(_optionId);

        Option storage option = options[_optionId];

        if (option.expiryTimestamp < block.timestamp) revert ExpiredOption();

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

        // mint ERC1155 NFTs
        uint256[] memory tokens = new uint256[](2);
        tokens[0] = _optionId;
        tokens[1] = positionId;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _amount;
        amounts[1] = 1;

        // mint position NFT and create mapping
        _tokenType[_nextId] = Type.Position;
        positions[_nextId] = Position({
            optionId: _optionId,
            amountWritten: _amount,
            amountBought: 0,
            amountExercised: 0,
            writer: msg.sender,
            liquidated: false
        });

        // push position to unbought positions
        unboughtPositionByOptions[_optionId].push(positionId);

        // increment id
        ++_nextId;

        // mint nfts
        _batchMint(msg.sender, tokens, amounts, hex"");

        emit OptionWritten(msg.sender, positionId, _optionId, _amount);

        return positionId;
    }

    /// @inheritdoc IVikalpa
    function buy(uint256 _optionId, uint80 _amount) external {
        if (_tokenType[_optionId] != Type.Option)
            revert InvalidToken(_optionId);

        Option storage option = options[_optionId];

        if (option.expiryTimestamp < block.timestamp) revert ExpiredOption();

        uint256 _optionAmount = uint256(
            deal(_optionId, _amount, option.randomSeed)
        );

        // transfer option premium from buyer
        SafeTransferLib.safeTransferFrom(
            ERC20(option.exerciseAsset),
            msg.sender,
            address(this),
            _optionAmount * option.premium
        );

        emit OptionsBought(msg.sender, _optionId, _amount);
    }

    /// @inheritdoc	IVikalpa
    function exercise(uint256 _optionId, uint80 _amount) external {
        if (_tokenType[_optionId] != Type.Option)
            revert InvalidToken(_optionId);

        if (balanceOf[msg.sender][_optionId] < uint80(_amount))
            revert NotEnoughBalance(msg.sender, _optionId);

        Option storage option = options[_optionId];

        // burns expired option NFTs
        if (option.expiryTimestamp <= block.timestamp) {
            _burn(msg.sender, _optionId, _amount);
            return;
        }

        // revert if option is can't be exercised
        if (option.exerciseTimestamp > block.timestamp)
            revert EarlyExercise(_optionId, option.exerciseTimestamp);

        uint256 optionAmount = option.underlyingAmount * _amount;
        uint256 exerciseAmount = option.exerciseAmount * _amount;

        // update exercise amount in positions
        Position storage position;

        uint256[] memory positionIds = unexercisedPositionsByAccount[
            msg.sender
        ];
        uint80 amountLeft = _amount;
        uint256 i;

        while (amountLeft > 0) {
            position = positions[positionIds[i]];

            if (!position.liquidated) {
                if (
                    amountLeft <
                    position.amountBought - position.amountExercised
                ) {
                    position.amountExercised += amountLeft;
                    amountLeft = 0;
                } else {
                    amountLeft -=
                        position.amountBought -
                        position.amountExercised;
                    position.amountExercised = position.amountBought;
                }
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

        if (balanceOf[msg.sender][_positionId] != 1)
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

        // transfer option premium from buyer
        if (position.amountBought > 0)
            SafeTransferLib.safeTransfer(
                ERC20(option.exerciseAsset),
                msg.sender,
                option.premium * position.amountBought
            );

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

        _burn(msg.sender, _positionId, 1);

        emit OptionLiquidated(msg.sender, _positionId);
    }

    // =============== PRIVATE FUNCTIONS ===============

    /// @notice buys `amount` of options from unbought positions
    /// @param _optionId option id
    /// @param _amount amount to buy
    /// @param _randomSeed option seed
    /// @return optionAmount amount of option bought
    function deal(
        uint256 _optionId,
        uint80 _amount,
        uint160 _randomSeed
    ) private returns (uint80) {
        // total unbought positions
        uint256 positionLen = unboughtPositionByOptions[_optionId].length;
        if (positionLen == 0) revert NoOption();

        Position storage position;
        uint80 amount = _amount;

        // currently available options
        uint80 amountCurrentlyBought;

        // current index
        uint256 curIndex;

        // current position id
        uint256 positionId;

        // counter to update option seed
        uint256 i;

        // loop over positions and buy options available i.e.
        // options writter - bought
        while (_amount > 0) {
            curIndex = (positionLen == 1) ? 0 : _randomSeed % positionLen;

            positionId = unboughtPositionByOptions[_optionId][curIndex];
            position = positions[positionId];

            uint80 amountAvailable = position.amountWritten -
                position.amountBought;

            if (_amount > amountAvailable) {
                _amount -= amountAvailable;
                amountCurrentlyBought = amountAvailable;

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
            } else {
                amountCurrentlyBought = _amount;
                _amount = 0;
            }

            // update bought amount in position
            position.amountBought += amountCurrentlyBought;

            unexercisedPositionsByAccount[msg.sender].push(positionId);

            emit OptionBoughtFromWriter(
                msg.sender,
                position.writer,
                positionId,
                position.optionId,
                amountCurrentlyBought
            );

            // transfer option NFT to buyer
            safeTransferFrom(
                position.writer,
                msg.sender,
                _optionId,
                amountCurrentlyBought,
                hex""
            );

            _randomSeed = uint160(
                uint256(keccak256(abi.encode(_randomSeed, i)))
            );
            ++i;
        }

        options[_optionId].randomSeed = _randomSeed;

        return amount - _amount;
    }
}
