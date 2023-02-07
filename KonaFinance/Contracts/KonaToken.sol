// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IStrategy {
    function strategyRepay(uint256 _total, uint256 _loanId) external;
}


contract KonaFinance is ChainlinkClient, ConfirmedOwner {
    // Chain Link
    using Chainlink for Chainlink.Request;
    bytes32 private jobId = "7599d3c8f31e4ce78ad2b790cbcfc673";
    uint256 private oracleFee = (1 * LINK_DIVISIBILITY) / 10; // 0,1 * 10**18 (Varies by network and job)
    string apiUrl = "https://www.kona.finance/get_loan_validity/";
    mapping(bytes32 => uint256) requestIdsloanIDs;

    // Tokens & Addresses
    address brzToken = 0x6d8374F35DBA16a3DC32D75852009dd652252F34; // goerli 
    address linkToken = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB; // goerli 
    address oracleAddress = 0x188b71C9d27cDeE01B9b0dfF5C1aff62E8D6F434 ; // goerli 

    address public transferoAddress;
    address public backEndAddress;
    address public konaFeesAddress;
    address public atisFeesAddress;

    mapping(address=>uint256) public feesToCollect;

    struct Loan {
        bool isValid;
        string contractId;
        uint256 amount;
        uint256 lenderPendingToClaim; // amount that can be withdrawn
        uint256 repaidAmount; // total received so far from Transfero
        address rampAddress; 

        bool invested;
        address lender;
        uint256 maturity; 
        uint256 numberOfRepayments; 
        uint256 totalToWithdraw; 
        uint256 apy; 
        address contractAddress;

        uint256 atisFee;
        uint256 konaFee;
        uint256 userFees;
        address userFeesAddress;
    }

    mapping(uint256 => Loan) loans;

    //Oracle Events
    event ResultContractData(bytes32 indexed requestId, uint256 value, uint256 loanID);
    event RequestContractData(string url);
    event ErrorAPICall(uint256 loanID);
    
    //Loan Events
    event LoanDeleted(uint256 indexed loanID, address indexed lender);
    event LoanApproved(uint256 indexed loanID, address indexed lender, uint256 amount);
    event LoanCreated(uint256 indexed loanID, uint256 amount, address rampAddress, uint256 apy, uint256 userFees, address indexed userFeesAddress);
    event LoanInvested(uint256 indexed loanID, address indexed lender);
    event LoanFulfilled(uint256 indexed loanID, address indexed lender);

    constructor() ConfirmedOwner(msg.sender) {
        setChainlinkToken(linkToken); 
        setChainlinkOracle(oracleAddress); 

        backEndAddress = msg.sender;
        konaFeesAddress = msg.sender;
        atisFeesAddress = msg.sender;
        transferoAddress = msg.sender;
    }

    function registerLoanRequest(uint256 _loanID, uint256 _amount, address _rampAddress, uint256 _maturity, uint256 _numberOfRepayments, uint256 _totalToWithdraw, uint256 _apy, uint256 _userFees, address _userFeesAddress, uint256 _atisFee, uint256 _konaFee) public onlyOwner {
        require(_loanID > 0, "Invalid ID");
        require(!loans[_loanID].isValid, "Already registered");
        require(_amount > 0, "Invalid amount");
        require(_rampAddress != address(0), "Invalid ramp address");
        if (_userFees > 0) {
            require(_userFeesAddress != address(0), "Invalid fees address");
        }
        
        loans[_loanID].isValid = true;
        loans[_loanID].amount = _amount;
        loans[_loanID].rampAddress = _rampAddress;
        loans[_loanID].maturity = _maturity;
        loans[_loanID].numberOfRepayments = _numberOfRepayments;
        loans[_loanID].totalToWithdraw = _totalToWithdraw;
        loans[_loanID].apy = _apy;
        loans[_loanID].userFees = _userFees;
        loans[_loanID].userFeesAddress = _userFeesAddress;
        loans[_loanID].atisFee = _atisFee;
        loans[_loanID].konaFee = _konaFee;

        emit LoanCreated(_loanID, _amount, _rampAddress, _apy, _userFees, _userFeesAddress);
    }

    //Lender functions
    function invest(uint256 _loanID, bool _payToContract, address _contractAddress) external {
        require (IERC20(brzToken).balanceOf(msg.sender) >= loans[_loanID].amount, "You don't have enough founds");
        require(IERC20(brzToken).allowance(msg.sender,address(this)) >= loans[_loanID].amount,"Approve the contract first");

        require (loans[_loanID].lender == address(0), "There is already another investor"); 
        require(!_payToContract || _contractAddress != address(0), "Invalid contract address");

        loans[_loanID].lender = msg.sender;
        loans[_loanID].contractAddress = _contractAddress;

        triggerOracle(_loanID);
        emit LoanInvested(_loanID, msg.sender);
    }

    function claim(uint256 _requestAmount, uint256 _loanID) public {
        require(_requestAmount > 0, "Amount equal to zero");
        require(msg.sender == loans[_loanID].lender, "Invalid caller");
        require(loans[_loanID].contractAddress == address(0), "Payments are automatic"); 
        require(loans[_loanID].lenderPendingToClaim >= _requestAmount, "Invalid amount"); 
        IERC20(brzToken).transfer(msg.sender, _requestAmount);
        loans[_loanID].lenderPendingToClaim -= _requestAmount;
    }

    // Called by our backend after ATIS locked the receivable
    function finalizeLoan(uint256 _loanID, bool flag, string memory _contractId) external {
        require(msg.sender == backEndAddress);
        // Check if the loan is active
        require(loans[_loanID].invested);
        // If Atis locked correctly the receivables, the funds are finally sent to the ramp address
        if (flag) {
            loans[_loanID].contractId = _contractId;
            // Funds are sent to the Ramp Address
            require(IERC20(brzToken).transfer(loans[_loanID].rampAddress, loans[_loanID].amount));
            emit LoanApproved(_loanID, loans[_loanID].lender, loans[_loanID].amount);
            
        } else {
            // If any problem with the last step of Atis, the loan is deleted and the nvestor is refunded
            IERC20(brzToken).transfer(loans[_loanID].lender, loans[_loanID].amount);
            delete loans [_loanID];
            emit LoanDeleted(_loanID, loans[_loanID].lender);
        }
    }

    // If our backend finds a problem in the loan, it is deleted with this function
    function revertLoan(uint256 _loanID) public {
        require(msg.sender == backEndAddress);
        //if the loan was invested, investor is refunded
        if(loans[_loanID].invested){
            IERC20(brzToken).transfer(loans[_loanID].lender, loans[_loanID].amount);
        }
        delete loans[_loanID];
        emit LoanDeleted(_loanID, loans[_loanID].lender);
    }

    // Ramp Address function
    function repay(uint256 _repaymentAmount, uint256 _loanID) public {
        require (msg.sender == transferoAddress, "Only transfero can call this");
        require(IERC20(brzToken).transferFrom(msg.sender, address(this), _repaymentAmount), "Error during ERC20 transferFrom");

        uint256 atisFee;
        uint256 konaFee;
        uint256 userFees;

        if (loans[_loanID].atisFee > 0) {
            atisFee = _repaymentAmount * loans[_loanID].atisFee / 1000;
            feesToCollect[atisFeesAddress] += atisFee;
        }

        if (loans[_loanID].konaFee > 0) {
            konaFee = _repaymentAmount * loans[_loanID].konaFee / 1000;
            feesToCollect[konaFeesAddress] += konaFee;
        }

        if (loans[_loanID].userFees > 0) {
            userFees = _repaymentAmount * loans[_loanID].userFees / 1000;
            feesToCollect[loans[_loanID].userFeesAddress] += userFees;
        }

        uint256 lenderTotal = _repaymentAmount - konaFee - atisFee - userFees;

        if (loans[_loanID].contractAddress == address(0)) {
            loans[_loanID].lenderPendingToClaim += lenderTotal; 
        } else {
            IERC20(brzToken).approve(loans[_loanID].contractAddress, lenderTotal);
            IStrategy(loans[_loanID].contractAddress).strategyRepay(lenderTotal, _loanID);
        }

        loans[_loanID].repaidAmount += lenderTotal;
    }

    function triggerOracle(uint256 _loanID) internal returns (bytes32 requestId) {
        string memory _url = string(abi.encodePacked(string.concat(apiUrl, Strings.toString(_loanID))));
        Chainlink.Request memory req = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);
        req.add('get', _url);
        req.add('path', 'value'); // Chainlink nodes 1.0.0 and later support this format
        req.addInt('multiply', 1);
        emit RequestContractData(_url);
        requestId = sendChainlinkRequest(req, oracleFee);
        requestIdsloanIDs[requestId] = _loanID;
        return requestId;
    }

    function fulfill(bytes32 _requestId, uint256 _oracleValue) public recordChainlinkFulfillment(_requestId) {
        uint256 _loanID = requestIdsloanIDs[_requestId];
         
        if (_oracleValue == 1) {
            emit ErrorAPICall(_loanID);
        }
        else if(_oracleValue == 3) {
            // Could not lock receivables, delete loan
            delete loans[_loanID];
            emit LoanDeleted(_loanID, loans[_loanID].lender);
        } else {
            // In case of error during funds transfer, another investor is allowed to invest
            if (IERC20(brzToken).balanceOf(loans[_loanID].lender) < loans[_loanID].amount || IERC20(brzToken).allowance(loans[_loanID].lender,address(this)) < loans[_loanID].amount){
                loans[_loanID].lender = address(0);
            } else {
                IERC20(brzToken).transferFrom(loans[_loanID].lender, address(this), loans[_loanID].amount);
                loans[_loanID].invested = true;
                emit LoanFulfilled(_loanID, loans[_loanID].lender);
            }
        }
        
        emit ResultContractData(_requestId, _oracleValue, _loanID);
    }

    // Allow withdraw of Link tokens from the contract
    function withdrawLink() external onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), 'Unable to transfer');
    }

    function linkBalance() public view returns(uint256) {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        return link.balanceOf(address(this));
    }

    function claimFees() external {
        uint256 total = feesToCollect[msg.sender];
        feesToCollect[msg.sender] = 0;
        IERC20(brzToken).transfer(msg.sender, total);
    }
    
    function updateAddresses(address _backEndAddress, address _konaFeesAddress, address _atisFeesAddress) onlyOwner external {
        backEndAddress = _backEndAddress;
        konaFeesAddress = _konaFeesAddress;
        atisFeesAddress = _atisFeesAddress;
    }

    function updateLoan(uint256 _loanID, uint256 _maturity, uint256 _numberOfRepayments, uint256 _totalToWithdraw, uint256 _apy) external onlyOwner{
        loans[_loanID].maturity = _maturity;        
        loans[_loanID].totalToWithdraw = _totalToWithdraw;
        loans[_loanID].numberOfRepayments = _numberOfRepayments;
        loans[_loanID].apy = _apy;
    }

    function getLoan(uint256 _loanID) public view returns (string memory, uint256, uint256, uint256, address, bool, address, uint256, uint256, uint256, uint256, address) {
        Loan memory loan = loans[_loanID];

        if (!loan.isValid){
            return ('', 0, 0, 0, address(0), false, address(0), 0, 0, 0, 0, address(0));
        }

        return (loan.contractId, loan.amount, loan.lenderPendingToClaim, loan.repaidAmount, loan.rampAddress, loan.invested,
        loan.lender, loan.maturity, loan.numberOfRepayments, loan.totalToWithdraw, loan.apy, loan.contractAddress);
    }

    function getLoanFees(uint256 _loanID) public view returns (uint256, uint256, uint256, address) {
        Loan memory loan = loans[_loanID];

        if (!loan.isValid){
            return (0, 0, 0, address(0));
        }

        return (loan.atisFee, loan.konaFee, loan.userFees, loan.userFeesAddress);
    }
}