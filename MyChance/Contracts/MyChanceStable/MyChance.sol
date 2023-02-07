// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;


import {IPool} from './IPool.sol';
import {IPrizeBond} from './IPrizeBond.sol';
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "./LibMyChance.sol";
import "./LibLendingPool.sol";
import "./LibConstants.sol";
import "./RandomRequester.sol";
import "./Charities.sol";


interface IMigration {
    function migrate(
        uint256 tokenId,
        uint256 weight
    ) external returns(bool);
}

abstract contract Lottery is Charities, RandomRequester, Pausable, KeeperCompatibleInterface {
    mapping(uint256=>LMyChance.SpecialLottery) specialLotteries; //Dates for Special Lotteries
    mapping(uint256=>uint256) reqToSpecialLottery; //ReqID to Date (for Special Lottery)

    mapping(uint256 => uint256) public mintingDate;
    mapping(IPrizeBond.Assets=>uint256) public platformStakes;

    mapping(uint256 => mapping(IPrizeBond.Assets=>uint256)) public claimable;

    mapping(IPrizeBond.Assets=>uint256) public totalFees;

    mapping(IPrizeBond.Assets=>mapping(address=>uint256)) increasedStakes; // It keeps track of the staking of each user 
    uint256[] prizeBonds;

    mapping(uint256 => LMyChance.PrizeBondPosition) prizeBondPositions;

    uint256 pendingDAI;
    uint256 pendingUSDT;
    uint256 pendingUSDC;
    
    uint256 totalDAIBonds;
    uint256 totalUSDTBonds;
    uint256 totalUSDCBonds;
    uint256 sumWeights;
    bool claimNotRequired = false;
    bool waitNotRequired = true;

    uint256 lastDrawn; //Date for the last normal drawn;

    struct ClaimVariables {
        uint256 totalFeesDAI;
        uint256 totalToCharityDAI;
        uint256 withdrawalAmountDAI;
        uint256 totalFeesUSDT;
        uint256 totalToCharityUSDT;
        uint256 withdrawalAmountUSDT;
        uint256 totalFeesUSDC;
        uint256 totalToCharityUSDC;
        uint256 withdrawalAmountUSDC;
    }

    //Events
    event NewSpecialDraw(uint256 _drawDate);
    event SpecialDrawExecuted(uint256 indexed _tokenIdWinner, uint256 indexed _drawDate);
    event DrawExecuted(uint256 indexed _tokenIdWinner);
    event AssetsClaimed(address indexed _beneficiary, uint256 indexed _tokenId, uint256 _totalWinnerDAI, uint256 _totalToCharityDAI, uint256 _totalFeesDAI, uint256 _totalWinnerUSDT, uint256 _totalToCharityUSDT, uint256 _totalFeesUSDT, uint256 _totalWinnerUSDC, uint256 _totalToCharityUSDC, uint256 _totalFeesUSDC);
    event PrizeBondBurnt(uint256 indexed _tokenId);
    event StakeIncreased(IPrizeBond.Assets _assetType, uint256 _total);
    event StakeReduced(IPrizeBond.Assets _assetType, uint256 _total);
    event FeesClaimed(uint256 _totalDAI, uint256 _totalUSDT, uint256 _totalUSDC);

    constructor() {
        lastDrawn = block.timestamp - LibConstants.TIME_FOR_NEXT_DRAW;
        claimNotRequired = true;
        waitNotRequired = true;
    }

    //Public functions

    function draw() public whenNotPaused {
        require(canDraw(), "Not yet");

        lastDrawn = block.timestamp;
        _randomnessRequest();
    }

    function drawSpecialLottery(uint256 _drawDate) external whenNotPaused {
        LMyChance.SpecialLottery storage specialLottery = specialLotteries[_drawDate];
        require(specialLottery.valid, "Invalid");
        require(block.timestamp > _drawDate, "Not yet");
        require(specialLottery.drawn == false, "Already drawn");
        require(prizeBonds.length > 0, "Not enough bonds");

        specialLottery.drawn = true;
        uint256 reqId = _randomnessRequest();
        reqToSpecialLottery[reqId] = _drawDate;
    }
    
    function claim(uint256 _tokenId, uint256 _percentage) external {
        require(LibConstants.prizeBond.ownerOf(_tokenId) == msg.sender, "Invalid owner");
        require(howMuchToClaim(_tokenId) > 0, "Nothing to claim");
        require((block.timestamp > mintingDate[_tokenId] + LibConstants.TIME_FOR_NEXT_DRAW) || waitNotRequired, "Winner has to wait a week");
        require(_percentage >= 5, "Minimum is 5%");


        if (_percentage > 100) {
            _percentage = 100;
        }

        uint256 totalDAI = claimable[_tokenId][IPrizeBond.Assets.DAI];
        claimable[_tokenId][IPrizeBond.Assets.DAI] = 0;

        uint256 totalUSDT = claimable[_tokenId][IPrizeBond.Assets.USDT];
        claimable[_tokenId][IPrizeBond.Assets.USDT] = 0;

        uint256 totalUSDC = claimable[_tokenId][IPrizeBond.Assets.USDC];
        claimable[_tokenId][IPrizeBond.Assets.USDC] = 0;

        address charity = aCharities[currentCharity % (aCharities.length - 1)];
        currentCharity += 1;

        ClaimVariables memory claimVariables;

        if (totalDAI > 0) {  
            (claimVariables.withdrawalAmountDAI, claimVariables.totalFeesDAI, claimVariables.totalToCharityDAI) = LMyChance.claimInternal(totalDAI, _percentage);
            totalFees[IPrizeBond.Assets.DAI] += claimVariables.totalFeesDAI;
            pendingDAI -= claimVariables.withdrawalAmountDAI;
            LibLendingPool.withdraw(LibConstants.daiToken, claimVariables.withdrawalAmountDAI, address(this));
            require(IERC20(LibConstants.daiToken).transfer(msg.sender, (claimVariables.withdrawalAmountDAI - claimVariables.totalToCharityDAI)), 'Transfer failed');
            require(IERC20(LibConstants.daiToken).transfer(charity, claimVariables.totalToCharityDAI), 'Transfer failed');
        }

        if (totalUSDT > 0) {
            (claimVariables.withdrawalAmountUSDT, claimVariables.totalFeesUSDT, claimVariables.totalToCharityUSDT) = LMyChance.claimInternal(totalUSDT, _percentage);
            totalFees[IPrizeBond.Assets.USDT] += claimVariables.totalFeesUSDT;
            pendingUSDT -= claimVariables.withdrawalAmountUSDT;
            LibLendingPool.withdraw(LibConstants.usdtToken, claimVariables.withdrawalAmountUSDT, address(this));
            require(IERC20(LibConstants.usdtToken).transfer(msg.sender, (claimVariables.withdrawalAmountUSDT - claimVariables.totalToCharityUSDT)), 'Transfer failed');
            require(IERC20(LibConstants.usdtToken).transfer(charity, claimVariables.totalToCharityUSDT), 'Transfer failed');
        }

        if (totalUSDC > 0) {
            (claimVariables.withdrawalAmountUSDC, claimVariables.totalFeesUSDC, claimVariables.totalToCharityUSDC) = LMyChance.claimInternal(totalUSDC, _percentage);            
            totalFees[IPrizeBond.Assets.USDC] += claimVariables.totalFeesUSDC;
            pendingUSDC -= claimVariables.withdrawalAmountUSDC;
            LibLendingPool.withdraw(LibConstants.usdcToken, claimVariables.withdrawalAmountUSDC, address(this));
            require(IERC20(LibConstants.usdcToken).transfer(msg.sender, (claimVariables.withdrawalAmountUSDC - claimVariables.totalToCharityUSDC)), 'Transfer failed');
            require(IERC20(LibConstants.usdcToken).transfer(charity, claimVariables.totalToCharityUSDC), 'Transfer failed');
        }
        

        emit AssetsClaimed(msg.sender, 
                           _tokenId,  
                           (claimVariables.withdrawalAmountDAI - claimVariables.totalToCharityDAI), 
                            claimVariables.totalToCharityDAI, 
                            claimVariables.totalFeesDAI, 
                            (claimVariables.withdrawalAmountUSDC - claimVariables.totalToCharityUSDC), 
                            claimVariables.totalToCharityUSDT, 
                            claimVariables.totalFeesUSDT, 
                            (claimVariables.withdrawalAmountUSDT - claimVariables.totalToCharityUSDT), 
                            claimVariables.totalToCharityUSDC, 
                            claimVariables.totalFeesUSDC);
    }

    function mintPrizeBond(IPrizeBond.Assets _assetType, uint weight) external whenNotPaused {
        require(weight > 0, "Invalid weight");

        if (_assetType == IPrizeBond.Assets.DAI) {
            uint256 cost = LibConstants.PRICE * weight * 1e18;
            require(IERC20(LibConstants.daiToken).transferFrom(msg.sender, address(this), cost), "Transfer failed");
            LibLendingPool.supply(LibConstants.daiToken, cost);            
            totalDAIBonds += weight;
        } 
        else if (_assetType == IPrizeBond.Assets.USDC) {
            uint256 cost = LibConstants.PRICE * weight * 1e6;
            require(IERC20(LibConstants.usdcToken).transferFrom(msg.sender, address(this), cost), "Transfer failed");
            LibLendingPool.supply(LibConstants.usdcToken, cost);  
            totalUSDCBonds += weight;
        }
        else if (_assetType == IPrizeBond.Assets.USDT) {
            uint256 cost = LibConstants.PRICE * weight * 1e6;
            require(IERC20(LibConstants.usdtToken).transferFrom(msg.sender, address(this), cost), "Transfer failed");
            LibLendingPool.supply(LibConstants.usdtToken, cost);  
            totalUSDTBonds += weight;
        } else {
            revert();
        } 

        LMyChance.mint(LibConstants.prizeBond, _assetType, weight, mintingDate, prizeBonds, prizeBondPositions);
        sumWeights += weight;
    }

    function burnPrizeBond(uint256 _tokenId) external {
        require(howMuchToClaim(_tokenId) == 0 || claimNotRequired, "Please claim first");
        require(LibConstants.prizeBond.ownerOf(_tokenId) == msg.sender, "Invalid owner");

        IPrizeBond.Assets assetType = LibConstants.prizeBond.getAssetType(_tokenId);

        LibConstants.prizeBond.safeBurn(_tokenId);

        uint256 weight= prizeBondPositions[_tokenId].weight;

        if (assetType == IPrizeBond.Assets.DAI) {
            LibLendingPool.withdraw(LibConstants.daiToken, LibConstants.PRICE * weight * 1e18, msg.sender);
            totalDAIBonds -= weight;
        } 
        else if (assetType == IPrizeBond.Assets.USDC) {
            LibLendingPool.withdraw(LibConstants.usdcToken, LibConstants.PRICE * weight * 1e6, msg.sender);
            totalUSDCBonds -= weight;
        }
        else if (assetType == IPrizeBond.Assets.USDT) {
            LibLendingPool.withdraw(LibConstants.usdtToken, LibConstants.PRICE * weight * 1e6, msg.sender);
            totalUSDTBonds -= weight;
        } else {
            revert("Invalid type");
        }

        // Updates the list of prize bonds
        uint256 deletedWeght = LMyChance.removeTicket(prizeBondPositions,prizeBonds,_tokenId);
        sumWeights -= deletedWeght;

        emit PrizeBondBurnt(_tokenId);
    }

    function increaseStake(IPrizeBond.Assets _assetType, uint256 _total) external whenNotPaused {
        if (_assetType == IPrizeBond.Assets.DAI) {
            require(IERC20(LibConstants.daiToken).transferFrom(msg.sender, address(this), _total), 'Transfer failed');
            LibLendingPool.supply(LibConstants.daiToken, _total);
        } 
        else if (_assetType == IPrizeBond.Assets.USDC) {
            require(IERC20(LibConstants.usdcToken).transferFrom(msg.sender, address(this), _total), 'Transfer failed');
            LibLendingPool.supply(LibConstants.usdcToken, _total);
        }
        else if (_assetType == IPrizeBond.Assets.USDT){
            require(IERC20(LibConstants.usdtToken).transferFrom(msg.sender, address(this), _total), 'Transfer failed');
            LibLendingPool.supply(LibConstants.usdtToken, _total);
        } else {
            revert();
        }

        platformStakes[_assetType] += _total;
        increasedStakes[_assetType][msg.sender] += _total;

        emit StakeIncreased(_assetType, _total);
    }

    function reduceStake(IPrizeBond.Assets _assetType, uint256 _total) external {
        require(increasedStakes[_assetType][msg.sender] >= _total, "Invalid amount");
        platformStakes[_assetType] -= _total;
        increasedStakes[_assetType][msg.sender]-=_total;

        if (_assetType == IPrizeBond.Assets.DAI) {
            LibLendingPool.withdraw(LibConstants.daiToken, _total, msg.sender);
        } 
        else if (_assetType == IPrizeBond.Assets.USDC) {
            LibLendingPool.withdraw(LibConstants.usdcToken, _total, msg.sender);
        }
        else if (_assetType == IPrizeBond.Assets.USDT) {
            LibLendingPool.withdraw(LibConstants.usdtToken, _total, msg.sender);
        } else {
            revert();
        }

        emit StakeReduced(_assetType, _total);
    }

    //Public getters

    function canDraw() internal view returns (bool) {
        return block.timestamp >= getNextDrawDate() && prizeBonds.length > 0;
    }

    function howMuchToClaim(uint256 _tokenId) public view returns(uint256) {
        return claimable[_tokenId][IPrizeBond.Assets.DAI] + claimable[_tokenId][IPrizeBond.Assets.USDT] + claimable[_tokenId][IPrizeBond.Assets.USDC];
    }

    function accumulatedDAI() public view returns (uint256) {
        return IERC20(LibConstants.aDaiToken).balanceOf(address(this)) - totalDAIBonds * LibConstants.PRICE * 1e18 - pendingDAI - platformStakes[IPrizeBond.Assets.DAI];
    }

    function accumulatedUSDT() public view returns (uint256) {
        return IERC20(LibConstants.aUsdtToken).balanceOf(address(this)) - totalUSDTBonds * LibConstants.PRICE * 1e6 - pendingUSDT - platformStakes[IPrizeBond.Assets.USDT];
    }

    function accumulatedUSDC() public view returns (uint256) {
        return IERC20(LibConstants.aUsdcToken).balanceOf(address(this)) - totalUSDCBonds * LibConstants.PRICE * 1e6 - pendingUSDC - platformStakes[IPrizeBond.Assets.USDC];
    }

    function getNextDrawDate() public view returns(uint256) {
        return lastDrawn + LibConstants.TIME_FOR_NEXT_DRAW;
    }

    //Internal functions
    function _executeDraw(uint256 _random) internal { 
        uint256 winnerIndex = LMyChance.winner_index(_random, prizeBonds, prizeBondPositions, sumWeights);
        uint256 tokenId = prizeBonds[winnerIndex];

        uint256 totalDAI = accumulatedDAI();
        uint256 totalUSDT = accumulatedUSDT();
        uint256 totalUSDC = accumulatedUSDC();

        pendingDAI += totalDAI;
        pendingUSDT += totalUSDT;
        pendingUSDC += totalUSDC;

        if (totalDAI > 0) 
        {
            claimable[tokenId][IPrizeBond.Assets.DAI] += totalDAI;
        }

        if (totalUSDT > 0) {
            claimable[tokenId][IPrizeBond.Assets.USDT] += totalUSDT;
        }

        if (totalUSDC > 0) {
            claimable[tokenId][IPrizeBond.Assets.USDC] += totalUSDC;
        }

        emit DrawExecuted(tokenId);
    }

    function _executeSpecialDraw(uint256 _random, uint256 _specialLotDate) internal {
        uint256 winnerIndex = LMyChance.winner_index(_random, prizeBonds, prizeBondPositions, sumWeights);
        uint256 tokenId = prizeBonds[winnerIndex];

        LMyChance.SpecialLottery storage lottery = specialLotteries[_specialLotDate];
        lottery.winner = tokenId;
        claimable[tokenId][lottery.assetType] += lottery.total;

        emit SpecialDrawExecuted(tokenId, _specialLotDate);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        if (reqToSpecialLottery[requestId] > 0) {
            _executeSpecialDraw(randomWords[0], reqToSpecialLottery[requestId]);
        } else {
            _executeDraw(randomWords[0]);
        }
    } 

    //ADMIN functions
    function setClaimNotRequired(bool _set) onlyRole(DEFAULT_ADMIN_ROLE) public {
        claimNotRequired = _set;
    }

    function setWaitNotRequired(bool _set) onlyRole(DEFAULT_ADMIN_ROLE) public {
        waitNotRequired = _set;
    }

    function _claimFees() onlyRole(FEES_ROLE) public {
        uint256 daiFees = totalFees[IPrizeBond.Assets.DAI];
        totalFees[IPrizeBond.Assets.DAI] = 0;

        uint256 usdtFees = totalFees[IPrizeBond.Assets.USDT];
        totalFees[IPrizeBond.Assets.USDT] = 0;

        uint256 usdcFees = totalFees[IPrizeBond.Assets.USDC];
        totalFees[IPrizeBond.Assets.USDC] = 0;

        if (daiFees > 0) {
            LibLendingPool.withdraw(LibConstants.daiToken, daiFees, msg.sender);
            pendingDAI-=daiFees;
        }

        if (usdtFees > 0) {
            LibLendingPool.withdraw(LibConstants.usdtToken, usdtFees, msg.sender);
            pendingUSDT-=usdtFees;
        }

        if (usdcFees > 0) {
            LibLendingPool.withdraw(LibConstants.usdcToken, usdcFees, msg.sender);
            pendingUSDC-=usdcFees;
        }

        emit FeesClaimed(daiFees, usdtFees, usdcFees);
    }

    function _addSpecialLottery(uint256 _drawDate, IPrizeBond.Assets _assetType, uint256 _total, string memory _description) public onlyRole(DEFAULT_ADMIN_ROLE) {
        address token;

        if (_assetType == IPrizeBond.Assets.DAI) {
            token = LibConstants.daiToken;
            pendingDAI += _total;
        } else if (_assetType == IPrizeBond.Assets.USDC) {
            token = LibConstants.usdcToken;
            pendingUSDC += _total;

        } else if (_assetType == IPrizeBond.Assets.USDT) {
            token = LibConstants.usdtToken;
            pendingUSDT += _total;
        } else {
            revert();
        }
        require(IERC20(token).transferFrom(msg.sender, address(this), _total), 'Transfer failed');
        LMyChance.addSpecialLottery(_total, _assetType, specialLotteries, _drawDate, _description);
        LibLendingPool.supply(token, _total);
        emit NewSpecialDraw(_drawDate);
    }
    
    receive() external payable {}
}

