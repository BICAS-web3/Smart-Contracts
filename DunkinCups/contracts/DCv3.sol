// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract DunkinCaps is ERC721Holder, ReentrancyGuard, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    
    uint256 public counter;

    address public feeAccount;
    address public moderatorAccount;
    uint256 public feeAmount;
    uint256 public maxPlayers;
    uint64 public gameTime;

    enum Status { Available, Active, Pending, Close }

    struct NFTs {
        address nft;
        uint256 id;
    }

    struct Game {
        Status status;
        address[] players;
        address winner;
        NFTs[] nfts;
        uint64 expires;
    }

    mapping(uint256 => Game) public gamesDetailsOf;
    mapping(uint256 => mapping(address => NFTs[])) public betsDetailsOf;

    event CreateGame(uint256 gameId);
    event CreateBet(uint256 gameId, address player, NFTs[]);
    event SetWinner(address winner);
    event ClaimRewards(address winner, NFTs[]);
    event SetFeeAccount(address account);
    event SetFeeAmount(uint256 amount);
    event SetModerator(address account);
    event SetMaxPlayers(uint256 maxPlayers);
    event SetGameTime(uint64 gameTime);
    
    constructor(
        address _admin,
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
        _transferOwnership(_admin);
    }

    modifier onlyModerator() {
        require(msg.sender == moderatorAccount, "Only moderator can perform this action");
        _;
    }

    function createGame() external onlyModerator returns(uint256) {
        counter++;
        gamesDetailsOf[counter].status = Status.Active;
        gamesDetailsOf[counter].expires = uint64(block.timestamp + gameTime);

        emit CreateGame(counter);
        return counter;
        
    }

    function makeBets(uint256 gameId, NFTs[] memory nfts) payable external nonReentrant {
        Game memory game = gamesDetailsOf[gameId];

        require(game.status == Status.Active, "Invalid game status");
        require(game.players.length < maxPlayers, "Max players reached");
        require(!_isPlayerInGame(gameId, msg.sender), "You have already joined this game");
        require(game.expires > block.timestamp, "Game has expired");

        // Transfer fee
        _sendFee(feeAccount, feeAmount);

        // Transfer NFT to contract
        for (uint i = 0; i < nfts.length; i++) {
             IERC721(nfts[i].nft).safeTransferFrom(msg.sender, address(this), nfts[i].id);
             betsDetailsOf[gameId][msg.sender].push(nfts[i]);
             gamesDetailsOf[gameId].nfts.push(nfts[i]);
        }

        gamesDetailsOf[gameId].players.push(msg.sender);

        emit CreateBet(gameId, msg.sender, betsDetailsOf[gameId][msg.sender]);
    }

    function setWinner(uint256 gameId, address winner) external onlyModerator {
        gamesDetailsOf[gameId].status = Status.Pending;
        gamesDetailsOf[gameId].winner = winner;

        emit SetWinner(winner);
    }

    function claimReward(uint256 gameId) external {
        Game memory game = gamesDetailsOf[gameId];
        require(game.winner == msg.sender, "Your are not winner");

        NFTs[] memory nfts = getNFTsForGame(gameId);
        
        for (uint i = 0; i < nfts.length; i++) {
             IERC721(nfts[i].nft).safeTransferFrom(address(this), msg.sender, nfts[i].id);
        }
        gamesDetailsOf[gameId].status = Status.Close;

        emit ClaimRewards(msg.sender, nfts);
    }

    function getGame(uint256 _gameId) public view returns (
            Status status,
            address[] memory players,
            address winner,
            uint64 expires
        ) {
        Game memory game = gamesDetailsOf[_gameId];
        uint256 playerCount = game.players.length;

        players = new address[](playerCount);

        for (uint256 i = 0; i < playerCount; i++) {
            players[i] = game.players[i];
        }

        return (
            game.status,
            players,
            game.winner,
            game.expires
        );
    }

    function getNFTsForGame(uint256 gameId) public view returns (NFTs[] memory) {
        return gamesDetailsOf[gameId].nfts;
    }

    function getBet(uint256 gameId, address user) public view returns (NFTs[] memory) {
        NFTs[] memory nfts = betsDetailsOf[gameId][user];
        return nfts;
    }

    function getWinner(uint256 gameId) public view returns (address) {
        Game memory game = gamesDetailsOf[gameId];
        require(game.status == Status.Close || game.status == Status.Pending, "Game is not closed yet");
        return game.winner;
    }

    function setFeeAccount (address account) external onlyOwner {
        require(account != address(0), "Zero address");
        feeAccount = account;   
        emit SetFeeAccount(account);
    }

    function setFeeAmount(uint256 amount) external onlyOwner {
        feeAmount = amount;
        emit SetFeeAmount(amount);
    }

    function setModerator(address account) external onlyOwner {
        require(account != address(0), "Zero address");
        moderatorAccount = account;
        emit SetModerator(account);
    }

    function setGameTime (uint64 time) external onlyOwner {
        gameTime = time;
        emit SetGameTime(time);
    }

    function setMaxPlayers (uint256 players) external onlyOwner {
        require(players > 1, "Players must be greater than 1");
        maxPlayers = players;
        emit SetMaxPlayers (maxPlayers);
    }


    function _sendFee(address recipient, uint256 amount) private {
        require(msg.value == amount, "Amount of ether sent does not match specified amount.");
        payable(recipient).transfer(amount);
    }

    function _isPlayerInGame(uint256 gameId, address player) private view returns (bool) {
        for (uint i = 0; i < gamesDetailsOf[gameId].players.length; i++) {
            if (gamesDetailsOf[gameId].players[i] == player) {
                return true;
            }
        }
        return false;
    }

}