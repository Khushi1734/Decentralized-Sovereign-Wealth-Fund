// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Decentralized Sovereign Wealth Fund
 * @dev A blockchain-based sovereign wealth fund for transparent asset management and citizen benefit distribution
 */
contract DecentralizedSovereignWealthFund is ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;
    
    // Roles
    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");
    bytes32 public constant CITIZEN_REGISTRAR_ROLE = keccak256("CITIZEN_REGISTRAR_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");
    
    // Struct for investment allocation
    struct Investment {
        address asset;           // Token contract address (address(0) for ETH)
        uint256 amount;         // Amount invested
        uint256 timestamp;      // Investment timestamp
        string description;     // Investment description
        bool active;           // Investment status
    }
    
    // Struct for citizen registration
    struct Citizen {
        bool registered;
        uint256 registrationTime;
        uint256 lastDistributionClaim;
        bool eligible;
    }
    
    // State variables
    mapping(uint256 => Investment) public investments;
    mapping(address => Citizen) public citizens;
    mapping(address => uint256) public assetBalances;
    
    uint256 public investmentCounter;
    uint256 public totalCitizens;
    uint256 public distributionInterval = 90 days; // Quarterly distributions
    uint256 public lastDistributionTime;
    uint256 public minimumReserveRatio = 2000; // 20% in basis points
    
    // Events
    event InvestmentMade(
        uint256 indexed investmentId,
        address indexed asset,
        uint256 amount,
        string description
    );
    
    event CitizenRegistered(address indexed citizen, uint256 timestamp);
    
    event BenefitDistributed(
        address indexed citizen,
        uint256 amount,
        uint256 distributionRound
    );
    
    event FundsDeposited(address indexed depositor, uint256 amount);
    
    event EmergencyWithdrawal(address indexed asset, uint256 amount);
    
    constructor(address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(TREASURY_MANAGER_ROLE, _admin);
        _grantRole(CITIZEN_REGISTRAR_ROLE, _admin);
        _grantRole(AUDITOR_ROLE, _admin);
        
        lastDistributionTime = block.timestamp;
    }
    
    /**
     * @dev Deposit funds into the sovereign wealth fund
     * @param _amount Amount to deposit (for ERC20 tokens)
     * @param _token Token address (address(0) for ETH)
     */
    function depositFunds(uint256 _amount, address _token) external payable nonReentrant whenNotPaused {
        if (_token == address(0)) {
            // ETH deposit
            require(msg.value > 0, "Must send ETH");
            assetBalances[address(0)] += msg.value;
            emit FundsDeposited(msg.sender, msg.value);
        } else {
            // ERC20 token deposit
            require(_amount > 0, "Amount must be greater than zero");
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            assetBalances[_token] += _amount;
            emit FundsDeposited(msg.sender, _amount);
        }
    }
    
    /**
     * @dev Make strategic investments with fund assets
     * @param _asset Asset to invest (address(0) for ETH)
     * @param _amount Amount to invest
     * @param _description Description of the investment
     * @param _recipient Recipient address for the investment
     */
    function makeInvestment(
        address _asset,
        uint256 _amount,
        string calldata _description,
        address _recipient
    ) external onlyRole(TREASURY_MANAGER_ROLE) nonReentrant whenNotPaused {
        require(_amount > 0, "Investment amount must be greater than zero");
        require(_recipient != address(0), "Invalid recipient address");
        require(bytes(_description).length > 0, "Investment description required");
        
        // Check if sufficient funds available and maintain reserve ratio
        uint256 availableBalance = assetBalances[_asset];
        uint256 reserveRequired = (availableBalance * minimumReserveRatio) / 10000;
        require(availableBalance >= _amount + reserveRequired, "Insufficient funds or reserve requirement not met");
        
        uint256 investmentId = investmentCounter++;
        
        investments[investmentId] = Investment({
            asset: _asset,
            amount: _amount,
            timestamp: block.timestamp,
            description: _description,
            active: true
        });
        
        // Update asset balance
        assetBalances[_asset] -= _amount;
        
        // Transfer funds to investment recipient
        if (_asset == address(0)) {
            payable(_recipient).transfer(_amount);
        } else {
            IERC20(_asset).safeTransfer(_recipient, _amount);
        }
        
        emit InvestmentMade(investmentId, _asset, _amount, _description);
    }
    
    /**
     * @dev Distribute benefits to eligible citizens
     * @param _citizens Array of citizen addresses to receive benefits
     * @param _amounts Array of benefit amounts corresponding to each citizen
     */
    function distributeBenefits(
        address[] calldata _citizens,
        uint256[] calldata _amounts
    ) external onlyRole(TREASURY_MANAGER_ROLE) nonReentrant whenNotPaused {
        require(_citizens.length == _amounts.length, "Arrays length mismatch");
        require(block.timestamp >= lastDistributionTime + distributionInterval, "Distribution interval not met");
        require(_citizens.length > 0, "No citizens specified");
        
        uint256 totalDistribution = 0;
        
        // Calculate total distribution amount
        for (uint256 i = 0; i < _amounts.length; i++) {
            totalDistribution += _amounts[i];
        }
        
        // Check if sufficient ETH balance for distribution
        require(assetBalances[address(0)] >= totalDistribution, "Insufficient ETH balance for distribution");
        
        // Distribute benefits
        for (uint256 i = 0; i < _citizens.length; i++) {
            address citizen = _citizens[i];
            uint256 amount = _amounts[i];
            
            require(citizens[citizen].registered, "Citizen not registered");
            require(citizens[citizen].eligible, "Citizen not eligible");
            require(amount > 0, "Benefit amount must be greater than zero");
            
            // Update citizen's last distribution claim
            citizens[citizen].lastDistributionClaim = block.timestamp;
            
            // Update asset balance
            assetBalances[address(0)] -= amount;
            
            // Transfer benefit
            payable(citizen).transfer(amount);
            
            emit BenefitDistributed(citizen, amount, block.timestamp);
        }
        
        lastDistributionTime = block.timestamp;
    }
    
    /**
     * @dev Register a new citizen for benefit eligibility
     * @param _citizen Address of the citizen to register
     */
    function registerCitizen(address _citizen) external onlyRole(CITIZEN_REGISTRAR_ROLE) {
        require(_citizen != address(0), "Invalid citizen address");
        require(!citizens[_citizen].registered, "Citizen already registered");
        
        citizens[_citizen] = Citizen({
            registered: true,
            registrationTime: block.timestamp,
            lastDistributionClaim: 0,
            eligible: true
        });
        
        totalCitizens++;
        
        emit CitizenRegistered(_citizen, block.timestamp);
    }
    
    /**
     * @dev Update citizen eligibility status
     * @param _citizen Address of the citizen
     * @param _eligible New eligibility status
     */
    function updateCitizenEligibility(address _citizen, bool _eligible) external onlyRole(CITIZEN_REGISTRAR_ROLE) {
        require(citizens[_citizen].registered, "Citizen not registered");
        citizens[_citizen].eligible = _eligible;
    }
    
    /**
     * @dev Get fund statistics
     */
    function getFundStatistics() external view returns (
        uint256 totalETHBalance,
        uint256 totalInvestments,
        uint256 registeredCitizens,
        uint256 nextDistributionTime
    ) {
        return (
            assetBalances[address(0)],
            investmentCounter,
            totalCitizens,
            lastDistributionTime + distributionInterval
        );
    }
    
    /**
     * @dev Get investment details
     * @param _investmentId ID of the investment
     */
    function getInvestment(uint256 _investmentId) external view returns (Investment memory) {
        require(_investmentId < investmentCounter, "Investment does not exist");
        return investments[_investmentId];
    }
    
    /**
     * @dev Get citizen information
     * @param _citizen Address of the citizen
     */
    function getCitizenInfo(address _citizen) external view returns (Citizen memory) {
        return citizens[_citizen];
    }
    
    /**
     * @dev Update distribution interval (only admin)
     * @param _newInterval New distribution interval in seconds
     */
    function updateDistributionInterval(uint256 _newInterval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newInterval >= 30 days, "Interval too short");
        require(_newInterval <= 365 days, "Interval too long");
        distributionInterval = _newInterval;
    }
    
    /**
     * @dev Update minimum reserve ratio (only admin)
     * @param _newRatio New reserve ratio in basis points
     */
    function updateReserveRatio(uint256 _newRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newRatio >= 1000, "Reserve ratio too low"); // Minimum 10%
        require(_newRatio <= 5000, "Reserve ratio too high"); // Maximum 50%
        minimumReserveRatio = _newRatio;
    }
    
    /**
     * @dev Emergency withdrawal function (only admin)
     * @param _asset Asset to withdraw (address(0) for ETH)
     * @param _amount Amount to withdraw
     */
    function emergencyWithdraw(address _asset, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_amount > 0, "Amount must be greater than zero");
        require(assetBalances[_asset] >= _amount, "Insufficient balance");
        
        assetBalances[_asset] -= _amount;
        
        if (_asset == address(0)) {
            payable(msg.sender).transfer(_amount);
        } else {
            IERC20(_asset).safeTransfer(msg.sender, _amount);
        }
        
        emit EmergencyWithdrawal(_asset, _amount);
    }
    
    /**
     * @dev Pause contract operations (only admin)
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause contract operations (only admin)
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Receive ETH deposits
     */
    receive() external payable {
        assetBalances[address(0)] += msg.value;
        emit FundsDeposited(msg.sender, msg.value);
    }
}
