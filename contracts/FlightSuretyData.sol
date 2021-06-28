pragma solidity ^0.5.8;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false

    mapping(address => bool) private authorizedCallers;     // Authorized Addresses for the smart contract
    
    // Data Struct for an Airline
    struct Airline {
        address airline; // account address of airline
        string name; // name of airline
        bool isRegistered; // is this airline registered or not
        bool isFunded; // is this airline funded or not
        uint256 fund; // amount of fund available
    }
    
    // To store & count airlines
    mapping(address => Airline) private airlines;
    uint256 internal airlinesCount = 0;


    // Data Struct for an Insurance
    struct Insurance {
        address payable insuree; // account address of insuree
        uint256 amount; // insurance amount
        address airline; // account address of airline
        string airlineName; // name of airline
        uint256 timestamp; // timestamp of airline
    }

    // Who's insured?
    mapping(bytes32 => Insurance[]) private insurances;
    // Payouts
    mapping(bytes32 => bool) private payoutCredited;
    // Credits
    mapping(address => uint256) private creditPayoutsToInsuree;




    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    event AirlineRegistered(address indexed airline, string airlineName);
    event AirlineFunded(address indexed airline, uint256 amount);
    event InsurancePurchased(address indexed insuree, uint256 amount, address airline, string airName, uint256 timestamp);
    event InsuranceCreditAvailable(address indexed airline, string indexed airName, uint256 indexed timestamp);
    event InsuranceCredited(address indexed insuree, uint256 amount);
    event InsurancePaid(address indexed insuree, uint256 amount);

    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor(address _airline, string memory _airlineName) public {
        contractOwner = msg.sender;
        addAirline(_airline, _airlineName);
    }


    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() 
    {
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireIsCallerAuthorized() {
        require(authorizedCallers[msg.sender] == true || msg.sender == contractOwner, "Caller is not authorized");
        _;
    }

    modifier requireIsAirline() {
        require(airlines[msg.sender].isRegistered == true, "Caller is not airline");
        _;
    }

    modifier requireFundedAirline(address _airline) {
        require(airlines[_airline].isFunded == true, "Airline is not funded");
        _;
    }

    modifier requireMsgData() {
        require(msg.data.length > 0, "Message data is empty");
        _;
    }


    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Add a new address to the list of authorized callers
     *      Can only be called by the contract owner
     */
    function authorizeCaller(address contractAddress) external requireContractOwner {
        authorizedCallers[contractAddress] = true;
    }

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */      
    function isOperational() external view returns(bool) {
        return operational;
    }

    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */    
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */   

    function registerAirline(address _airline, string calldata _airlineName) external requireIsCallerAuthorized {
        addAirline(_airline, _airlineName);
    }

    function addAirline(address _airline, string memory _airlineName) private {
        airlinesCount = airlinesCount.add(1);
        airlines[_airline] = Airline(_airline, _airlineName, true, false, 0);
        emit AirlineRegistered(_airline, _airlineName);
    }



   /**
    * @dev Buy insurance for a flight
    *
    */   
    function buy(address payable _insuree, address _airline, string calldata _flight, uint256 _timestamp)
    external payable {
        bytes32 flightKey = getFlightKey(_airline, _flight, _timestamp);
        airlines[_airline].fund = airlines[_airline].fund.add(msg.value);
        insurances[flightKey].push(
            Insurance(
                _insuree,
                msg.value,
                _airline,
                _flight,
                _timestamp
            )
        );
        emit InsurancePurchased(
            _insuree,
            msg.value,
            _airline,
            _flight,
            _timestamp
        );
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees(uint256 _creditPercentage, address _airline, string calldata _flight, uint256 _timestamp) 
    external requireIsCallerAuthorized {
        bytes32 flightKey = getFlightKey(_airline, _flight, _timestamp);
        require(!payoutCredited[flightKey], "Insurance payout was already made");
        for (uint i = 0; i < insurances[flightKey].length; i++) {
            address insuree = insurances[flightKey][i].insuree;
            uint256 amountToReceive = insurances[flightKey][i].amount.mul(_creditPercentage).div(100);
            creditPayoutsToInsuree[insuree] = creditPayoutsToInsuree[insuree].add(amountToReceive);
            airlines[_airline].fund = airlines[_airline].fund.sub(amountToReceive);
            emit InsuranceCredited(insuree, amountToReceive);
        }
        payoutCredited[flightKey] = true;
        emit InsuranceCreditAvailable(_airline, _flight, _timestamp);
    }
    

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay(address payable _insuree) external requireIsCallerAuthorized {
        uint256 amountToPay = creditPayoutsToInsuree[_insuree];
        delete(creditPayoutsToInsuree[_insuree]);
        _insuree.transfer(amountToPay);
        emit InsurancePaid(_insuree, amountToPay);
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */   
    function fund(address _airline) external payable requireIsCallerAuthorized {
        addFund(_airline, msg.value);
        airlines[_airline].isFunded = true;
        emit AirlineFunded(_airline, msg.value);
    }

    function addFund(address _airline, uint256 _fundValue) private {
        airlines[_airline].fund = airlines[_airline].fund.add(_fundValue);
    }

    function getFlightKey (address airline, string memory flight, uint256 timestamp) pure internal returns(bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }


    function isAirline(address _airline) external view returns(bool) {
        return airlines[_airline].isRegistered;
    }

    function isAirlineFunded(address _airline) external view requireIsCallerAuthorized returns(bool) {
        return airlines[_airline].isFunded;
    }

    function getFund(address _airline) external view requireIsCallerAuthorized returns(uint256) {
        return airlines[_airline].fund;
    }

    function getAirlinesCount() external view returns(uint256) {
        return airlinesCount;
    }


    function getAmountPaidByInsuree(address payable _insuree, address _airline, string calldata _flight, uint256 _timestamp) 
    external view returns(uint256 amountPaid) {
        amountPaid = 0;
        bytes32 flightKey = getFlightKey(_airline, _flight, _timestamp);
        
        for (uint i = 0; i < insurances[flightKey].length; i++) {
            if (insurances[flightKey][i].insuree == _insuree) {
                amountPaid = insurances[flightKey][i].amount;
                break;
            }
        }
    }

    function getInsureePayoutCredits(address payable _insuree) external view returns(uint256 amount) {
        return creditPayoutsToInsuree[_insuree];
    }

    /**
     * @dev Fallback function for funding smart contract.
     *
     */
    function () external payable requireMsgData requireIsAirline {
        addFund(msg.sender, msg.value);
        airlines[msg.sender].isFunded = true;
        emit AirlineFunded(msg.sender, msg.value);
    }

}

