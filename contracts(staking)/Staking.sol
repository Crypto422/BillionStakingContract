// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/WadMath.sol";

/**
 * @title Staking contract
 * @notice Implements the core contract of staking.
 * this contract manages all states and handles user interaction.
 * @author dderabin
 **/
contract Staking is Ownable {
    using SafeMath for uint256;
    using WadMath for uint256;

    uint256 public lendCount;
    uint256 public cashpTotalLiquidity;
    address public cashpAddress;
    address public marketWalletAddress;
    uint256 public stakingPeriod = 180 days;
    uint256 public withdrawPeriod = 1 days;
    uint256 public cashpPrice = 0.7 * 1e8;
    uint256 public ROI = 2; // 2 %
    uint256 public taxLend = 10; // 2 %

    /**
     * @dev the struct for storing the Lend data
     */
    struct LendRequest {
        address lender;
        uint256 lendId;
        uint256 lendAmount;
        uint256 timeLend;
        uint256 timeLastClaim;
        uint256 timeNextClaim;
        uint256 timeLendDueDate;
        bool retrieved;
    }

    /**
     * @dev the mapping from the user to the struct of that Lend request
     * user address => pool
     */
    mapping(address => uint256) public userLendsCount;

    /**
     * @dev the mapping from the user deposit totally
     * user address => pool
     */
    mapping(address => uint256) public userLendsAmount;

    /**
     * @dev the mapping from the user claim totally
     * user address => pool
     */
    mapping(address => uint256) public userClaimAmount;

    /**
     * @dev the mapping from user address to LendRequest to the user data of
     * that lends
     */
    mapping(address => mapping(uint256 => LendRequest)) public lends;

    /**
     * @dev emitted on init
     * @param admin the address of admin
     * @param amount the amount to init
     */
    event InitBalance(address indexed admin, uint256 amount);

    /**
     * @dev emitted on lend
     * @param lender the address of lender
     * @param lendAmount the amount to lend
     * @param timeLend the time of Lend
     * @param timeLastClaim the time of you claim
     * @param timeNextClaim the time of next claim
     * @param timeLendDueDate the duedate of lend
     * @param retrieved the flag of the user get the all interest
     */
    event NewLend(
        address indexed lender,
        uint256 lendAmount,
        uint256 timeLend,
        uint256 timeLastClaim,
        uint256 timeNextClaim,
        uint256 timeLendDueDate,
        bool retrieved
    );

    /**
     * @dev emitted on claim
     * @param claimer the type of token that withdrow
     * @param expired the flag of earn interst
     * @param claimAmount the amount to withdraw
     */
    event Claim(address claimer, uint256 claimAmount, bool expired);

    /**
     * @dev emitted on update price of cashp
     * @param price the price of cashp
     */
    event PriceOfCashPUpdated(uint256 price);

    constructor(address _cashpAddress, address _marketWalletAddress) {
        lendCount = 1;
        cashpTotalLiquidity = 0;
        cashpAddress = _cashpAddress;
        marketWalletAddress = _marketWalletAddress;
    }

    function initCashp(uint256 _amount) external onlyOwner {
        require(
            ERC20(cashpAddress).transferFrom(
                msg.sender,
                address(this),
                _amount
            ),
            "Transaction failed on init function"
        );
        ERC20(cashpAddress).increaseAllowance(address(this), _amount);

        cashpTotalLiquidity = cashpTotalLiquidity.add(_amount);
        emit InitBalance(msg.sender, _amount);
    }

    /**
     * @dev lend the specific amount of tokens
     * @param _amount the amount of tokens
     */
    function deposite(uint256 _amount) public {
        uint256 taxDepositAmount = _amount.mul(taxLend).div(100);
        uint256 depositAmount = _amount.sub(taxDepositAmount);
        require(
            ERC20(cashpAddress).transferFrom(
                msg.sender,
                address(this),
                depositAmount
            ),
            "lendToken: Transfer token from user to contract failed"
        );
        require(
            ERC20(cashpAddress).transferFrom(
                msg.sender,
                marketWalletAddress,
                taxDepositAmount
            ),
            "lendToken: Transfer token from user to contract failed"
        );
        LendRequest memory request;
        request.lender = msg.sender;
        request.lendId = userLendsCount[msg.sender];
        request.lendAmount = depositAmount;
        request.timeLend = block.timestamp;
        request.timeLendDueDate = block.timestamp + 180 days;
        request.timeLastClaim = block.timestamp;
        request.timeNextClaim = block.timestamp + 1 days;
        request.retrieved = false;
        lends[msg.sender][userLendsCount[msg.sender]] = request;
        lendCount++;
        userLendsCount[msg.sender]++;
        uint256 lendamount = userLendsAmount[msg.sender];
        lendamount = lendamount.add(depositAmount);
        userLendsAmount[msg.sender] = lendamount;

        ERC20(cashpAddress).increaseAllowance(address(this), depositAmount);
        cashpTotalLiquidity = cashpTotalLiquidity.add(depositAmount);
        emit NewLend(
            request.lender,
            request.lendAmount,
            request.timeLend,
            request.timeLastClaim,
            request.timeNextClaim,
            request.timeLendDueDate,
            request.retrieved
        );
    }

    /**
     * @dev compound the specific amount of tokens
     */
    function compound() public {
        uint256 totalClaimAmount;
        LendRequest[] memory requests = getUserAllLends();
        for (uint256 i = 0; i < requests.length; i++) {
            if (!requests[i].retrieved) {
                if (requests[i].lendId >= 0) {
                    if (requests[i].timeNextClaim <= block.timestamp) {
                        if (requests[i].lender == msg.sender) {
                            uint256 stakingDuration;

                            if (
                                requests[i].timeLendDueDate >= block.timestamp
                            ) {
                                stakingDuration = (block.timestamp -
                                    requests[i].timeLastClaim)
                                    .div(60)
                                    .div(60)
                                    .div(24);
                            } else {
                                stakingDuration = (requests[i].timeLendDueDate -
                                    requests[i].timeLastClaim)
                                    .div(60)
                                    .div(60)
                                    .div(24);
                            }

                            uint256 interestAmount = requests[i]
                                .lendAmount
                                .mul(ROI)
                                .div(100)
                                .mul(stakingDuration);

                            totalClaimAmount = totalClaimAmount.add(
                                interestAmount
                            );
                        }
                    }
                }
            }
        }
        require(
            checkEnoughLiquidity(totalClaimAmount),
            "compound: not enough Cashp liquidity of Marketing"
        );

        LendRequest memory request;
        request.lender = msg.sender;
        request.lendId = userLendsCount[msg.sender];
        request.lendAmount = totalClaimAmount;
        request.timeLend = block.timestamp;
        request.timeLendDueDate = block.timestamp + 180 days;
        request.timeLastClaim = block.timestamp;
        request.timeNextClaim = block.timestamp + 1 days;
        request.retrieved = false;
        lends[msg.sender][userLendsCount[msg.sender]] = request;
        lendCount++;
        userLendsCount[msg.sender]++;
        uint256 lendamount = userLendsAmount[msg.sender];
        userLendsAmount[msg.sender] = lendamount.add(totalClaimAmount);

        for (uint256 i = 0; i < userLendsCount[msg.sender]; i++) {
            LendRequest storage req = lends[msg.sender][i];
            if (!req.retrieved) {
                if (req.lendId >= 0) {
                    if (req.lender == msg.sender) {
                        req.timeLastClaim = block.timestamp;
                        req.timeNextClaim = block.timestamp + 1 days;
                        if (req.timeNextClaim >= req.timeLendDueDate) {
                            req.retrieved = true;
                        }
                    }
                }
            }
        }

        emit NewLend(
            request.lender,
            request.lendAmount,
            request.timeLend,
            request.timeLastClaim,
            request.timeNextClaim,
            request.timeLendDueDate,
            request.retrieved
        );
    }

    /**
     * @dev check the liquidity
     * @param _amount the amount of tokens
     */
    function checkEnoughLiquidity(uint256 _amount) public view returns (bool) {
        uint256 total;
        total = cashpTotalLiquidity;
        if (_amount > total) {
            return false;
        } else {
            return true;
        }
    }

    /**
     * @dev emitted on withDrawReserve
     * @param _amount the amount of token to withdraw
     */
    function withDrawReserve(uint256 _amount) external onlyOwner {
        require(
            checkEnoughLiquidity(_amount),
            "withDrawReserve: not enough Cashp liquidity of Marketing"
        );

        require(
            ERC20(cashpAddress).transferFrom(
                address(this),
                msg.sender,
                _amount
            ),
            "Transaction failed on init function"
        );

        cashpTotalLiquidity = cashpTotalLiquidity.sub(_amount);
    }

    /**
     * @dev get the all lends of user
     */
    function getUserAllLends() internal view returns (LendRequest[] memory) {
        LendRequest[] memory requests = new LendRequest[](
            userLendsCount[msg.sender]
        );
        for (uint256 i = 0; i < userLendsCount[msg.sender]; i++) {
            requests[i] = lends[msg.sender][i];
        }
        return requests;
    }
 
    /**
     * @dev claim the all interests
     */
    function claim() external {
        uint256 totalClaimAmount;
        LendRequest[] memory requests = getUserAllLends();
        for (uint256 i = 0; i < requests.length; i++) {
            if (!requests[i].retrieved) {
                if (requests[i].lendId >= 0) {
                    if (requests[i].timeNextClaim <= block.timestamp) {
                        if (requests[i].lender == msg.sender) {
                            uint256 stakingDuration;

                            if (
                                requests[i].timeLendDueDate >= block.timestamp
                            ) {
                                stakingDuration = (block.timestamp -
                                    requests[i].timeLastClaim)
                                    .div(60)
                                    .div(60)
                                    .div(24);
                            } else {
                                stakingDuration = (requests[i].timeLendDueDate -
                                    requests[i].timeLastClaim)
                                    .div(60)
                                    .div(60)
                                    .div(24);
                            }

                            uint256 interestAmount = requests[i]
                                .lendAmount
                                .mul(ROI)
                                .div(100)
                                .mul(stakingDuration);

                            totalClaimAmount = totalClaimAmount.add(
                                interestAmount
                            );
                        }
                    }
                }
            }
        }
        require(
            checkEnoughLiquidity(totalClaimAmount),
            "claim: not enough Cashp liquidity of Marketing"
        );

        uint256 percentage = totalClaimAmount.wadDiv(cashpTotalLiquidity).mul(
            100
        );

        uint256 whaleTax = 0;

        if (percentage >= 1 * 1e18) {
            whaleTax = totalClaimAmount.mul(5).div(100);
        } else if (percentage >= 2 * 1e18) {
            whaleTax = totalClaimAmount.mul(10).div(100);
        } else if (percentage >= 3 * 1e18) {
            whaleTax = totalClaimAmount.mul(15).div(100);
        } else if (percentage >= 4 * 1e18) {
            whaleTax = totalClaimAmount.mul(20).div(100);
        } else if (percentage >= 5 * 1e18) {
            whaleTax = totalClaimAmount.mul(25).div(100);
        } else if (percentage >= 6 * 1e18) {
            whaleTax = totalClaimAmount.mul(30).div(100);
        } else if (percentage >= 7 * 1e18) {
            whaleTax = totalClaimAmount.mul(35).div(100);
        } else if (percentage >= 8 * 1e18) {
            whaleTax = totalClaimAmount.mul(40).div(100);
        } else if (percentage >= 9 * 1e18) {
            whaleTax = totalClaimAmount.mul(45).div(100);
        } else if (percentage >= 10 * 1e18) {
            whaleTax = totalClaimAmount.mul(50).div(100);
        }

        uint256 realClaimAmount = totalClaimAmount.sub(whaleTax);
        require(
            ERC20(cashpAddress).transferFrom(
                address(this),
                msg.sender,
                realClaimAmount
            ),
            "claim: fail transfer cashp from contract to user"
        );

        require(
            ERC20(cashpAddress).transferFrom(
                address(this),
                marketWalletAddress,
                whaleTax
            ),
            "claim: fail transfer cashp from contract to market wallet "
        );

        cashpTotalLiquidity.sub(totalClaimAmount);
        uint256 newamount = userClaimAmount[msg.sender];
        userClaimAmount[msg.sender] = newamount.add(realClaimAmount);

        for (uint256 i = 0; i < userLendsCount[msg.sender]; i++) {
            LendRequest storage req = lends[msg.sender][i];
            if (!req.retrieved) {
                if (req.lendId >= 0) {
                    if (req.lender == msg.sender) {
                        req.timeLastClaim = block.timestamp;
                        req.timeNextClaim = block.timestamp + 1 days;
                        if (req.timeNextClaim >= req.timeLendDueDate) {
                            req.retrieved = true;
                        }
                    }
                }
            }
        }
    }

    /**
     * @dev set the cashp price
     * @param price the price of token
     */
    function setCashpPrice(uint256 price) external onlyOwner {
        cashpPrice = price;
        emit PriceOfCashPUpdated(cashpPrice);
    }
}
