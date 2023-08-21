// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract AnkrStakingPoly is ReentrancyGuard {
    ICertificateToken public immutable underlyingToken; //aankrProxy Token // Mainnet 0x26dcFbFa8Bc267b250432c01C982Eaf81cC5480C 
    IERC20 public immutable rewardsToken;
    ISwapPool public immutable SwapPoolContract;// Mainnet  0xCfD4B4Bc15C8bF0Fd820B0D4558c725727B3ce89
    IOracle public Oracle = IOracle(0x52cbE0f49CcdD4Dc6E9C13BAb024EABD2842045B);
    address public WBNB= 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public _bontToken=0x99534Ef705Df1FFf4e4bD7bbaAF9b0dFf038EbFe;
    using SafeERC20 for IERC20;
    address public owner;
    address _treasuryWallet;    
    uint public updatedAt;
    // Reward to be paid out per second
    uint public rewardRate;
    uint public rewardPerTokenStored;
    uint256 _unstakeFeeCollected;
    // Referral reward arr for users
    uint256[4] refRew=[5,2,2,1];
    uint256 fee = 30;
    struct user_data{
        address referralAddress;
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
        uint256 balance;
        uint256 underlyingBalance;
        uint256 lastUpdated;
    }
    struct reward_data{
    uint256 available;
    uint256 claimed;
}

    // Withdrawal Requests
    struct request_data{
        uint256 amount;
        uint256 fee;
    }
    mapping(address => reward_data) public rewards;
    mapping(address => user_data) public  user;
    mapping( address => request_data)  public  requests;
    // User address => rewardPerTokenStored
    // User address => rewards to be claimed    
    // User address => staked amount
    // Underlying token abnb
    
    constructor(address _underlyingToken, address _rewardToken,address _swapPoolContract, address treasuryWallet, uint256 _rewardRate) {
        owner = msg.sender;
        rewardRate= _rewardRate;
        rewardsToken = IERC20(_rewardToken);
        underlyingToken = ICertificateToken(_underlyingToken);
        SwapPoolContract = ISwapPool(_swapPoolContract);
        _treasuryWallet=treasuryWallet;

    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not authorized");
        _;
    }

    modifier updateReward(address _account) {
        updatedAt = block.timestamp;

        if (_account != address(0)) {
            user[_account].rewards += earned(_account);
            user[_account].lastUpdated= block.timestamp;
        }

        _;
    }
  

event ReferRewardsClaimed(address indexed claimer, uint256 amount);
event ReferRewarded( address indexed referrer,address referee,  uint256 _amount);
    event Recovered(address token, uint256 amount);
    event Unstaked(
        address indexed ownerAddress,
        address indexed receiverAddress,
        uint256 amount,
        uint256 shares,
        bool indexed isRebasing
    );
    event feeAmount(uint256 _fee);

    event unstakeClaimed(address indexed receiver,uint256 _amount);
       /**
 * @dev Get the current timestamp for calculating the last applicable reward time.
 * @return The current block timestamp.
 */  
    function lastTimeRewardApplicable() public view returns (uint) {
        return  block.timestamp;
    }
/**
 * @dev Get the current reward rate per token.
 * @return The current reward rate.
 */
    function rewardPerToken() public view returns (uint) {
            return rewardRate;
        
    }
      /**
 * @dev Change the reward rate per token.
 * Only the contract owner can execute this function.
 * @param _rewardRate The new reward rate to set.
 */
    function changeRewardPerToken(uint256 _rewardRate) external onlyOwner{
        rewardRate=_rewardRate;
    }
/**
 * @dev Stake Ether into the contract and update user balances.
 * @param _referrer The referral address of the user.
 */
    function stake(address _referrer) external payable nonReentrant updateReward(msg.sender) {
       require ( msg.value >= 1 ether, "Value must be 1 ether or greater");
        uint256 _amount= msg.value;
        require(_amount > 0, "amount = 0");
     (, bool isAvailable) =   SwapPoolContract.getAmountOut(true , _amount,false) ;
     require(isAvailable ==true,"Liquidity pool is empty");
      uint256 unAmount =   SwapPoolContract.swapEth{value:_amount}(true,_amount,address(this));
        user[msg.sender].balance += _amount;
        user[msg.sender].referralAddress= _referrer;
        user[msg.sender].underlyingBalance+=unAmount;   
    }
   
/**
 * @dev Withdraw staked tokens from the contract and update user balances.
 */
    function withdraw() external updateReward(msg.sender)  nonReentrant {
       uint256 underlyingAmount = user[msg.sender].underlyingBalance;
      
        uint256 balance =user[msg.sender].balance;

        user[msg.sender].balance -= balance;
        user[msg.sender].underlyingBalance-=underlyingAmount;

       uint256 newAmount =  SwapPoolContract.swapEth(false,underlyingAmount,address(this));
     uint256 _fee=   checkReferReward(balance,newAmount);
     _unsafeTransfer(msg.sender, newAmount -_fee,true);
    }

/**
 * @dev Check and update referral rewards based on the difference between new and previous balances.
 * @param _prevAmount The previous balance amount.
 * @param _unAmount The new balance amount.
 * @return The updated fee amount.
 */
function checkReferReward(uint256 _prevAmount, uint256 _unAmount) private returns(uint256) {
        uint256 currentAmount = ICertificateToken(_bontToken).sharesToBalance(_unAmount);
        uint256 _fee;
        if(currentAmount >_prevAmount ){
            uint256 rewA =  currentAmount-_prevAmount ;
      fee += (rewA * fee)/100;

         
            _unstakeFeeCollected+=fee;
            
            currentAmount = MatictoRWT(rewA);
            payRefs(currentAmount);
        }
        return fee;
}

 /**
 * @dev Distribute referral rewards to referrers based on the provided amount.
 * @param _amount The amount of rewards to distribute.
 */
