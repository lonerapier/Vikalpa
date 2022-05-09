// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

interface IVikalpa {
    error InvalidToken(uint256);
    error InvalidAmount();
    error InvalidAssets(address, address);
    error NotEnoughBalance(address, uint256);
    error OptionExists(bytes32);
    error ExerciseWindowTooShort(uint32, uint32);
    error NoOption();
    error EarlyExercise(uint256, uint112);
    error EarlyLiquidation(uint256, uint40);
    error ExpiredOption();
    error AlreadyLiquidated(uint256);

    event NewOptionCreated(
        uint256 indexed optionId,
        address indexed underlyingAsset,
        address indexed exerciseAsset,
        bool optionType,
        uint256 underlyingAmount,
        uint256 exerciseAmount,
        uint256 expiryTimestamp,
        uint256 exerciseTimestamp
    );

    event OptionWritten(
        address indexed writer,
        uint256 indexed positionId,
        uint256 indexed optionId,
        uint256 amount
    );

    event OptionExercised(
        address indexed buyer,
        uint256 indexed optionId,
        uint256 amount
    );

    event OptionLiquidated(address indexed writer, uint256 indexed positionId);

    event OptionBoughtFromWriter(
        address indexed buyer,
        address indexed writer,
        uint256 indexed optionId,
        uint256 amount
    );

    event OptionsBought(
        address indexed buyer,
        uint256 optionId,
        uint256 amount
    );

    // ERC1155 Token type
    enum Type {
        Option,
        Position
    }

    /// @notice Contains data assosciated with Option NFT of ERC1155 token.
    /// @dev utilises 4 storage slots
    struct Option {
        // underlying asset to be sold or bought in terms of option type
        address underlyingAsset;
        // amount of underlying asset
        uint96 underlyingAmount;
        // exercise asset to be sold or bought in terms of option type
        address exerciseAsset;
        // amount of exercise asset
        uint96 exerciseAmount;
        // premium to be paid to writer by buyer
        uint256 premium;
        // expiry timestamp
        uint32 expiryTimestamp;
        // exercise timestamp
        uint32 exerciseTimestamp;
        // randomised seed for option buying
        uint160 randomSeed;
        // Can be of two types: Call or Put
        bool optionType;
    }

    /// @notice Contains data assosciated with Position NFT of ERC1155 token.
    struct Position {
        // written option id
        uint256 optionId;
        // amount of option written
        uint80 amountWritten;
        // amount of option sold
        uint80 amountBought;
        // amount of option exercised
        uint80 amountExercised;
        // option writer
        address writer;
        // Option is liquidated after expiry
        bool liquidated;
    }

    /// @notice Option info
    struct Info {
        bool optionType;
        address underlyingAsset;
        address exerciseAsset;
        uint256 underlyingAmount;
        uint256 exerciseAmount;
    }

    /// @notice create new option
    /// @param option option info
    /// @return optionId id of new option
    function newOption(Option memory option) external returns (uint256);

    /// @notice write position
    /// @param optionId id of option to be written
    /// @param amount amount of options
    /// @return positionId id of position written
    function write(uint256 optionId, uint80 amount)
        external
        returns (uint256 positionId);

    /// @notice buy options
    /// @param optionId id of option to be bought
    /// @param amount amount of options
    function buy(uint256 optionId, uint80 amount) external;

    /// @notice exercise options
    /// @param optionId id of option to be exercised
    /// @param amount amount of options
    function exercise(uint256 optionId, uint80 amount) external;

    /// @notice liquidate expired position
    /// @param positionId id of position to be liquidated
    function liquidate(uint256 positionId) external;

    /// @notice get option info
    /// @param tokenId token id returned during option creation
    /// @return info option info
    function getTokenInfo(uint256 tokenId)
        external
        view
        returns (Info memory info);
}
