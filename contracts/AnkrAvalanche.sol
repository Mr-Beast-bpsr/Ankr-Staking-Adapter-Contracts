// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract AnkrStaking is ReentrancyGuard {
    ICertificateToken public immutable underlyingToken; //aankrProxy Token // Mainnet 0xc3344870d52688874b06d844E0C36cc39FC727F6 
    IERC20 public immutable rewardsToken;
    IStakingContract public immutable StakingContract;// Mainnet  0x7baa1e3bfe49db8361680785182b80bb420a836d
    IOracle public Oracle = IOracle(0x52cbE0f49CcdD4Dc6E9C13BAb024EABD2842045B);
    address public WBNB= 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address public _bontToken=0x6C6f910A79639dcC94b4feEF59Ff507c2E843929;
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
 */
    function lastTimeRewardApplicable() public view returns (uint) {
        return  block.timestamp;
    }
/**
 * @dev Get the current reward per token.
 */
    function rewardPerToken() public view returns (uint) {
            return rewardRate;
        
    }
    /**
 * @dev Change the reward rate per token.
 * @param _rewardRate The new reward rate to set.
 */
    function changeRewardPerToken(uint256 _rewardRate) external onlyOwner{
        rewardRate=_rewardRate;
    }
/**
 * @dev Stake a certain amount of ETH into the Staking Contract.
 * @param _referrer The address of the referrer who referred the user.
 */
    function stake(address _referrer) external payable nonReentrant updateReward(msg.sender) {
       require ( msg.value % 1 ether == 0 , "Value must be a whole number");
       require ( msg.value >= 1 ether, "Value must be 1 ether or greater");
        uint256 _amount= msg.value;
        require(_amount > 0, "amount = 0");
        StakingContract.stakeAndClaimCerts{value:_amount}();
        user[msg.sender].balance += _amount;
        user[msg.sender].referralAddress= _referrer;
        uint256 unAmount = underlyingToken.ratio();
        unAmount = unAmount * (msg.value/1e18);
        user[msg.sender].underlyingBalance+=unAmount;   
       

    }
   
/**
 * @dev Withdraw staked funds and claim corresponding certificates.
 */
    function withdraw() external updateReward(msg.sender)  nonReentrant {
       uint256 underlyingAmount = user[msg.sender].underlyingBalance;
       require(underlyingAmount>= 0.1 ether, "Invalid amount Called");
        uint256 currentAmount = ICertificateToken(_bontToken).sharesToBalance(underlyingAmount);

        requests[msg.sender].amount += currentAmount;
        
        uint256 balance =user[msg.sender].balance;

        user[msg.sender].balance -= balance;
        user[msg.sender].underlyingBalance-= underlyingAmount;
        checkReferReward(balance,currentAmount);
        StakingContract.claimCerts(underlyingAmount);
    }
/**
 * @dev Check and distribute referral rewards if the underlying amount exceeds the previous amount.
 * @param _prevAmount The previous amount of underlying tokens.
 * @param _unAmount The current amount of underlying tokens.
 */

function checkReferReward(uint256 _prevAmount, uint256 _unAmount) private {
        if(_unAmount >_prevAmount ){
            uint256 rewA =  _unAmount-_prevAmount ;
             uint256 _unstakeFee = (rewA * fee)/100;
            _unstakeFeeCollected+=_unstakeFee;
            requests[msg.sender].fee += _unstakeFee; 
            _unAmount = AVXtoRWT(rewA);
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
 * @dev Claim available referral rewards.
 */
function claimReferRewards()external{
        uint256 rew = rewards[msg.sender].available;
        require(rew != 0, "No rewards available");
        require(rewardsToken.balanceOf(address(this)) >= rew,"Wait for rewards to be available");
        rewards[msg.sender].available=0;
         rewardsToken.safeTransfer( msg.sender,rew);
        rewards[msg.sender].claimed+= rew;
emit ReferRewardsClaimed(msg.sender, rew);


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
/**
 * @dev Withdraw collected unstake fees to the treasury wallet.
 * Only the owner can execute this function.
 */
   function withdrawFee() external onlyOwner{
    require(_unstakeFeeCollected >0, "No fee collected yet!");
        _unsafeTransfer(_treasuryWallet,_unstakeFeeCollected,false);
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

  
/**
 * @dev Claim and transfer unstaked amount to the sender after deducting the fee.
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
 * @dev Check if a user is eligible to claim their unstaked amount.
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

    //Convert Avalanche price to Reward Tokens
    function AVXtoRWT(uint256 _amount) public  view returns(uint256){
        uint256 _avaxtoRWT =Oracle.getRate(WBNB, rewardsToken, false); 
        uint256 _cafAmount = (_amount* _avaxtoRWT) / 1e18;
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
function updateTreasuryAddress(address _receiverAddress) external onlyOwner{
    _treasuryWallet =   _receiverAddress ;
}

  receive() external payable {}
}

interface  IStakingContract{
    function stakeAndClaimCerts() external  payable;
    function claimCerts(uint256 shares) external  ;
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
