// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DunkinCaps is ERC721Holder, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public counter;

    address public feeAccount;
    address public moderatorAccount;
    uint256 public feeAmount;
    uint256 public maxPlayers;
    uint64 public gameTime;

    enum Status { Available, Active, Close, Pending }

    struct NFTs {
        address nft;
        uint256 id;
    }

    struct Bets {
        uint256 gameId;
        address account;
        NFTs[] nfts;
    }

    struct Game {
        Status status;
        EnumerableSet.AddressSet players;
        address winner;
        Bets[] bets;
        uint64 expires;
    }

    mapping(uint256 => Game) private games;

    event GameCreated(uint256 indexed gameId, uint64 expires);
    event GameClosed(uint256 indexed gameId);
    event BetPlaced(uint256 indexed gameId, address indexed player, uint256 indexed betId);

    constructor(
        address _feeAccount,
        address _moderatorAccount,
        uint256 _feeAmount,
        uint256 _maxPlayers,
        uint64 _gameTime
    ) {
        require(_feeAccount != address(0), "Invalid fee account");
        require(_moderatorAccount != address(0), "Invalid moderator account");
        require(_feeAmount > 0, "Fee amount should be greater than 0");
        require(_maxPlayers > 0, "Max players should be greater than 0");
        require(_gameTime > 0, "Game time should be greater than 0");

        feeAccount = _feeAccount;
        moderatorAccount = _moderatorAccount;
        feeAmount = _feeAmount;
        maxPlayers = _maxPlayers;
        gameTime = _gameTime;
    }


    function createGame(uint64 _expires) external {
        require(_expires > block.timestamp + gameTime, "Game time should be greater than current time");

        Game storage game = games[counter];
        game.status = Status.Available;
        game.expires = _expires;

        emit GameCreated(counter, _expires);

        counter++;
    }

    function closeGame(uint256 _gameId) external {
        Game storage game = games[_gameId];

        require(game.status == Status.Available || game.status == Status.Active, "Invalid game status");
        require(block.timestamp > game.expires, "Game is still active");

        game.status = Status.Close;

        emit GameClosed(_gameId);
    }

    function makeBets(uint256 _gameId, NFTs[] memory _nfts) external nonReentrant {
        Game storage game = games[_gameId];
        require(game.status == Status.Available || game.status == Status.Active, "Invalid game status");

        // если доступно - создать игру, добавить хуйню 
        // если уже актив, надо 

        //require(game.expires > block.timestamp, "Game has expired");
        require(game.players.length() < maxPlayers, "Max players reached");
        require(!game.players.contains(msg.sender), "You have already joined this game");

        // Transfer NFTs to contract
        for (uint i = 0; i < _nfts.length; i++) {
             IERC721(_nfts[i].nft).safeTransferFrom(msg.sender, address(this), _nfts[i].id);
        }

        // Save bet data
        uint256 newBetId = game.bets.length;
        game.bets.push();
        game.bets[newBetId].gameId = _gameId;
        game.bets[newBetId].account = msg.sender;
        for (uint i = 0; i < _nfts.length; i++) {
            game.bets[newBetId].nfts.push(_nfts[i]);
        }

        // Save other data
        if (game.status == Status.Available) {
            game.status = Status.Active;
        }
        game.players.add(msg.sender);
        game.expires = uint64(block.timestamp + gameTime);


    }


}