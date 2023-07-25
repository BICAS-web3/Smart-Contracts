// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.6;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";


contract DunkinCups is Ownable, ReentrancyGuard {
    uint256 counter;

    address feeAccount;
    address moderatorAccount;
    uint256 feeAmount;
    uint256 maxPlayers;
    uint64 gameTime;


    enum Status { Available, Active, Close, Pending }


    struct NFTs {
        address nft;
        uint id;
    }

    struct Bets {
        uint256 gameId;
        address account;
        NFTs[] nfts;
        
    }

    struct Game {
        Status status;
        address[] players;
        address winner;
        Bets[] bets;
        uint64 expires;
    }

    mapping(uint256 => mapping(address => Bets)) public betsDetailsOf;
    mapping(uint256 => Game) public gameDetailsOf;


    event SetFee(_fee);
    event SetModerator(_moderator);
    event SetMaxPlayers(_maxPlayers);

    constructor(
        address _admin
        ) {
        _transferOwnership(_admin);
    }


    modifier onlyModerator() {
        require(msg.sender == moderatorAccount, "Not moderator");
        _;
    }


    function makeBets (uint256 _gameId, NFTs[] memory _nfts) external nonReentrant {
        Game storage gameDetails = gameDetailsOf[_gameId];
        require(gameDetails.status == Status.Available || gameDetails.status == Status.Active, "Closed game");
        require(gameDetails.expires > block.timestamp, "Expired");

        if (gameDetails.status == Status.Available) {
            gameDetails.status = Status.Active; 
        }

        gameDetails.players.push(msg.sender);

        for (uint i = 0; i < _nfts.length; i++) {
            IERC721(_nfts[i].nft).safeTransferFrom(msg.sender, address(this), _nfts[i].id);
        }

        

        Bets memory betsDetails = betsDetailsOf[_gameId][msg.sender];
        betsDetails.account = msg.sender;
        betsDetails.gameId = _gameId;
        betsDetails.nfts = _nfts;


        betsDetailsOf[_gameId] = betsDetails;
        gameDetailsOf[_gameId] = gameDetails;
    }


    function _addPlayerToGame(address player, uint256 gameId) {
        //
    }

    function _getPlayersCount(uint256 _gameId) privavte view returns(uint256) {
        Game memory game = games[_gameId];
        return game.players.length;
    }

    function setWinner(uint256 _gameId, address _winner) external onlyModerator {
        // Установка победителя
    }

    function claimReward(uint256 _gameId) external {
        // claim
    }


    function setFee (uint256 _fee) external onlyOwner {
        _setFee(_fee);
    }

    function _setFee(_fee) private {
        feeAmount = _fee;
        emit SetFee(_fee);
    }

    function setMaxPlayers (uint256 _maxPlayers) external onlyOwner {
        _setMaxPlayers(_maxPlayers);
    }

    function _setMaxPlayers(uint256 _maxPlayers) private {
        require(_maxPlayers > 1, "Zero Players not allowed");
        maxPlayers = _maxPlayers;
        emit SetMaxPlayers(_maxPlayers);
    }

    function setModerator (address _moderator) external onlyOwner {
       require (address(_moderator) != address(0),"Zero address");
       _setModerator(_moderator); 
    }

    function _setModerator(address _moderator) private {
        moderatorAccount = _moderator;
        emit SetModerator(_moderator);
    }




}