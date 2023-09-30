// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IERC20.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/SafeERC20.sol";
import "hardhat/console.sol";

contract FlashLoan {
    using SafeERC20 for IERC20;
      address private constant PANCAKE_FACTORY =
        0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address private constant PANCAKE_ROUTER =
        0x10ED43C718714eb63d5aA57B78B54704E256024E;

    // Token Addresses
    address private constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant CROX = 0x2c094F5A7D1146BB93850f629501eB749f6Ed491;
    address private constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

    uint256 private deadline = block.timestamp + 1 days;
    uint256 private constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;
    
    function checkResult(uint _repayAmount , uint _acquiredAmount)private returns(bool){
        return _repayAmount>_acquiredAmount ;
       }
    
    function placeTrade(address _tokenFrom , address _tokenTo , uint _amountIn) private returns(uint){
        address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(_tokenFrom,_tokenTo);
        require(pair != address(0),"Pool does not exist");
        address[] memory path = new address[](2);
        path[0]= _tokenFrom;
        path[1]= _tokenTo;

        uint amountRequired = IUniswapV2Router01(PANCAKE_FACTORY).getAmountOut(_amountIn, path);
        
        uint amountRecieved = IUniswapV2Router01(PANCAKE_ROUTER).swapExactTokensForTokens(_amountIn,amountRequired , path , address(this),deadline)[1];
        require(amountRecieved >0 , "Transaction Abort");
        return amountRecieved;
     }

    function initiateArbitrage(address _busdBorrow , uint256 _amount){
    IERC20(BUSD).safeApprove(address(PANCAKE_ROUTER),MAX_INT);
    IERC20(CROX).safeApprove(address(PANCAKE_ROUTER),MAX_INT);
    IERC20(CAKE).safeApprove(address(PANCAKE_ROUTER),MAX_INT);

    address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(
        _busdBorrow,
        WBNB);
    
    require(pair!=0 , "pool does not exist");
    // picking out token addresses of WBNB and BUSD from the pair of liquidity pool 
    address token0 = IUniswapV2Pair(pair).token0();//WBNB
    address token1 = IUniswapV2Pair(pair).token1();//BUSD
    // transfering the amount of bused or WBNB token into respective variables otherwise 0
    uint amount0Out = _busdBorrow==token0?_amount:0;
    uint amount1Out = _busdBorrow==token1?_amount:0;
    // preparing the data that has to be sent 
    bytes memory data = abi.encode(_busdBorrow,_amount,msg.sender);
    // calling the swap function from the Interface to transfer amount to the smart contract's address
    IUniswapV2Pair(pair).swap(amount0Out,amount1Out,address(this),data);

    }
    // main functin that does all the arbitrage for the contract
   
    function pancakeCall(address _sender , uint _amount0 , uint _amount1,bytes calldata _data )external {
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(token0,token1);
        require(msg.sender == pair, "Pair does not match ");
        require(_sender == address(this),"sender does not match");
        (address busdBorrow  , uint amount , address account) = abi.decode(_data ,(address, uint , address));
        uint fee = ((amount*3)/997)+1;
        uint repayAmount = fee + amount;
        uint loanAmount = _amount0?_amount0:_amount1;

        // Triangular Arbitrage
        uint trade1coin = placeTrade(BUSD , CROX , loanAmount);
        uint trade2coin = placeTrade(CROX , CAKE , trade1coin);
        uint trade3coin = placeTrade(CAKE , BUSD , trade2coin);

        // Checking if trade was profitable or not 

        bool result = checkResult(repayAmount, trade3coin);

        require(result , "The arbitrage is not profitable");
        

        IERC20(BUSD).transfer(account, trade3coin-repayAmount);
        IERC20(busdBorrow).transfer(pair, repayAmount);
        }



}