abstract contract Recovery is Lottery {
    function _recoverTokens(uint256 _amount, address _asset) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(prizeBonds.length == 0, "Contract in use");
        require(IERC20(_asset).transfer(msg.sender, _amount), 'Transfer failed');
    }

    function _recoverAVAX(uint256 _amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        payable(msg.sender).transfer(_amount);
    }

    function _withdrawAndRecover(uint256 _amount, address _asset) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(prizeBonds.length == 0, "Contract in use");
        LibLendingPool.withdraw(_asset, _amount, msg.sender);
    }
}

abstract contract Migratable is Recovery {
    address newInstance;

    function startMigration(address _newInstance) public onlyRole(MIGRATOR_ROLE) {
        require (newInstance == address(0), "Already set");
        newInstance = _newInstance;
    }

    function migrateMyself(uint256 _tokenId) external {
        require(howMuchToClaim(_tokenId) == 0 || claimNotRequired, "You must claim first");
        require(LibConstants.prizeBond.ownerOf(_tokenId) == msg.sender, "Invalid owner");
        require (newInstance != address(0), "Cannot migrate yet");

        IPrizeBond.Assets assetType = LibConstants.prizeBond.getAssetType(_tokenId);
        uint256 weight = prizeBondPositions[_tokenId].weight;

        uint256 total;
        address token;

        if (assetType == IPrizeBond.Assets.DAI) {
            total = LibConstants.PRICE * weight * 1e18;
            token = LibConstants.aDaiToken;
            totalDAIBonds -= weight;
        } 
        else if (assetType == IPrizeBond.Assets.USDC) {
            total = LibConstants.PRICE * weight * 1e6;
            token = LibConstants.aUsdcToken;
            totalUSDCBonds -= weight;
        }
        else if (assetType == IPrizeBond.Assets.USDT) {
            total = LibConstants.PRICE * weight * 1e6;
            token = LibConstants.aUsdtToken;
            totalUSDTBonds -= weight;
        } else {
            revert("Invalid type");
        }

        require(IERC20(token).transfer(newInstance, total), 'Transfer failed');

        require(IMigration(newInstance).migrate(_tokenId, weight), "Migration failed");

        // Updates the list of prize bonds
        uint256 deletedWeght = LMyChance.removeTicket(prizeBondPositions, prizeBonds, _tokenId);
        sumWeights -= deletedWeght;        
    }
}

