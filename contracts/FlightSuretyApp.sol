pragma solidity ^0.5.8;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    uint256 private constant AIRLINES_THRESHOLD = 4;
    uint256 public constant MAX_INSURANCE_COST = 1 ether;
    uint256 public constant INSURANCE_RETURN_PERCENTAGE = 150;
    uint256 public constant MINIMUM_FUND = 10 ether;

    address private contractOwner;          // Account used to deploy contract

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;        
        address airline;
    }
    mapping(bytes32 => Flight) private flights;

    IFlightSuretyData internal flightSuretyData;

    mapping(address => mapping(address => bool)) private airVotes;
    mapping(address => uint256) private airVotesCount;

    event FlightRegistered(
        address airAcccount,
        string airName,
        uint256 timestamp
    );

    event FlightRegisteredDApp(
        bool success,
        uint256 votes
    );


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
    modifier requireIsOperational() {
        require(flightSuretyData.isOperational(), "Contract is currently not operational");
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /**
     * @dev Modifier that requires sender account to be the function caller
     */
    modifier requireIsAirline() {
        require(flightSuretyData.isAirline(msg.sender), "Caller is not registered airline");
        _;
    }

    /**
     * @dev Modifier that requires an airline account to be the function caller
     */
    modifier requireFundedAirline() {
        require(flightSuretyData.isAirlineFunded(msg.sender), "Caller airline is not funded");
        _;
    }

    /**
     * @dev Modifier that requires a timestamp to be of future
     */
    modifier requireIsFutureFlight(uint256 _timestamp) {
        require(_timestamp > block.timestamp, "Flight is not in future");
        _;
    }

    /**
     * @dev Modifier that requires a minimum fund to interact
     */
    modifier requireIsMinimumFunded() {
        require(msg.value >= MINIMUM_FUND, "Not enough funds");
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
    * @dev Contract constructor
    *
    */
    constructor(address payable dataContract) public {
        contractOwner = msg.sender;
        flightSuretyData = IFlightSuretyData(dataContract);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() public view returns(bool) {
        return flightSuretyData.isOperational();
    }

    function isAirline(address _airAcccount) public view returns(bool) {
        return flightSuretyData.isAirline(_airAcccount);
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

  
   /**
    * @dev Add an airline to the registration queue
    *
    */   
    function registerAirline(address _airAcccount, string calldata _airName) external requireIsOperational requireIsAirline requireFundedAirline returns(bool success, uint256 votes) {
        require(!isAirline(_airAcccount), "Airline is already registered");
        success = false;
        votes = 0;
        uint256 airlinesCount = flightSuretyData.getAirlinesCount();
    
        if (airlinesCount < AIRLINES_THRESHOLD) {
            flightSuretyData.registerAirline(_airAcccount, _airName);
            success = true;
        } else {
            uint256 votesNeeded = airlinesCount.mul(100).div(2);
            addVote(_airAcccount, msg.sender);
            votes = airVotesCount[_airAcccount];
            if (votes.mul(100) >= votesNeeded) {
                flightSuretyData.registerAirline(_airAcccount, _airName);
                success = true;
            }
        }
        emit FlightRegisteredDApp(success, votes);
    }

    /**
    * @dev Fund an airline
    * Returns true if the airline is funded (has received 10 ether).
    */
    function fund() external payable requireIsOperational requireIsAirline {
        flightSuretyData.fund.value(msg.value)(msg.sender);
    }


    /**
     * @dev Add votes to add an airline to the registration queue
     *
     */
    function addVote(address _airAcccount, address _callerairAcccount) internal {
        if (airVotes[_airAcccount][_callerairAcccount] == false) {
            airVotes[_airAcccount][_callerairAcccount] = true;
            airVotesCount[_airAcccount] = airVotesCount[_airAcccount].add(1);
        }
    }

   /**
    * @dev Register a future flight for insuring.
    *
    */  
    function registerFlight(string calldata _airName, uint256 _timestamp) external requireIsOperational requireIsAirline requireFundedAirline requireIsFutureFlight(_timestamp) {
        bytes32 flightKey = getFlightKey(msg.sender, _airName, _timestamp);
        flights[flightKey] = Flight(true, STATUS_CODE_UNKNOWN, block.timestamp, msg.sender);
        emit FlightRegistered(msg.sender, _airName, _timestamp);
    }

    /**
     * @dev Called after oracle has updated flight status
     *
     */
    function processFlightStatus(address _airAcccount, string memory _airName, uint256 _timestamp, uint8 _statusCode) internal {
        bytes32 flightKey = getFlightKey(_airAcccount, _airName, _timestamp);
        flights[flightKey].updatedTimestamp = block.timestamp;
        flights[flightKey].statusCode = _statusCode;
    }

    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(address _airAcccount, string calldata _airName, uint256 _timestamp) external {
        uint8 index = getRandomIndex(msg.sender);
        // Generate a unique key for storing the request
        bytes32 key = keccak256(abi.encodePacked(index, _airAcccount, _airName, _timestamp));
        oracleResponses[key] = ResponseInfo({requester: msg.sender, isOpen: true});
        emit OracleRequest(index, _airAcccount, _airName, _timestamp);
    }

    /**
     * @dev Buy insurance for a flight
     *
     */
    function buyInsurance(address _airAcccount, string calldata _airName, uint256 _timestamp) external payable requireIsOperational {
        require(!isAirline(msg.sender), "Caller is airline itself");
        require(block.timestamp < _timestamp, "Insurance is not before flight timestamp");
        require(msg.value <= MAX_INSURANCE_COST, "Value sent by caller is above insurance cost");
        bytes32 flightKey = getFlightKey(_airAcccount, _airName, _timestamp);
        require(flights[flightKey].isRegistered == true, "Airline is not registered");
        
        flightSuretyData.buy.value(msg.value)(msg.sender, _airAcccount, _airName, _timestamp);
    }

    /**
     *  @dev get amount paid by insuree
     *
     */
    function getAmountPaidByInsuree(address _airAcccount, string calldata _airName, uint256 _timestamp) external view returns(uint256) {
        bytes32 flightKey = getFlightKey(_airAcccount, _airName, _timestamp);
        require(flights[flightKey].isRegistered == true, "Flight not registered");

        return flightSuretyData.getAmountPaidByInsuree(msg.sender, _airAcccount, _airName, _timestamp);
    }

    /**
     * @dev Claim credit for a delayed flight.
     *
     */
    function claimCredit(address _airAcccount, string calldata _airName, uint256 _timestamp) external requireIsOperational {
        bytes32 flightKey = getFlightKey(_airAcccount, _airName, _timestamp);
        require(flights[flightKey].statusCode == STATUS_CODE_LATE_AIRLINE, "Flight status is not late");
        require(block.timestamp > flights[flightKey].updatedTimestamp, "Claim not allowed yet");
        
        flightSuretyData.creditInsurees(INSURANCE_RETURN_PERCENTAGE, _airAcccount, _airName, _timestamp);
    }

    /**
     * @dev Withdraw credits to insuree
     *
     */
    function withdrawCredits() external requireIsOperational {
        require(flightSuretyData.getInsureePayoutCredits(msg.sender) > 0, "No credits available");
        
        flightSuretyData.pay(msg.sender);
    }


// region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;    

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;


    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;        
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
                                                        // This lets us group responses and identify
                                                        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

    event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);


    // Register an oracle with the contract
    function registerOracle () external payable {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");
        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
    }

    function getMyIndexes() view external returns(uint8[3] memory){
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }




    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse
                        (
                            uint8 index,
                            address airline,
                            string calldata flight,
                            uint256 timestamp,
                            uint8 statusCode
                        )
                        external
    {
        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");


        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp)); 
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {

            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }


    function getFlightKey
                        (
                            address airline,
                            string memory flight,
                            uint256 timestamp
                        )
                        pure
                        internal
                        returns(bytes32) 
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes
                            (                       
                                address account         
                            )
                            internal
                            returns(uint8[3] memory)
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);
        
        indexes[1] = indexes[0];
        while(indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex
                            (
                                address account
                            )
                            internal
                            returns (uint8)
    {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

// endregion

}   

// Interface to the data contract FlightSuretyData.sol
interface IFlightSuretyData {
    function isOperational() external view returns(bool);
    function isAirline(address airAcccount) external view returns(bool);
    function isAirlineFunded(address airAcccount) external view returns(bool);
    function getAirlinesCount() external view returns(uint256);
    function registerAirline(address airAcccount, string calldata airName) external;
    function buy(address payable insureeAcc, address airAcccount, string calldata airName, uint256 timestamp) external payable;
    function getAmountPaidByInsuree(address payable insureeAcc, address airAcccount, string calldata airName, uint256 timestamp) external view returns(uint256 amountPaid);
    function creditInsurees(uint256 creditPercentage, address airAcccount, string calldata airName, uint256 timestamp) external;
    function getInsureePayoutCredits(address payable insureeAcc) external view returns(uint256 amount);
    function pay(address payable insureeAcc) external;
    function fund(address airAcccount) external payable;
}