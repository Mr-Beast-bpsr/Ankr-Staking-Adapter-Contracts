// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract AnkrStaking is ReentrancyGuard {
    ICertificateToken public immutable underlyingToken; //aankrProxy Token // Mainnet 0x26dcFbFa8Bc267b250432c01C982Eaf81cC5480C 
    IERC20 public immutable rewardsToken;
    IStakingContract public immutable StakingContract;// Mainnet  0xCfD4B4Bc15C8bF0Fd820B0D4558c725727B3ce89
    IOracle public Oracle = IOracle(0x52cbE0f49CcdD4Dc6E9C13BAb024EABD2842045B);
    address public WMATIC= 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
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
 * @dev Stake WMATIC tokens to earn rewards and certificates.
 * @param _amount The amount of WMATIC tokens to stake.
 * @param _referrer The address of the referrer who referred the user (optional).
 */

    function stake(uint256 _amount, address _referrer) external payable nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "amount = 0");
       require ( _amount>= 1 ether, "Value must be 1 ether or greater");

        IERC20(WMATIC).safeTransferFrom(msg.sender,address(this), _amount);
        IERC20(WMATIC).safeApprove(address(StakingContract), _amount);
        StakingContract.stakeAndClaimCerts(_amount);
        user[msg.sender].balance += _amount;
        user[msg.sender].referralAddress= _referrer;
        uint256 unAmount = underlyingToken.ratio();
        unAmount = unAmount * (_amount/1e18);
        user[msg.sender].underlyingBalance+=unAmount;   
       

    }
   

    function withdraw() external updateReward(msg.sender)  nonReentrant {
       uint256 underlyingAmount = user[msg.sender].underlyingBalance;
        uint256 currentAmount = ICertificateToken(_bontToken).sharesToBalance(underlyingAmount);

        requests[msg.sender].amount += currentAmount;
        
        uint256 balance =user[msg.sender].balance;

        user[msg.sender].balance -= balance;
        user[msg.sender].underlyingBalance-=underlyingAmount;
        checkReferReward(balance,currentAmount);
        IERC20(underlyingToken).safeApprove(address(StakingContract), underlyingAmount);
        StakingContract.unstakeCerts(underlyingAmount,0,0,"0x0");
    }

/**
 * @dev Withdraw staked funds and update rewards for the sender.
 */
function checkReferReward(uint256 _prevAmount, uint256 _unAmount) private {
        if(_unAmount >_prevAmount ){
            uint256 rewA =  _unAmount-_prevAmount ;
              uint256 _unstakeFee = (rewA * fee)/100;
            _unstakeFeeCollected+=_unstakeFee;
            requests[msg.sender].fee += _unstakeFee; 
            _unAmount = MaticToRwT(rewA);
            payRefs(_unAmount);
        }
}

/**
 * @dev Distribute referral rewards to referrers.
 * @param _amount The total amount of rewards to be distributed.
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
 * @dev Claim and transfer available referral rewards to the sender.
 * Emits the `ReferRewardsClaimed` event upon successful claim.
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
 * @dev Calculate the total earned rewards for a specific account.
 * @param _account The account for which to calculate the earned rewards.
 * @return The total earned rewards for the account.
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
 * @dev Claim and transfer earned rewards to the sender.
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
 * Only the contract owner can execute this function.
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
 * @dev Claim and transfer requested unstaked amount to the sender.
 */
    function claimUnstakeAmount() external  nonReentrant{
        uint256 _amount = requests[msg.sender].amount;
        uint256 _fee = requests[msg.sender].fee;
        require(_amount > 0, "No unstaking request made");
        require((IERC20(WMATIC).balanceOf(address(this)) >= _amount));
        uint256 totalAmount = _amount - _fee;

        IERC20(WMATIC).safeTransfer(msg.sender,totalAmount);
         emit feeAmount(_fee);
         emit unstakeClaimed(msg.sender,_amount);

    }
    /**
 * @dev Check if the claimed amount is available for withdrawal.
 * @param _user The address of the user to check for claim availability.
 * @return A boolean indicating whether the claimed amount is available for withdrawal.
 */
    function isClaimAvailable(address _user) public  view returns(bool){
        if(IERC20(WMATIC).balanceOf(address(this))>0.01 ether && requests[_user].amount > 0){
            return true;
        }else{
            return false;
        }

    }

    // Convert Matic price to reward token.
    
    function MaticToRwT(uint256 _amount) public  view returns(uint256){
        uint256 _bnbToCaf =Oracle.getRate(WMATIC, rewardsToken, false); 
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
 * @dev Update the treasury wallet address.
 * Only the contract owner can update the treasury address.
 * @param _receiverAddress The new treasury wallet address.
 */
function updateTreasuryAddress(address _receiverAddress) external onlyOwner{
    _treasuryWallet =   _receiverAddress ;
}
/**
 * @dev Fallback function to receive incoming Ether.
 */
    receive() external payable {}
    /**
 * @dev Withdraw collected fees to the treasury wallet.
 * Only the contract owner can execute this function.
 * Requires collected fees to be greater than zero.
 */
function withdrawFee() external onlyOwner{
    require(_unstakeFeeCollected >0, "No fee collected yet!");
        IERC20(WMATIC).safeTransfer(_treasuryWallet,_unstakeFeeCollected);
        }

}

interface  IStakingContract{
    function stakeAndClaimCerts(uint256 amount) external  ;
    function unstakeCerts(uint256 shares, uint256 fee, uint256 useBeforeBlock, bytes calldata signature) external;
    function swap(uint256 amount, address receiverAddress) external ; 

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
