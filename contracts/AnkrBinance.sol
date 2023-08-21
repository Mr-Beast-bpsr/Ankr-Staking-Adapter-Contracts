// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract AnkrStaking is ReentrancyGuard {
    ICertificateToken public immutable underlyingToken; //aankrProxy Token //Testnet 0x3C1039C346bd5141BF2D5e855928E61655658fA7 // Mainnet 0x52F24a5e03aee338Da5fd9Df68D2b6FAe1178827 //
    IERC20 public immutable rewardsToken;
    IStakingContract public immutable StakingContract;//Testnet 0x3c9205b5d4b312ca7c4d28110c91fe2c74718a94 // Mainnet  0x9e347Af362059bf2E55839002c699F7A5BaFE86E
    IOracle public Oracle = IOracle(0x52cbE0f49CcdD4Dc6E9C13BAb024EABD2842045B);
    address public WBNB= 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    using SafeERC20 for IERC20;
    address public owner;
    address _treasuryWallet;    
    uint public updatedAt;
    // Reward to be paid out per second
    uint public rewardRate;
    uint public rewardPerTokenStored;
    uint256 _flashUnstakeCollectedFee;
    uint256 _unstakeFeeCollected;
    // Referral reward arr for users
    uint256[4] refRew=[5,2,2,1];
    uint256 fee = 30;
    uint256  _flashUnstakeFee = 2;
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
    
    constructor(address _underlyingToken, address _rewardToken,address _stakingContract, address treasuryWallet, uint256 _rewardRate) {
        owner = msg.sender;
        rewardRate= _rewardRate;
        rewardsToken = IERC20(_rewardToken);
        underlyingToken = ICertificateToken(_underlyingToken);
        StakingContract = IStakingContract(_stakingContract);
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
    event FlashUnstakeFeeCollectedClaimed(address indexed wallet,uint256 amount);
    event FlashFeeAmount(uint256 unstakeFeeAmt);
    event Unstaked(
        address indexed ownerAddress,
        address indexed receiverAddress,
        uint256 amount,
        uint256 shares,
        bool indexed isRebasing
    );
    event FlashFeeAmount(address userAddress, uint256 amount);
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
 * @dev Stake ETH to earn rewards and certificates.
 * @param _referrer The address of the referrer who referred the user (optional).
 */
    function stake(address _referrer) external payable nonReentrant updateReward(msg.sender) {
        uint256 _amount= msg.value;
        require(_amount > 0, "amount = 0");
        StakingContract.stakeCerts{value:_amount}();
        user[msg.sender].balance += _amount;
        user[msg.sender].referralAddress= _referrer;
        uint256 unAmount = underlyingToken.bondsToShares(_amount);
        user[msg.sender].underlyingBalance+=unAmount;   
       

    }
   
/**
 * @dev Withdraw staked funds and claim corresponding certificates.
 */

    function withdraw() external updateReward(msg.sender)  nonReentrant {
       uint256 underlyingAmount = user[msg.sender].underlyingBalance;
       require(underlyingAmount>= 0.1 ether, "Invalid amount Called");
        uint256 currentAmount = underlyingToken.sharesToBonds(underlyingAmount);
        
        requests[msg.sender].amount += currentAmount;
        
        uint256 balance =user[msg.sender].balance;

        user[msg.sender].balance -= balance;
        user[msg.sender].underlyingBalance-=underlyingAmount;
        checkReferReward(balance,currentAmount);
        StakingContract.unstakeCerts(underlyingAmount);

    }

/**
 * @dev Check and distribute referral rewards if the increase in underlying amount exceeds the previous amount.
 * @param _prevAmount The previous amount of underlying tokens.
 * @param _unAmount The current amount of underlying tokens.
 */
function checkReferReward(uint256 _prevAmount, uint256 _unAmount) private {
        if(_unAmount >_prevAmount ){
            uint256 rewA =  _unAmount-_prevAmount ;
            uint256 _unstakeFee = (rewA * fee)/100;
            _unstakeFeeCollected+=_unstakeFee;
            requests[msg.sender].fee += _unstakeFee; 
            _unAmount = BNBtoCAF(rewA);
            payRefs(_unAmount);
        }
}

/**
 * @dev Distribute referral rewards to up to 4 levels of referrers.
 * @param _amount The total reward amount to distribute.
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
 * @dev Claim available referral rewards and transfer them to the sender.
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
 * @dev Calculate the total earned rewards for a given account.
 * @param _account The account for which to calculate earned rewards.
 * @return The total earned rewards.
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
 * @dev Claim and transfer pending rewards to the sender.
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
 * @dev Recover ERC20 tokens from the contract, transferring them to the owner.
 * Only the owner can execute this function.
 * @param tokenAddress The address of the ERC20 token to recover.
 * @param tokenAmount The amount of ERC20 tokens to recover.
 */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(underlyingToken), "Cannot withdraw the staking token");
        IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

   
    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }
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

  
    ///Flash unstake with extra fee
    /**
 * @dev Initiate a flash unstake by swapping tokens and transferring the result to the sender.
 * @param shares The amount of shares to be unstaked.
 */
    function flashUnstake(uint256 shares) external nonReentrant {
        require(shares > 0, "Invalid shares 0");
        require(user[msg.sender].balance>= shares, "Invalid shares");
        uint256 amount = shares;
         uint256 unstakeFeeAmt = (shares * _flashUnstakeFee) / 100;
        amount -= unstakeFeeAmt;
        _flashUnstakeCollectedFee += unstakeFeeAmt;
      user[msg.sender].balance -= shares;
        StakingContract.swap(amount,msg.sender);
         emit FlashFeeAmount(unstakeFeeAmt);
        emit Unstaked(msg.sender, msg.sender, amount, shares, false);
    }
    /**
 * @dev Change the flash unstake fee.
 * Only the contract owner can execute this function.
 * @param _fee The new flash unstake fee to set.
 */
    function changeFlashUnstakeFee(uint256 _fee) external onlyOwner{
                _flashUnstakeFee=_fee;
    }
    /**
 * @dev Claim the requested unstaked amount after deducting the fee and transfer to the sender.
 */
    function claimUnstakeAmount() external  nonReentrant{
        uint256 _amount = requests[msg.sender].amount;
        uint256 _fee = requests[msg.sender].fee;
        require(_amount > 0, "No unstaking request made");
        require((address(this).balance >= _amount));
        uint256 totalAmount = _amount - _fee;
        _unsafeTransfer(msg.sender, totalAmount, true);
         emit feeAmount(_fee);
         emit unstakeClaimed(msg.sender,_amount);

    }
    /**
 * @dev Check if a user is eligible to claim their requested unstaked amount.
 * @param _user The user's address to check.
 * @return Whether the user can claim their unstaked amount.
 */
    function isClaimAvailable(address _user) public  view returns(bool){
        if(address(this).balance> 0.01 ether && requests[_user].amount > 0){
            return true;
        }else{
            return false;
        }

    }
    /**
 * @dev Claim and transfer the collected flash unstake fees to the treasury.
 */
    function claimFlashUnstakeFeeCollected() external nonReentrant {
        address treasuryAddress =  _treasuryWallet;
        require(
            treasuryAddress != address(0),
            "LiquidTokenStakingPool: treasury is not set"
        );
        uint256 amount = _flashUnstakeCollectedFee;
        _flashUnstakeCollectedFee = 0;
        bool result = _unsafeTransfer(treasuryAddress, amount, false);
        require(
            result,
            "LiquidTokenStakingPool: failed to send flashUnstake fee to treasury"
        );

        emit FlashUnstakeFeeCollectedClaimed(msg.sender, amount);
        emit FlashFeeAmount(msg.sender, amount);
    }
    

    //Convert BNB price to CAF 
    function BNBtoCAF(uint256 _amount) public  view returns(uint256){
        uint256 _bnbToCaf =Oracle.getRate(WBNB, rewardsToken, false); 
        uint256 _cafAmount = (_amount* _bnbToCaf) / 1e18;
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
 * @dev Update the treasury address.
 * Only the contract owner can execute this function.
 * @param _receiverAddress The new treasury address to set.
 */
function updateTreasuryAddress(address _receiverAddress) external onlyOwner{
    _treasuryWallet =   _receiverAddress; 
}
/**
 * @dev Withdraw collected unstake fees to the treasury.
 * Only the contract owner can execute this function.
 */
function withdrawFee() external onlyOwner{
    require(_unstakeFeeCollected >0, "No fee collected yet!");
        _unsafeTransfer(_treasuryWallet,_unstakeFeeCollected,false);
}
/**
 * @dev Fallback function to receive incoming Ether.
 */
    receive() external payable {}

}

interface  IStakingContract{
    function stakeCerts() external  payable;
    function unstakeCerts(uint256 shares) external  ;
    function swap(uint256 amount, address receiverAddress) external ; 

}
interface ICertificateToken is IERC20 {

    function sharesToBonds(uint256 amount) external view returns (uint256);

    function bondsToShares(uint256 amount) external view returns (uint256);

} 

interface IOracle {
    function getRate(
        address srcToken,
        IERC20 dstToken,
        bool useWrappers
    ) external view returns (uint256 weightedRate) ;
    
}
