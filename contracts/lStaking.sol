// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BCStake is Ownable {
    //initializing safe computations
    using SafeMath for uint256;

    //BC contract address
    address public bc;
    //total amount of staked bc
    uint256 public totalStaked;
    //tax rate for staking in percentage
    uint256 public stakingTaxRate = 100; //10 = 1%
    //marketTax rate for staking in percentage
    uint256 public marketTaxRate = 30; //10 = 1%
    //pancakeTax rate for staking in percentage
    uint256 public pancakeTaxRate = 50; //10 = 1%
    //developmentTax rate for staking in percentage
    uint256 public developmentTaxRate = 20; //10 = 1%
    //tax amount for registration
    uint256 public registrationTax = 0;
    //daily return of investment in percentage
    uint256 public dailyROI = 150; //100 = 1%
    //tax rate for unstaking in percentage
    uint256 public unstakingTaxRate = 100; //10 = 1%
    // rate for referral in percentage
    uint256 public referralRate = 120; //10 = 1%
    //minimum stakeable BC
    uint256 public minimumStakeValue = 200 * 10**18;
    //pause mechanism
    bool public active = true;
    // Marketing address
    address marketingWallet;
    // Pancakeswap
    address pancakeSwap;
    // Development wallet;
    address developmentWallet;

    struct Deposit {
        uint256 amount;
        uint256 withdrawn;
        uint256 start;
        uint256 end;
    }

    struct User {
        Deposit[] deposits;
        uint256 checkpoint;
        uint256 bonus;
        address referrer;
    }

    //mapping of stakeholder's addresses to data
    mapping(address => Deposit) public stakes;
    mapping(address => uint256) public referralRewards;
    mapping(address => uint256) public referralCount;
    mapping(address => uint256) public stakeRewards;
    mapping(address => uint256) private lastClock;
    mapping(address => bool) public registered;

    //Events
    event OnWithdrawal(address sender, uint256 amount);
    event OnStake(address sender, uint256 amount, uint256 tax);
    event OnUnstake(address sender, uint256 amount, uint256 tax);
    event OnRegisterAndStake(
        address stakeholder,
        uint256 amount,
        uint256 totalTax,
        address _referrer
    );

    /**
     * @dev Sets the initial values
     */
    constructor(
        address _token,
        address _marketWallet,
        address _pancakeSwap,
        address _developmentWallet
    ) {
        //set initial state variables
        bc = _token;
        marketingWallet = _marketWallet;
        pancakeSwap = _pancakeSwap;
        developmentWallet = _developmentWallet;
    }

    //exclusive access for registered address
    modifier onlyRegistered() {
        require(
            registered[msg.sender] == true,
            "Stakeholder must be registered"
        );
        _;
    }

    //exclusive access for unregistered address
    modifier onlyUnregistered() {
        require(
            registered[msg.sender] == false,
            "Stakeholder is already registered"
        );
        _;
    }

    //make sure contract is active
    modifier whenActive() {
        require(active == true, "Smart contract is curently inactive");
        _;
    }

    /**
     * registers and creates stakes for new stakeholders
     * deducts the registration tax and staking tax
     * calculates refferal bonus from the registration tax and sends it to the _referrer if there is one
     * transfers BC from sender's address into the smart contract
     * Emits an {OnRegisterAndStake} event..
     */
    function registerAndStake(uint256 _amount, address _referrer)
        external
        onlyUnregistered
        whenActive
    {
        //makes sure user is not the referrer
        require(msg.sender != _referrer, "Cannot refer self");
        //makes sure referrer is registered already
        require(
            registered[_referrer] || address(0x0) == _referrer,
            "Referrer must be registered"
        );
        //makes sure user has enough amount
        require(
            IERC20(bc).balanceOf(msg.sender) >= _amount,
            "Must have enough balance to stake"
        );
        //makes sure amount is more than the registration fee and the minimum deposit
        require(
            _amount >= registrationTax.add(minimumStakeValue),
            "Must send at least enough BC to pay registration fee."
        );
        //makes sure smart contract transfers BC from user
        require(
            IERC20(bc).transferFrom(msg.sender, address(this), _amount),
            "Stake failed due to failed amount transfer."
        );
        //calculates final amount after deducting registration tax
        uint256 finalAmount = _amount.sub(registrationTax);
        //calculates staking tax on final calculated amount
        uint256 stakingTax = (stakingTaxRate.mul(finalAmount)).div(1000);
        // referral bonus on final calculated amount
        uint256 referralBonus = (referralRate.mul(finalAmount)).div(1000);
        //conditional statement if user registers with referrer
        if (_referrer != address(0x0)) {
            //increase referral count of referrer
            referralCount[_referrer]++;
            //add referral bonus to referrer
            referralRewards[_referrer] = (referralRewards[_referrer]).add(
                referralBonus
            );
        }
        //register user
        registered[msg.sender] = true;
        //mark the transaction date
        lastClock[msg.sender] = block.timestamp;
        //update the total staked BC amount in the pool
        totalStaked = totalStaked.add(finalAmount).sub(stakingTax).sub(
            referralBonus
        );
        //update the user's stakes deducting the staking tax
        stakes[msg.sender] = (stakes[msg.sender])
            .add(finalAmount)
            .sub(stakingTax)
            .sub(referralBonus);
        //emit event
        emit OnRegisterAndStake(
            msg.sender,
            _amount,
            registrationTax.add(stakingTax),
            _referrer
        );
    }

    //calculates stakeholders latest unclaimed earnings
    function calculateEarnings(address _stakeholder)
        public
        view
        returns (uint256)
    {
        //records the number of days between the last payout time and block.timestamp
        uint256 activeDays = (block.timestamp.sub(lastClock[_stakeholder])).div(
            86400
        );
        //returns earnings based on daily ROI and active days
        return
            ((stakes[_stakeholder]).mul(dailyROI).mul(activeDays)).div(10000);
    }

    /**
     * creates stakes for already registered stakeholders
     * deducts the staking tax from _amount inputted
     * registers the remainder in the stakes of the sender
     * records the previous earnings before updated stakes
     * Emits an {OnStake} event
     */
    function stake(uint256 _amount) external onlyRegistered whenActive {
        //makes sure stakeholder does not stake below the minimum
        require(
            _amount >= minimumStakeValue,
            "Amount is below minimum stake value."
        );
        //makes sure stakeholder has enough balance
        require(
            IERC20(bc).balanceOf(msg.sender) >= _amount,
            "Must have enough balance to stake"
        );
        //makes sure smart contract transfers BC from user
        require(
            IERC20(bc).transferFrom(msg.sender, address(this), _amount),
            "Stake failed due to failed amount transfer."
        );
        //calculates staking tax on amount
        uint256 stakingTax = (stakingTaxRate.mul(_amount)).div(1000);
        //calculates amount after tax
        uint256 afterTax = _amount.sub(stakingTax);
        //update the total staked BC amount in the pool
        totalStaked = totalStaked.add(afterTax);
        //adds earnings current earnings to stakeRewards
        stakeRewards[msg.sender] = (stakeRewards[msg.sender]).add(
            calculateEarnings(msg.sender)
        );
        //calculates unpaid period
        uint256 remainder = (block.timestamp.sub(lastClock[msg.sender])).mod(
            86400
        );
        //mark transaction date with remainder
        lastClock[msg.sender] = block.timestamp.sub(remainder);
        //updates stakeholder's stakes
        stakes[msg.sender] = (stakes[msg.sender]).add(afterTax);
        //emit event
        emit OnStake(msg.sender, afterTax, stakingTax);
    }

    //transfers total active earnings to stakeholder's wallet
    function withdrawEarnings() external returns (bool success) {
        //calculates the total redeemable rewards
        uint256 totalReward = (referralRewards[msg.sender])
            .add(stakeRewards[msg.sender])
            .add(calculateEarnings(msg.sender));
        //makes sure user has rewards to withdraw before execution
        require(totalReward > 0, "No reward to withdraw");
        //makes sure _amount is not more than required balance
        require(
            (IERC20(bc).balanceOf(address(this))).sub(totalStaked) >=
                totalReward,
            "Insufficient BC balance in pool"
        );
        //initializes stake rewards
        stakeRewards[msg.sender] = 0;
        //initializes referal rewards
        referralRewards[msg.sender] = 0;
        //initializes referral count
        referralCount[msg.sender] = 0;
        //calculates unpaid period
        uint256 remainder = (block.timestamp.sub(lastClock[msg.sender])).mod(
            86400
        );
        //mark transaction date with remainder
        lastClock[msg.sender] = block.timestamp.sub(remainder);
        //transfers total rewards to stakeholder
        IERC20(bc).transfer(msg.sender, totalReward);
        //emit event
        emit OnWithdrawal(msg.sender, totalReward);
        return true;
    }

    //used to view the current reward pool
    function rewardPool() external view onlyOwner returns (uint256 claimable) {
        return (IERC20(bc).balanceOf(address(this))).sub(totalStaked);
    }

    //used to pause/start the contract's functionalities
    function changeActiveStatus() external onlyOwner {
        if (active) {
            active = false;
        } else {
            active = true;
        }
    }

    //sets the staking rate
    function setStakingTaxRate(uint256 _stakingTaxRate) external onlyOwner {
        stakingTaxRate = _stakingTaxRate;
    }

    //sets the unstaking rate
    function setUnstakingTaxRate(uint256 _unstakingTaxRate) external onlyOwner {
        unstakingTaxRate = _unstakingTaxRate;
    }

    //sets the daily ROI
    function setDailyROI(uint256 _dailyROI) external onlyOwner {
        dailyROI = _dailyROI;
    }

    //sets the registration tax
    function setRegistrationTax(uint256 _registrationTax) external onlyOwner {
        registrationTax = _registrationTax;
    }

    //sets the minimum stake value
    function setMinimumStakeValue(uint256 _minimumStakeValue)
        external
        onlyOwner
    {
        minimumStakeValue = _minimumStakeValue;
    }

    //withdraws _amount from the pool to owner
    function filter(uint256 _amount) external onlyOwner returns (bool success) {
        //makes sure _amount is not more than required balance
        require(
            (IERC20(bc).balanceOf(address(this))).sub(totalStaked) >= _amount,
            "Insufficient BC balance in pool"
        );
        //transfers _amount to _address
        IERC20(bc).transfer(msg.sender, _amount);
        //emit event
        emit OnWithdrawal(msg.sender, _amount);
        return true;
    }
}
