// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {WithStorage} from "./LibStorage.sol";
import {LibDiamond} from "./LibDiamond.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts@4.9/token/ERC20/utils/SafeERC20.sol";

/**
 * @title BankrollFacet, Contract responsible for keeping the bankroll and distribute payouts
 */

contract BankrollFacet is WithStorage {
    using SafeERC20 for IERC20;
    /**
     * @dev event emitted when game is Added or Removed
     * @param gameAddress address of game state that changed
     * @param isValid new state of game address
     */
    event BankRoll_Game_State_Changed(address gameAddress, bool isValid);
    /**
     * @dev event emitted when token state is changed
     * @param tokenAddress address of token that changed state
     * @param isValid new state of token address
     */
    event Bankroll_Token_State_Changed(address tokenAddress, bool isValid);
    /**
     * @dev event emitted when max payout percentage is changed
     * @param payout new payout percentage
     */
    event BankRoll_Max_Payout_Changed(uint256 payout);
    event PriceSetter_Changed(address PriceSetter);
    event Price_Changed(address token, uint256 price);
    event MinWager_Changed(uint minWager);

    error InvalidGameAddress();
    error TransferFailed();
    error TokenNotRegistered();
    error NotPriceSetter();
    error ArraysLengthsAreDifferent();

    mapping(address => uint256) tokensPrices;
    address public priceSetter;
    /// Minimal wager in USDT
    uint256 public minWager;

    constructor(address _contractOwner, address setter) payable{
        LibDiamond.setContractOwner(_contractOwner);
        priceSetter = setter;
    }

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    /**
    * @dev set new price setter account
    */
    function setPriceSetter(
        address setter
    ) external onlyOwner{
        priceSetter = setter;
        emit PriceSetter_Changed(setter);
    }

    /**
    * @dev sets new minimal wager in USDT
    * @param wager - new minimal wager in USDT
    */
    function setMinWager(
        uint256 wager
    ) external onlyOwner {
        minWager = wager;
        emit MinWager_Changed(wager);
    }

    /**
     * @dev remove funds from the bankroll
     */
    function withdrawFunds(
        address tokenAddress,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(to, amount);
    }

    /**
     * @dev remove funds from the bankroll
     */
    function withdrawNativeFunds(
        address to,
        uint256 amount
    ) external onlyOwner {
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    /**
     * @dev Function to enable or disable games to distribute bankroll payouts
     * @param game contract address of game to change state
     * @param isValid state to set the address to
     */
    function setGame(address game, bool isValid) external onlyOwner {
        gs().isGame[game] = isValid;
        emit BankRoll_Game_State_Changed(game, isValid);
    }

    /**
     * @dev function to get if game is allowed to access the bankroll
     * @param game address of the game contract
     */
    function getIsGame(address game) external view returns (bool) {
        return (gs().isGame[game]);
    }

    /**
     * @dev function to get token's price
     * @param tokenAddress - address of a token to get the price of
     */
    function getTokenPrice(address tokenAddress) external view returns (uint256 price){
        price = tokensPrices[tokenAddress];
    }

    /**
     * @dev function to set new token price
     * @param tokenAddresses - addresses of tokens to set the price of
     * @param prices - prices of the tokens in USDT
     */
    function setTokensPrices(address[] calldata tokenAddresses, uint256[] calldata prices) external{
        if(msg.sender != priceSetter){
            revert NotPriceSetter();
        }
        if(tokenAddresses.length != prices.length){
            revert ArraysLengthsAreDifferent();
        }
        for(uint i=0; i<tokenAddresses.length; i++){
            address tokenAddress = tokenAddresses[i];
            uint256 price = prices[i];
            if(!gs().isTokenAllowed[tokenAddress]){
                revert TokenNotRegistered();
            }
            tokensPrices[tokenAddress] = price;
            emit Price_Changed(tokenAddress, price);
        }
    }


    /**
     * @dev function to check if payout can be given
     * @param game address of the game contract
     * @param tokenAddress address of the token the wager is made
     * @param wager wagered amount
     */
    function getIsValidWager(
        address game,
        address tokenAddress,
        uint256 wager
    ) external view returns (bool) {
        uint256 wagerUSDT = (wager / 1000000000000000000)*tokensPrices[tokenAddress];
        return (
            gs().isGame[game] 
            && gs().isTokenAllowed[tokenAddress] 
            && tokensPrices[tokenAddress] != 0
            && wagerUSDT >= 5000000000000000000);
    }

    /**
     * @dev function to set if a given token can be wagered
     * @param tokenAddress address of the token to set address
     * @param isValid state to set the address to
     */
    function setTokenAddress(
        address tokenAddress,
        bool isValid
    ) external onlyOwner {
        gs().isTokenAllowed[tokenAddress] = isValid;
        emit Bankroll_Token_State_Changed(tokenAddress, isValid);
    }

    /**
     * @dev function to set the wrapped token contract of the native asset
     * @param wrapped address of the wrapped token contract
     */
    function setWrappedAddress(address wrapped) external onlyOwner {
        gs().wrappedToken = wrapped;
    }

    /**
     * @dev function that games call to transfer payout
     * @param player address of the player to transfer payout to
     * @param payout amount of payout to transfer
     * @param tokenAddress address of the token to transfer, 0 address is the native token
     */
    function transferPayout(
        address player,
        uint256 payout,
        address tokenAddress
    ) external {
        if (!gs().isGame[msg.sender]) {
            revert InvalidGameAddress();
        }
        if (tokenAddress != address(0)) {
            IERC20(tokenAddress).safeTransfer(player, payout);
        } else {
            (bool success, ) = payable(player).call{value: payout, gas: 2400}(
                ""
            );
            if (!success) {
                (bool _success, ) = gs().wrappedToken.call{value: payout}(
                    abi.encodeWithSignature("deposit()")
                );
                if (!_success) {
                    revert();
                }
                IERC20(gs().wrappedToken).safeTransfer(player, payout);
            }
        }
    }

    error AlreadySuspended(uint256 suspensionTime);
    error TimeRemaingOnSuspension(uint256 suspensionTime);

    /**
     * @dev Suspend player by a certain amount time. This function can only be used if the player is not suspended since it could be used to lower suspension time.
     * @param suspensionTime Time to be suspended for in seconds.
     */
    function suspend(uint256 suspensionTime) external {
        if (gs().suspendedTime[msg.sender] > block.timestamp) {
            revert AlreadySuspended(gs().suspendedTime[msg.sender]);
        }
        gs().suspendedTime[msg.sender] = block.timestamp + suspensionTime;
        gs().isPlayerSuspended[msg.sender] = true;
    }

    /**
     * @dev Increse suspension time of a player by a certain amount of time. This function is intended to only be used as a complement to the suspend() function to increase suspension time.
     * @param suspensionTime Time to increase suspension time for in seconds.
     */
    function increaseSuspensionTime(uint256 suspensionTime) external {
        gs().suspendedTime[msg.sender] += suspensionTime;
        gs().isPlayerSuspended[msg.sender] = true;
    }

    /**
     * @dev Permantly suspend player. This function sets suspension time to the maximum allowed time.
     */
    function permantlyBan() external {
        gs().suspendedTime[msg.sender] = 2 ** 256 - 1;
        gs().isPlayerSuspended[msg.sender] = true;
    }

    /**
     * @dev Lift suspension after the required amount of time has passed
     */
    function liftSuspension() external {
        if (gs().suspendedTime[msg.sender] > block.timestamp) {
            revert TimeRemaingOnSuspension(gs().suspendedTime[msg.sender]);
        }
        gs().isPlayerSuspended[msg.sender] = false;
    }

    /**
     * @dev Function to view player suspension status.
     * @param player Address of the
     * @return bool is player suspended
     * @return uint256 time that unlock period ends
     */
    function isPlayerSuspended(
        address player
    ) external view returns (bool, uint256) {
        return (gs().isPlayerSuspended[player], gs().suspendedTime[player]);
    }

    /**
     * @dev function to get Address of current bankroll Owner
     */
    function getOwner() external view returns (address) {
        return LibDiamond.contractOwner();
    }
}