contract MyChance is Migratable {
    constructor() {
        _approveLP(LibConstants.daiToken, LibConstants.MAX_INT);
        _approveLP(LibConstants.usdtToken, LibConstants.MAX_INT);
        _approveLP(LibConstants.usdcToken, LibConstants.MAX_INT);
    }

    //Keepers Functions
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded = canDraw();
    }

    function performUpkeep(bytes calldata) external override {
        draw();
    }

    //Pausable
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    //ChainLink
    function _updateCallbackGasLimit(uint32 _callbackGasLimit) public onlyRole(DEFAULT_ADMIN_ROLE) {
        callbackGasLimit = _callbackGasLimit;
    }

    //ERC20
    function _approveLP(address _token, uint256 _amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        LibLendingPool.approve(_token, _amount);        
    }

    //Public
    function getTotalPrizeBonds() public view returns(uint256) {
        return prizeBonds.length;
    }
 
    function getStakedAmount(IPrizeBond.Assets _assetType) public view returns (uint256){
        return increasedStakes[_assetType][msg.sender];
    }
    
    function getListOfTickets() public view returns (uint256[] memory){
        return prizeBonds;
    }

    function getTicketData(uint256 tokenId) public view returns (LMyChance.PrizeBondPosition memory ) {
        return prizeBondPositions[tokenId];
    }

    function getState() public view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256, bool, bool) {
        return (pendingDAI, pendingUSDT, pendingUSDC, totalDAIBonds, totalUSDTBonds, totalUSDCBonds, sumWeights, claimNotRequired, waitNotRequired);
    }
}