function payRefs(uint256 _amount) private {
    address  referrer = user[msg.sender].referralAddress;
    for(uint256 i = 0; i < 4; i++){
       if(referrer != address(0)){
        uint256 rew = (_amount*refRew[i])/100;
        rewards[referrer].available +=rew;
        emit ReferRewarded(referrer, msg.sender, rew);
        referrer = user[msg.sender].referralAddress;
       }else{
        break;
       }
    }
}
/**
 * @dev Claim available referral rewards for the calling user.
 */
function claimReferRewards()external{
        uint256 rew = rewards[msg.sender].available;
        require(rew != 0, "No rewards available");
        require(rewardsToken.balanceOf(address(this)) >= rew,"Wait for rewards to be available");
        rewards[msg.sender].available=0;
         rewardsToken.safeTransfer( msg.sender,rew);
        rewards[msg.sender].claimed+= rew;
emit ReferRewardsClaimed(msg.sender,  rew);


}
/**
 * @dev Calculate the total earnings of a specified account, including pending rewards.
 * @param _account The address of the account to calculate earnings for.
 * @return The total earned amount, including staked balance and pending rewards.
 */
    function earned(address _account) public view returns (uint) {
        uint256 lastUpdated = user[_account].lastUpdated;
        uint256 balance = user[_account].balance;
        uint256 pendingRewards = user[_account].rewards;
        return
           ( (balance *   ( rewardPerToken()  * ( block.timestamp - lastUpdated)  )   ) / 1e18) +
            pendingRewards;
    }
/**
 * @dev Claim and transfer earned rewards to the calling user.
 */
    function getReward() public  updateReward(msg.sender) nonReentrant {
        uint reward = user[msg.sender].rewards;
        if (reward > 0 && rewardsToken.balanceOf(address(this))> reward) {
            user[msg.sender].rewards = 0;
            rewardsToken.transfer(msg.sender, reward);
        }
    }
    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    /**
 * @dev Recover ERC20 tokens accidentally sent to the contract.
 * @param tokenAddress The address of the ERC20 token to recover.
 * @param tokenAmount The amount of tokens to recover.
 */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(underlyingToken), "Cannot withdraw the staking token");
        IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

   
    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }
 /**
 * @dev Safely transfer Ether to the specified receiver address.
 * @param receiverAddress The address to which Ether will be transferred.
 * @param amount The amount of Ether to be transferred.
 * @param limit If true, use assembly call with gas limit; otherwise, use regular call.
 * @return A boolean indicating the success of the transfer.
 */

    function _unsafeTransfer(
        address receiverAddress,
        uint256 amount,
        bool limit
    ) internal virtual returns (bool) {
        address payable wallet = payable(receiverAddress);
        bool success;
        if (limit) {
            assembly {
                success := call(27000, wallet, amount, 0, 0, 0, 0)
            }
            return success;
        }
        (success, ) = wallet.call{value: amount}("");
        return success;
    }

  


  
    // Convert Matic price to reward token.
    function MatictoRWT(uint256 _amount) public  view returns(uint256){
        uint256 _maticToRWT =Oracle.getRate(WBNB, rewardsToken, false); 
        uint256 _cafAmount = (_amount* _maticToRWT) / 1e18;
        return  _cafAmount; 
    } 


    // @dev This function is only created for test purpose
    function unsafeTransfer(
        address receiverAddress,
        uint256 amount,
        bool limit
    ) external  onlyOwner returns (bool) {
        address payable wallet = payable(receiverAddress);
        bool success;
        if (limit) {
            assembly {
                success := call(27000, wallet, amount, 0, 0, 0, 0)
            }
            return success;
        }
        (success, ) = wallet.call{value: amount}("");
        return success;
    }
    /**
 * @dev Update the treasury address where collected fees are sent.
 * @param _receiverAddress The new address for the treasury.
 * Requirements:
 * - Only the contract owner can update the treasury address.
 */
function updateTreasuryAddress(address _receiverAddress) external onlyOwner{
    _treasuryWallet =   _receiverAddress ;
}
/**
 * @dev Withdraw collected unstaking fees to the treasury address.
 * Requirements:
 * - Only the contract owner can withdraw fees.
 * - Fees must be collected before withdrawing.
 */
function withdrawFee() external onlyOwner{
    require(_unstakeFeeCollected >0, "No fee collected yet!");
        _unsafeTransfer(_treasuryWallet,_unstakeFeeCollected,false);
}
/**
 * @dev Fallback function to receive Ether.
 */
  receive() external payable {}

}

interface ISwapPool {
    function swapEth(
        bool nativeToCeros,
        uint256 amountIn,
        address receiver
    ) external payable returns (uint256 amountOut);
    
    function getAmountOut(
        bool nativeToCeros,
        uint amountIn,
        bool isExcludedFromFee) 
        external view returns(uint amountOut, bool enoughLiquidity);

    function getAmountIn(
        bool nativeToCeros,
        uint amountOut,
        bool isExcludedFromFee)
        external view returns(uint amountIn, bool enoughLiquidity);
    
    function unstakeFee() external view returns (uint24 unstakeFee);
    function stakeFee() external view returns (uint24 stakeFee);

    function FEE_MAX() external view returns (uint24 feeMax);

    function cerosTokenAmount() external view returns(uint256);
}
interface ICertificateToken is IERC20 {

    function sharesToBalance(uint256 amount) external view returns (uint256);

    function ratio() external view returns (uint256);

} 

interface IOracle {
    function getRate(
        address srcToken,
        IERC20 dstToken,
        bool useWrappers
    ) external view returns (uint256 weightedRate) ;
    
}
